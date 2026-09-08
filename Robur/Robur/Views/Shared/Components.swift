import SwiftUI
import SwiftData

struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var icon: String
    var color: Color = .roburAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Image(systemName: icon).foregroundStyle(color); Text(title).font(.caption).foregroundStyle(.secondary) }
            Text(value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.7)
            if let s = subtitle { Text(s).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct RingView: View {
    let progress: Double   // 0...1+
    var color: Color = .roburAccent
    var lineWidth: CGFloat = 10
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(progress, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: progress)
        }
    }
}

struct MacroBar: View {
    let label: String
    let value: Double
    let target: Double
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption.bold())
                Spacer()
                Text("\(value.g0) / \(target.g0) g").font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18))
                    Capsule().fill(color).frame(width: geo.size.width * min(1, target > 0 ? value / target : 0))
                }
            }
            .frame(height: 8)
        }
    }
}

/// Peso más reciente registrado (para cálculos).
struct LatestWeight {
    static func kg(context: ModelContext) -> Double {
        var d = FetchDescriptor<BodyMeasurement>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        return (try? context.fetch(d).first?.weightKg) ?? 75
    }
}

struct EmptyHint: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}

/// Foto desde disco con placeholder.
struct StoredPhoto: View {
    let filename: String
    var body: some View {
        if let img = PhotoStore.load(filename) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Rectangle().fill(.quaternary).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}
