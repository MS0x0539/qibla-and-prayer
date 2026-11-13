import SwiftUI

enum IbadahPart: String {
    case tasbih, tracker
}

/// Ibadah: the tasbih and the tracker (fasts and missed prayers) in one tab, switched at the top.
struct IbadahView: View {
    // `-ibadahPart tracker` opens the tracker (used for CI screenshots); afterwards the part last shown.
    @AppStorage("ibadahPart") private var part = IbadahPart.tasbih

    var body: some View {
        NavigationStack {
            Group {
                switch part {
                case .tasbih: TasbihView()
                case .tracker: TrackerView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Ibadah", selection: $part) {
                        Text("Tasbih").tag(IbadahPart.tasbih)
                        Text("Tracker").tag(IbadahPart.tracker)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
            }
        }
    }
}
