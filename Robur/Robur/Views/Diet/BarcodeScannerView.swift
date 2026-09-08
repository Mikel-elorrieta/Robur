import SwiftUI
import VisionKit
import SwiftData

struct BarcodeScannerView: View {
    let date: Date
    let meal: MealType
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var code: String?
    @State private var product: OpenFoodFactsService.Product?
    @State private var loading = false
    @State private var error: String?
    @State private var food: Food?

    var body: some View {
        NavigationStack {
            Group {
                if let e = error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                        Text(e).multilineTextAlignment(.center)
                        Button("Escanear otro") { error = nil; code = nil; product = nil }.buttonStyle(.borderedProminent)
                    }.padding()
                } else if loading {
                    ProgressView("Buscando \(code ?? "")…")
                } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerRepresentable { c in
                        guard code == nil else { return }
                        code = c
                        Task { await lookup(c) }
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        Text("Apunta al código de barras").padding(8).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 24)
                    }
                } else {
                    Text("El escáner no está disponible en este dispositivo.").padding()
                }
            }
            .navigationTitle("Escanear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .sheet(item: $food) { f in
                PortionSheet(food: f) { grams in
                    let fid = f.id
                    if let existing = try? context.fetch(FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.id == fid })).first {
                        existing.usageCount += 1
                        context.insert(MealEntry(date: date, mealType: meal, food: existing, grams: grams, source: "off"))
                    } else {
                        context.insert(f); f.usageCount = 1
                        context.insert(MealEntry(date: date, mealType: meal, food: f, grams: grams, source: "off"))
                    }
                    try? context.save()
                    dismiss()
                }
            }
        }
    }

    private func lookup(_ c: String) async {
        loading = true
        do {
            if let p = try await OpenFoodFactsService().product(barcode: c) { food = p.toFood() }
            else { error = "Producto \(c) no está en Open Food Facts. Créalo a mano desde \"Añadir\"." }
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                           qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems { if case .barcode(let b) = item, let s = b.payloadStringValue { onCode(s); return } }
        }
    }
}
