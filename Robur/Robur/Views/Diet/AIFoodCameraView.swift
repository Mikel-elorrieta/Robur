import SwiftUI
import SwiftData
import PhotosUI

/// Foto → Claude → lista editable de alimentos → diario.
struct AIFoodCameraView: View {
    let date: Date
    let meal: MealType
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.claudeModel) private var model = SettingsKey.defaultModel

    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var analyzing = false
    @State private var analysis: ClaudeVisionService.Analysis?
    @State private var items: [ClaudeVisionService.FoodEstimate] = []
    @State private var error: String?
    @State private var saveAsFood = false

    private var hasKey: Bool { !Keychain.get(account: Keychain.apiKeyAccount).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if !hasKey {
                    Section {
                        Label("Necesitas una API key de Anthropic. Ponla en Ajustes → Cámara IA.", systemImage: "key.fill").foregroundStyle(.orange)
                    }
                }
                Section {
                    if let img = image {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                    HStack {
                        Button { showCamera = true } label: { Label("Hacer foto", systemImage: "camera.fill") }
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        Spacer()
                        PhotosPicker(selection: $pickerItem, matching: .images) { Label("Galería", systemImage: "photo.on.rectangle") }
                    }.buttonStyle(.borderless)
                    if image != nil && analysis == nil {
                        Button {
                            Task { await analyze() }
                        } label: {
                            HStack { if analyzing { ProgressView().padding(.trailing, 4) }; Text(analyzing ? "Analizando…" : "Analizar con IA").bold() }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).disabled(analyzing || !hasKey)
                    }
                }
                if let e = error { Section { Text(e).foregroundStyle(.red).font(.subheadline) } }
                if let a = analysis {
                    Section {
                        ForEach($items) { $it in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    TextField("Alimento", text: $it.name).font(.headline)
                                    if let c = it.confidence { Text(c).font(.caption2).padding(4).background(Color(.tertiarySystemFill), in: Capsule()) }
                                }
                                HStack(spacing: 8) {
                                    num("g", $it.grams); num("kcal", $it.kcal); num("P", $it.protein); num("H", $it.carbs); num("G", $it.fat)
                                }
                            }
                        }
                        .onDelete { items.remove(atOffsets: $0) }
                    } header: {
                        HStack { Text(a.dishName); Spacer(); Text("\(items.reduce(0) { $0 + $1.kcal }.g0) kcal") }
                    } footer: {
                        Text(a.notes ?? "Estimación aproximada (±25 %). Corrige los gramos si lo ves raro.")
                    }
                    Section {
                        Toggle("Guardar también como alimento reutilizable", isOn: $saveAsFood)
                        Button { save() } label: { Text("Añadir a \(meal.label)").bold().frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).disabled(items.isEmpty)
                        Button("Reanalizar") { analysis = nil; items = [] }
                    }
                }
            }
            .navigationTitle("Cámara IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker { image = $0; analysis = nil; items = [] }.ignoresSafeArea() }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) { image = img; analysis = nil; items = [] }
                }
            }
        }
    }

    private func num(_ label: String, _ v: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            TextField("0", value: v, format: .number.precision(.fractionLength(0))).keyboardType(.decimalPad).multilineTextAlignment(.center)
                .padding(4).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func analyze() async {
        guard let img = image else { return }
        analyzing = true; error = nil
        do {
            let a = try await ClaudeVisionService().analyze(image: img, apiKey: Keychain.get(account: Keychain.apiKeyAccount), model: model)
            analysis = a; items = a.items
        } catch { self.error = error.localizedDescription }
        analyzing = false
    }

    private func save() {
        let photo = image.flatMap { PhotoStore.save($0, maxSide: 800) }
        for (i, it) in items.enumerated() {
            context.insert(MealEntry(date: date, mealType: meal, name: it.name, grams: it.grams, kcal: it.kcal, protein: it.protein,
                                     carbs: it.carbs, fat: it.fat, source: "ai", photoFilename: i == 0 ? photo : nil))
            if saveAsFood, it.grams > 0 {
                let f = it.grams / 100
                context.insert(Food(name: it.name, kcal: it.kcal / f, protein: it.protein / f, carbs: it.carbs / f, fat: it.fat / f,
                                    servingGrams: it.grams, category: "IA", source: "ai"))
            }
        }
        try? context.save()
        dismiss()
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
