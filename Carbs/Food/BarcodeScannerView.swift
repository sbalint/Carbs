import SwiftUI
import VisionKit

/// Live barcode scanner. Not available in the Simulator, which offers manual entry instead.
struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var onScan: (String) -> Void
    @State private var manualCode = ""

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerRepresentable(onScan: onScan).ignoresSafeArea()
                } else {
                    Form {
                        Section {
                            TextField("Barcode number", text: $manualCode).keyboardType(.numberPad)
                            Button("Look up") { onScan(manualCode) }.disabled(manualCode.count < 6)
                        } footer: {
                            Text("The camera scanner isn't available on this device, so type the number under the barcode.")
                        }
                    }
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var done = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    done = true
                    dataScanner.stopScanning()
                    onScan(value)
                    return
                }
            }
        }
    }
}
