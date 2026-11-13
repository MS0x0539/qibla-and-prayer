import AVFoundation
import SwiftUI

/// The Qibla on the live camera picture: hold the phone upright, and a star marks where Mecca lies; off the picture,
/// an arrow at the edge shows which way to turn. Uses the same compass as the Qibla dial; nothing is recorded.
struct QiblaCameraView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var camera = QiblaCamera()
    @State private var aligned = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if camera.state == .running {
                    CameraPreview(session: camera.session)
                }
                overlay(size: geometry.size)
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .top) { topBar }
        .task {
            model.location.startHeading()
            await camera.start()
        }
        .onDisappear { camera.stop() }
        .sensoryFeedback(.success, trigger: aligned) { _, new in new }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Qibla")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                Text("Hold your phone upright and turn until the star is in the middle.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .accessibilityLabel(Text("Close"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private func overlay(size: CGSize) -> some View {
        switch camera.state {
        case .denied:
            message("Allow camera access in iPhone Settings to see the Qibla on the camera picture.", settings: true)
        case .unavailable:
            message("This device has no camera that can show the Qibla.", settings: false)
        default:
            if let place = model.qiblaPlace, let heading = model.location.heading {
                let offset = QiblaView.signedOffset(place.qibla - heading)
                marker(offset: offset, distance: place.kilometresToMecca, size: size)
                    .onChange(of: offset, initial: true) { _, new in
                        // As on the dial: within 3° counts as facing it, beyond 5° no longer.
                        if abs(new) <= 3 { aligned = true } else if abs(new) > 5 { aligned = false }
                    }
            } else {
                ProgressView().tint(.white)
            }
        }
    }

    /// The star where Mecca lies on the picture, or an arrow at the edge when it is outside it.
    private func marker(offset: Double, distance: Double, size: CGSize) -> some View {
        let half = camera.horizontalFieldOfView(for: size) / 2
        let visible = abs(offset) < half
        let x = visible ? size.width / 2 + tan(offset * .pi / 180) / tan(half * .pi / 180) * size.width / 2
                        : (offset > 0 ? size.width - 40 : 40)
        return ZStack {
            // The aim: the middle of the picture.
            Rectangle()
                .fill(.white.opacity(0.35))
                .frame(width: 1, height: size.height * 0.4)
                .position(x: size.width / 2, y: size.height / 2)
            if visible {
                VStack(spacing: 8) {
                    EightPointStar()
                        .fill(aligned ? Theme.gold : .white)
                        .frame(width: 54, height: 54)
                        .shadow(radius: 6)
                    Text("Mecca \(Formats.distance(distance))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                .position(x: x, y: size.height / 2)
            } else {
                Image(systemName: offset > 0 ? "chevron.right.circle.fill" : "chevron.left.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white, Theme.gold)
                    .shadow(radius: 6)
                    .position(x: x, y: size.height / 2)
                    .accessibilityHidden(true)
            }
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
            .foregroundStyle(aligned ? Theme.gold : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
            .position(x: size.width / 2, y: size.height - 120)
        }
    }

    private func message(_ text: LocalizedStringKey, settings: Bool) -> some View {
        VStack(spacing: 16) {
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if settings {
                Button("Open Settings") { openAppSettings() }
                    .buttonStyle(.bordered)
                    .tint(Theme.gold)
            }
        }
        .padding(32)
    }
}

/// The back camera, running only while the Qibla camera is shown; nothing is recorded or saved.
@MainActor @Observable
final class QiblaCamera {
    enum State { case starting, running, denied, unavailable }

    private(set) var state = State.starting
    let session = AVCaptureSession()
    /// The camera's field of view along the long side of its picture, in degrees.
    private var fieldOfView = 65.0

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }
        if session.inputs.isEmpty {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                state = .unavailable
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .high
            session.addInput(input)
            session.commitConfiguration()
            fieldOfView = Double(device.activeFormat.videoFieldOfView)
        }
        let session = session
        // startRunning blocks until the camera runs: off the main thread.
        await Task.detached { session.startRunning() }.value
        state = .running
    }

    func stop() {
        let session = session
        Task.detached { session.stopRunning() }
    }

    /// What the picture shows across the screen, held upright: the short side of the 4:3 picture, cropped to fill
    /// the taller screen.
    func horizontalFieldOfView(for size: CGSize) -> Double {
        guard size.width > 0, size.height > 0 else { return 40 }
        let shortSide = tan(fieldOfView / 2 * .pi / 180) * 3 / 4
        let shown = min(1, (size.width / size.height) / (3.0 / 4.0))
        return 2 * atan(shortSide * shown) * 180 / .pi
    }
}

/// The camera picture, filling the view.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // swiftlint:disable:next force_cast
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
