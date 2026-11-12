import MapKit
import SwiftUI

/// The Qibla as a line on the map (the shortest way over the globe to the Kaaba), with mosques nearby.
struct QiblaMapView: View {
    @Environment(AppModel.self) private var model
    @State private var position = MapCameraPosition.automatic
    @State private var showingWhole = false
    @State private var mosques: [MKMapItem] = []
    @State private var search = SearchState.loading
    /// The camera is placed once, and mosques are searched once per place, not on every return to the map.
    @State private var framed = false
    @State private var searchedKey: String?

    private enum SearchState { case loading, done, failed }

    var body: some View {
        Group {
            if let place = model.qiblaPlace {
                content(place)
            } else {
                NoPlaceView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Qibla map")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ place: Place) -> some View {
        let here = place.coordinate
        return VStack(spacing: 0) {
            Map(position: $position) {
                MapPolyline(coordinates: [here, Prayers.kaaba], contourStyle: .geodesic)
                    .stroke(Theme.gold, lineWidth: 4)
                Annotation("Kaaba", coordinate: Prayers.kaaba) {
                    Image(systemName: "cube.fill")
                        .foregroundStyle(Theme.gold)
                        .padding(6)
                        .background(Theme.background, in: Circle())
                }
                if model.location.isAuthorized {
                    UserAnnotation()
                } else {
                    Marker(place.displayName, coordinate: here)
                        .tint(Theme.gold)
                }
                ForEach(mosques, id: \.self) { item in
                    Marker(item: item)
                        .tint(Theme.gold)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            mosqueList(from: here)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingWhole.toggle()
                    withAnimation { position = showingWhole ? .automatic : .region(nearby(here)) }
                } label: {
                    Image(systemName: showingWhole ? "location" : "globe.europe.africa")
                }
                .accessibilityLabel(showingWhole ? Text("Show nearby") : Text("Show the whole line"))
            }
        }
        .onAppear {
            guard !framed else { return }
            framed = true
            position = .region(nearby(here))
        }
        .task(id: "\(place.latitude),\(place.longitude)") { await findMosques(near: here) }
    }

    private func mosqueList(from here: CLLocationCoordinate2D) -> some View {
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        return List {
            Section {
                switch search {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                case .failed:
                    Text("Mosques nearby could not be loaded. Check your internet connection.")
                        .foregroundStyle(Theme.muted)
                case .done where mosques.isEmpty:
                    Text("No mosques found nearby.")
                        .foregroundStyle(Theme.muted)
                case .done:
                    ForEach(mosques, id: \.self) { item in
                        Button {
                            item.openInMaps()
                        } label: {
                            HStack {
                                Text(verbatim: item.name ?? "")
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(verbatim: distanceText(distance(item, from: origin)))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            } header: {
                Text("Mosques nearby")
            } footer: {
                Text("Tap a mosque to open it in Apple Maps. Not every mosque is on the map.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .frame(height: 280)
    }

    private func nearby(_ here: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: here, latitudinalMeters: 5_000, longitudinalMeters: 5_000)
    }

    private func findMosques(near here: CLLocationCoordinate2D) async {
        let key = "\(here.latitude),\(here.longitude)"
        guard key != searchedKey else { return }
        let request = MKLocalSearch.Request()
        // shortcut: one English query; Apple Maps matches it to mosques in other countries too.
        request.naturalLanguageQuery = "mosque"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: here, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        do {
            let items = try await MKLocalSearch(request: request).start().mapItems
            let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
            mosques = items.sorted { distance($0, from: origin) < distance($1, from: origin) }
            searchedKey = key
            search = .done
        } catch let error as MKError where error.code == .placemarkNotFound {
            // "Nothing found" also arrives as an error.
            mosques = []
            searchedKey = key
            search = .done
        } catch {
            // Offline or throttled: keep what an earlier search found.
            if mosques.isEmpty { search = .failed }
        }
    }

    private func distance(_ item: MKMapItem, from origin: CLLocation) -> CLLocationDistance {
        let coordinate = item.placemark.coordinate
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: origin)
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        let formatter = MKDistanceFormatter()
        formatter.locale = .app
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: meters)
    }
}
