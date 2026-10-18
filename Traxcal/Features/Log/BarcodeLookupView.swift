import SwiftUI
import VisionKit

/// Live barcode scanning (VisionKit) → Open Food Facts lookup → food detail.
struct BarcodeLookupView: View {
    var onDone: () -> Void

    @State private var scanned: String?
    @State private var item: FoodItem?
    @State private var isLooking = false
    @State private var message: String?
    @State private var manualCode = ""

    var body: some View {
        VStack(spacing: 16) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                BarcodeScanner { code in
                    guard scanned != code, !isLooking else { return }
                    scanned = code
                    Haptics.success()
                    Task { await lookup(code) }
                }
                .clipShape(.rect(cornerRadius: Theme.corner))
                .overlay(alignment: .center) {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Palette.water, style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                        .frame(width: 260, height: 150)
                }
                .overlay(alignment: .bottom) {
                    if isLooking {
                        Label("Looking up \(scanned ?? "")…", systemImage: "magnifyingglass")
                            .padding(12).glassEffect(.regular, in: .capsule).padding()
                    }
                }
            } else {
                ContentUnavailableView("Scanner unavailable", systemImage: "barcode.viewfinder",
                                       description: Text("Enter the barcode number below."))
            }

            if let message {
                Text(message).font(.subheadline).foregroundStyle(Palette.warning).multilineTextAlignment(.center)
            }

            HStack {
                TextField("Barcode number", text: $manualCode)
                    .keyboardType(.numberPad)
                    .padding(12)
                    .glassEffect(.regular, in: .capsule)
                Button("Look up") { Task { await lookup(manualCode) } }
                    .buttonStyle(.glassProminent)
                    .disabled(manualCode.count < 6)
            }
        }
        .padding(16)
        .navigationTitle("Scan Barcode")
        .sheet(item: $item) { FoodDetailView(item: $0, onLogged: onDone) }
    }

    private func lookup(_ code: String) async {
        isLooking = true
        message = nil
        defer { isLooking = false }
        do {
            if let found = try await OpenFoodFactsProvider().lookup(barcode: code) {
                item = found
            } else {
                message = "Product \(code) isn't in Open Food Facts yet. Try search or Quick Add."
                Haptics.warning()
            }
        } catch {
            message = "Lookup failed: \(error.localizedDescription)"
            Haptics.error()
        }
        // Allow re-scanning the same code after the sheet closes.
        scanned = nil
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    onCode(value)
                    return
                }
            }
        }
    }
}
