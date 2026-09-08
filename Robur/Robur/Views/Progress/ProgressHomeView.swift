import SwiftUI
import SwiftData
import Charts
import PhotosUI

struct ProgressHomeView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @State private var showAdd = false
    @State private var range: Int = 90   // días en gráfico
    @State private var compare = false

    private var chartData: [BodyMeasurement] {
        let from = Date.now.adding(days: -range)
        return measurements.filter { range == 0 || $0.date >= from }.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if measurements.count >= 2 { deltaHeader }
                    Picker("Rango", selection: $range) {
                        Text("1 mes").tag(30); Text("3 meses").tag(90); Text("6 meses").tag(180); Text("1 año").tag(365); Text("Todo").tag(0)
                    }.pickerStyle(.segmented)
                    if chartData.count >= 2 { weightChart } else { EmptyHint(icon: "chart.xyaxis.line", text: "Con dos pesajes ya sale gráfico.") }
                }
                if measurements.contains(where: { !$0.photoFilenames.isEmpty }) {
                    Section {
                        NavigationLink { PhotoGalleryView(measurements: measurements) } label: { Label("Galería de fotos", systemImage: "photo.stack") }
                        NavigationLink { ComparePhotosView(measurements: measurements) } label: { Label("Comparar antes / después", systemImage: "rectangle.split.2x1") }
                    }
                }
                Section("Registros") {
                    ForEach(measurements) { m in
                        NavigationLink { MeasurementDetailView(m: m) } label: { MeasurementRow(m: m, previous: previous(of: m)) }
                    }
                    .onDelete { idx in
                        idx.map { measurements[$0] }.forEach { m in m.photoFilenames.forEach(PhotoStore.delete); context.delete(m) }
                        try? context.save()
                    }
                }
            }
            .navigationTitle("Progreso")
            .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $showAdd) { AddMeasurementView(profile: profile) }
        }
    }

    private func previous(of m: BodyMeasurement) -> BodyMeasurement? {
        guard let i = measurements.firstIndex(where: { $0.persistentModelID == m.persistentModelID }), i + 1 < measurements.count else { return nil }
        return measurements[i + 1]
    }

    private var deltaHeader: some View {
        let latest = measurements[0], first = chartData.first ?? measurements[measurements.count - 1]
        let delta = latest.weightKg - first.weightKg
        return HStack {
            VStack(alignment: .leading) {
                Text("\(latest.weightKg.g1) kg").font(.system(size: 34, weight: .bold, design: .rounded))
                Text(latest.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(delta >= 0 ? "+" : "")\(delta.g1) kg").font(.title3.bold()).foregroundStyle(deltaColor(delta))
                Text("desde \(first.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func deltaColor(_ d: Double) -> Color {
        switch profile.goal {
        case .cut: return d <= 0 ? .green : .orange
        case .bulk: return d >= 0 ? .green : .orange
        case .maintain: return abs(d) < 1 ? .green : .orange
        }
    }

    private var weightChart: some View {
        let minW = (chartData.map(\.weightKg).min() ?? 60) - 1.5
        let maxW = (chartData.map(\.weightKg).max() ?? 90) + 1.5
        return Chart(chartData) { m in
            AreaMark(x: .value("Fecha", m.date), yStart: .value("min", minW), yEnd: .value("kg", m.weightKg))
                .foregroundStyle(LinearGradient(colors: [.roburAccent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Fecha", m.date), y: .value("kg", m.weightKg))
                .foregroundStyle(Color.roburAccent).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2.5))
            PointMark(x: .value("Fecha", m.date), y: .value("kg", m.weightKg)).foregroundStyle(Color.roburAccent)
                .symbol {
                    Circle().strokeBorder(Color.roburAccent, lineWidth: 2).background(Circle().fill(Color(.systemBackground)))
                        .frame(width: m.photoFilenames.isEmpty ? 7 : 11, height: m.photoFilenames.isEmpty ? 7 : 11)
                }
        }
        .chartYScale(domain: minW...maxW)
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 220)
        .padding(.vertical, 4)
    }
}

struct MeasurementRow: View {
    let m: BodyMeasurement
    let previous: BodyMeasurement?
    var body: some View {
        HStack(spacing: 12) {
            if let f = m.photoFilenames.first {
                StoredPhoto(filename: f).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "scalemass").frame(width: 44, height: 44).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.weightKg.g1) kg").font(.headline)
                Text(m.date.formatted(date: .abbreviated, time: .omitted) + (m.bodyFatPct.map { " · \($0.g1) % grasa" } ?? "")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let p = previous {
                let d = m.weightKg - p.weightKg
                Text("\(d >= 0 ? "+" : "")\(d.g1)").font(.subheadline.monospacedDigit()).foregroundStyle(d == 0 ? Color.secondary : (d < 0 ? Color.green : Color.orange))
            }
        }
    }
}

struct AddMeasurementView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var health
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]

    @State private var date = Date.now
    @State private var weight: Double = 75
    @State private var fat: Double?
    @State private var waist: Double?
    @State private var notes = ""
    @State private var images: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                    HStack { Text("Peso"); Spacer(); TextField("kg", value: $weight, format: .number.precision(.fractionLength(1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90); Text("kg") }
                    HStack { Text("% grasa (opcional)"); Spacer(); TextField("—", value: $fat, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }
                    HStack { Text("Cintura (opcional)"); Spacer(); TextField("cm", value: $waist, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90); Text("cm") }
                    TextField("Notas", text: $notes, axis: .vertical)
                }
                Section("Fotos (frente, perfil, espalda…)") {
                    if !images.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                                    Image(uiImage: img).resizable().scaledToFill().frame(width: 90, height: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button { images.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6)) }.padding(4)
                                        }
                                }
                            }
                        }
                    }
                    HStack {
                        Button { showCamera = true } label: { Label("Cámara", systemImage: "camera.fill") }.disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        Spacer()
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) { Label("Galería", systemImage: "photo.on.rectangle") }
                    }.buttonStyle(.borderless)
                }
            }
            .navigationTitle("Nuevo registro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(weight < 30) }
            }
            .onAppear { weight = measurements.first?.weightKg ?? 75 }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker { images.append($0) }.ignoresSafeArea() }
            .onChange(of: pickerItems) { _, items in
                Task {
                    for it in items { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { images.append(img) } }
                    pickerItems = []
                }
            }
        }
    }

    private func save() {
        let files = images.compactMap { PhotoStore.save($0) }
        let m = BodyMeasurement(date: date, weightKg: weight, bodyFatPct: fat, waistCm: waist, notes: notes, photoFilenames: files)
        context.insert(m)
        try? context.save()
        Reminders.scheduleWeighIn(afterDays: profile.weighInReminderDays, from: date)
        if AppSettings.healthKitEnabled && AppSettings.autoSaveWeight {
            Task { try? await health.saveBodyMass(kg: weight, date: date) }
        }
        dismiss()
    }
}

struct MeasurementDetailView: View {
    @Bindable var m: BodyMeasurement
    var body: some View {
        List {
            Section {
                LabeledContent("Fecha", value: m.date.formatted(date: .long, time: .omitted))
                LabeledContent("Peso", value: "\(m.weightKg.g1) kg")
                if let f = m.bodyFatPct { LabeledContent("% grasa", value: f.g1) }
                if let w = m.waistCm { LabeledContent("Cintura", value: "\(w.g1) cm") }
                if !m.notes.isEmpty { Text(m.notes) }
            }
            if !m.photoFilenames.isEmpty {
                Section("Fotos") {
                    ForEach(m.photoFilenames, id: \.self) { f in
                        StoredPhoto(filename: f).frame(maxWidth: .infinity).frame(height: 420).clipShape(RoundedRectangle(cornerRadius: 12)).listRowInsets(EdgeInsets())
                    }
                }
            }
        }
        .navigationTitle(m.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PhotoGalleryView: View {
    let measurements: [BodyMeasurement]
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 6)]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(measurements.filter { !$0.photoFilenames.isEmpty }) { m in
                    ForEach(m.photoFilenames, id: \.self) { f in
                        NavigationLink { MeasurementDetailView(m: m) } label: {
                            StoredPhoto(filename: f).frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .bottomLeading) {
                                    Text("\(m.weightKg.g1) kg · \(m.date.formatted(.dateTime.day().month()))").font(.caption2.bold())
                                        .padding(4).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.white).padding(4)
                                }
                        }
                    }
                }
            }.padding(6)
        }
        .navigationTitle("Fotos")
    }
}

struct ComparePhotosView: View {
    let measurements: [BodyMeasurement]
    @State private var left: BodyMeasurement?
    @State private var right: BodyMeasurement?
    private var withPhotos: [BodyMeasurement] { measurements.filter { !$0.photoFilenames.isEmpty } }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                slot(left, title: "Antes")
                slot(right, title: "Después")
            }
            .frame(maxHeight: .infinity)
            HStack {
                picker("Antes", $left); picker("Después", $right)
            }
            if let l = left, let r = right {
                let d = r.weightKg - l.weightKg
                Text("\(d >= 0 ? "+" : "")\(d.g1) kg en \(Calendar.current.dateComponents([.day], from: l.date, to: r.date).day ?? 0) días").font(.headline)
            }
        }
        .padding()
        .navigationTitle("Comparar")
        .onAppear { if left == nil { left = withPhotos.last; right = withPhotos.first } }
    }

    private func slot(_ m: BodyMeasurement?, title: String) -> some View {
        VStack {
            if let m, let f = m.photoFilenames.first {
                StoredPhoto(filename: f).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("\(m.weightKg.g1) kg · \(m.date.formatted(date: .abbreviated, time: .omitted))").font(.caption)
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.quaternary).overlay(Text(title).foregroundStyle(.secondary))
            }
        }
    }

    private func picker(_ title: String, _ sel: Binding<BodyMeasurement?>) -> some View {
        Menu {
            ForEach(withPhotos) { m in Button("\(m.date.formatted(date: .abbreviated, time: .omitted)) · \(m.weightKg.g1) kg") { sel.wrappedValue = m } }
        } label: { Label(title, systemImage: "calendar").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
    }
}
