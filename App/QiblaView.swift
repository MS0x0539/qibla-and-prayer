import CoreLocation
import SwiftUI

struct QiblaView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var readoutSize: CGFloat = 52
    @State private var aligned = false
    @State private var showingHelp = false
    // `-showMap YES` opens the map first (used for CI screenshots).
    @State private var showingMap = UserDefaults.standard.bool(forKey: "showMap")
    @State private var showingCamera = false
    // `-showLive YES` opens Makkah live first (used for CI screenshots).
    @State private var showingLive = UserDefaults.standard.bool(forKey: "showLive")
    /// The compass's size: 300 points, or as much less (down to 200) as the page needs to fit the screen unscrolled.
    @State private var dial: CGFloat = 300

    /// The turn from the phone's heading to the Qibla: negative is left, positive is right.
    private var offset: Double? {
        guard let place = model.qiblaPlace, let heading = model.location.heading else { return nil }
        return QiblaView.signedOffset(place.qibla - heading)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Text("Qibla")
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    Text("Hold your phone flat, away from magnets.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                    if let place = model.qiblaPlace {
                        compass(place)
                    } else {
                        NoPlaceView()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The compass gives up as much as the page reaches past the screen, or takes back room left over (up to
            // 300); with large text the page still scrolls, the compass at 200.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                    - geometry.containerSize.height
            } action: { _, overflow in
                dial = min(300, max(200, (dial - overflow).rounded(.down)))
            }
            .foregroundStyle(Theme.ink)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingHelp = true } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel(Text("How to use the compass"))
                }
            }
            .sheet(isPresented: $showingHelp) { CompassHelp() }
            .navigationDestination(isPresented: $showingMap) { QiblaMapView() }
            .navigationDestination(isPresented: $showingLive) { MakkahLiveView() }
            .fullScreenCover(isPresented: $showingCamera) { QiblaCameraView() }
        }
        .onAppear { model.location.startHeading() }
        .onDisappear { model.location.stopHeading() }
        .onChange(of: offset, initial: true) { _, new in
            // Line up within 3°, let go only beyond 5°, so the haptic doesn't stutter at the edge.
            // A negative accuracy means the heading is invalid: no "Facing the Qibla" or haptic then.
            guard let new, model.location.headingAccuracy >= 0 else {
                aligned = false
                return
            }
            aligned = abs(new) <= (aligned ? 5 : 3)
        }
        .sensoryFeedback(.success, trigger: aligned) { _, isAligned in isAligned }
    }

    @ViewBuilder
    private func compass(_ place: Place) -> some View {
        let qibla = place.qibla
        let location = model.location

        VStack(spacing: 16) {
            Triangle()
                .fill(aligned ? Theme.gold : Theme.muted)
                .frame(width: 16, height: 14)
            ZStack {
                Circle()
                    .strokeBorder(aligned ? Theme.gold : Theme.gold.opacity(0.3), lineWidth: aligned ? 3 : 1)
                    .padding(-8)
                Dial(qibla: qibla, heading: location.continuousHeading)
                    .rotationEffect(.degrees(-location.continuousHeading))
                EightPointStar()
                    .fill(aligned ? Theme.gold : Color.clear)
                    .overlay(EightPointStar().stroke(Theme.gold, lineWidth: 1.5))
                    .frame(width: 84, height: 84)
            }
            .frame(width: 300, height: 300)
            // Drawn at 300 points, shown at the size that fits.
            .scaleEffect(dial / 300)
            .frame(width: dial, height: dial)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: location.continuousHeading)
            // A compass shows physical directions: it must never be mirrored for right-to-left languages.
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
        }
        .padding(.top, 26)

        if let heading = location.heading, let offset {
            Text(verbatim: Formats.bearing(heading))
                .font(.system(size: readoutSize, weight: .medium, design: .serif).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 24)
            Group {
                if aligned {
                    Text("Facing the Qibla")
                } else if offset > 0 {
                    Text("Turn right \(Int(abs(offset).rounded()))°")
                } else {
                    Text("Turn left \(Int(abs(offset).rounded()))°")
                }
            }
            .font(.headline)
            .foregroundStyle(aligned ? Theme.gold : Theme.ink)
            .accessibilityAddTraits(.updatesFrequently)
            if location.headingAccuracy < 0 || location.headingAccuracy > 20 {
                Text("Low accuracy: move your phone in a figure eight.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            if !location.isAuthorized {
                Text("Without location access the compass uses magnetic north, which can be a few degrees off.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        } else if CLLocationManager.headingAvailable() {
            // The first heading takes a moment; don't claim there is no compass meanwhile.
            ProgressView()
                .padding(.top, 24)
        } else {
            Text("This device has no compass. The Qibla is at \(Int(qibla.rounded()))° from north.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
        }

        HStack(spacing: 6) {
            Text("Qibla \(Formats.bearing(qibla))")
            // A dot drawn, not typed: decoration, not text.
            Circle().fill(Theme.gold).frame(width: 3, height: 3)
                .accessibilityHidden(true)
            Text("Mecca \(Formats.distance(place.kilometresToMecca))")
        }
        .accessibilityElement(children: .combine)
        .font(.subheadline)
        .foregroundStyle(Theme.muted)
        .padding(.top, 22)

        Button { showingMap = true } label: {
            Label("Map and mosques nearby", systemImage: "map")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .foregroundStyle(Theme.gold)
        .padding(.top, 18)

        HStack(spacing: 12) {
            Button { showingCamera = true } label: {
                Label("Camera", systemImage: "camera")
            }
            Button { showingLive = true } label: {
                Label("Makkah live", systemImage: "play.tv")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .foregroundStyle(Theme.gold)
        .padding(.top, 10)
    }

    /// The turn from the current heading to the Qibla, between -180° (left) and 180° (right).
    static func signedOffset(_ degrees: Double) -> Double {
        (degrees + 540).truncatingRemainder(dividingBy: 360) - 180
    }
}

/// The part that turns: ticks, N/E/S/W and the Kaaba marker on the rim at the Qibla bearing.
private struct Dial: View {
    let qibla: Double
    /// The dial turns by -heading; the letters turn back by the same amount so they stay upright.
    let heading: Double

    var body: some View {
        ZStack {
            ForEach(0..<72, id: \.self) { index in
                let major = index % 6 == 0
                Rectangle()
                    .fill(major ? Theme.gold : Theme.gold.opacity(0.45))
                    .frame(width: major ? 2 : 1, height: major ? 14 : 8)
                    .offset(y: major ? -135 : -138)
                    .rotationEffect(.degrees(Double(index) * 5))
            }
            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, letter in
                Text(LocalizedStringKey(letter))
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(index == 0 ? Theme.gold : Theme.ink)
                    .rotationEffect(.degrees(heading - Double(index) * 90))
                    .offset(y: -108)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            // From the central star to the marker, which sits on the rim, clear of the letters.
            Rectangle()
                .fill(Theme.gold.opacity(0.55))
                .frame(width: 2, height: 92)
                .offset(y: -90)
                .rotationEffect(.degrees(qibla))
            KaabaMarker()
                .offset(y: -150)
                .rotationEffect(.degrees(qibla))
        }
        .frame(width: 300, height: 300)
    }
}

private struct KaabaMarker: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: 0x0B0F0E))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.gold, lineWidth: 1.5))
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.gold).frame(height: 3).padding(.top, 6)
            }
            .frame(width: 24, height: 24)
    }
}

/// How to use the compass, from the (i) button.
private struct CompassHelp: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HelpStep(number: 1, text: "Hold your phone flat in front of you, screen up.")
                    HelpStep(number: 2, text: "Turn slowly until the gold Kaaba marker reaches the mark at the top. The star fills in and your phone taps once.")
                    HelpStep(number: 3, text: "Keep away from metal, magnets and other electronics: they disturb the compass. If the accuracy is low, move your phone in a figure eight.")
                    Text("The Qibla is the direction of the Kaaba in Mecca, calculated from your location along the shortest route over the globe and measured from true north.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.ink)
                .padding(24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("How to use the compass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct HelpStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: Formats.number(number))
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.background)
                .frame(width: 28, height: 28)
                .background(Theme.gold, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
