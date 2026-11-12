import MapKit
import Observation
import SwiftUI

/// City search with Apple Maps suggestions as you type (no extra service).
@Observable
final class CitySearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    func place(for completion: MKLocalSearchCompletion) async -> Place? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let item = try? await search.start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        return Place(
            name: completion.title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneID: (item.timeZone ?? .current).identifier,
            countryCode: item.placemark.isoCountryCode)
    }
}

struct CitySearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var search = CitySearch()

    var body: some View {
        List(search.results, id: \.self) { result in
            Button {
                Task {
                    if let place = await search.place(for: result) {
                        model.chooseCity(place)
                        dismiss()
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .foregroundStyle(Theme.ink)
                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("City")
        .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search for a city"))
    }
}
