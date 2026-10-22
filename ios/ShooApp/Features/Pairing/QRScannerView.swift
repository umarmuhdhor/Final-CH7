import AVFoundation
import SwiftUI
import VisionKit

/// PR-01 "Scan QR": live camera, QR codes only, nothing recorded or saved (SECURITY §3 P7).
/// The camera permission is asked only when this tab is opened.
struct QRScannerView: View {
    let onPayload: (String) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var access: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private var scannerAvailable: Bool {
        AppConfig.cameraEnabled && DataScannerViewController.isSupported
    }

    @State private var scannerFailed = false

    var body: some View {
        Group {
            if !scannerAvailable {
                note("Scanning isn't available on this iPhone. Enter the code instead.")
            } else {
                switch access {
                case .authorized where !DataScannerViewController.isAvailable || scannerFailed:
                    // Camera restricted (Screen Time) or busy.
                    note("Scanning isn't available right now. Enter the code instead.")
                case .authorized:
                    QRScannerRepresentable(onPayload: onPayload, onFailure: { scannerFailed = true })
                        .frame(minHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(Text("Camera. Point it at the QR code on your guardian's phone."))
                case .notDetermined:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                default:
                    VStack(spacing: 12) {
                        note("Shoo can't use the camera. Allow it in Settings, or enter the code instead.")
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
        .task {
            guard scannerAvailable, access == .notDetermined else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            access = AVCaptureDevice.authorizationStatus(for: .video)
        }
        // Back from Settings with the camera allowed, or the camera free again: try once more.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            access = AVCaptureDevice.authorizationStatus(for: .video)
            scannerFailed = false
        }
        .onAppear { scannerFailed = false }
        .accessibilityIdentifier("connect.scanner")
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.readableSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onPayload: (String) -> Void
    let onFailure: () -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            Log.ui.error("QR scanner failed", error)
            DispatchQueue.main.async(execute: onFailure)
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onPayload: (String) -> Void
        private var lastPayload: String?

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in items {
                // The same code seen again (it left the frame and came back) is answered once.
                guard let payload = barcode.payloadStringValue, payload != lastPayload else { continue }
                lastPayload = payload
                onPayload(payload)
            }
        }
    }
}
