import Foundation

/// Búsqueda de productos en Open Food Facts (por texto y por código de barras). Sin auth; solo User-Agent.
struct OpenFoodFactsService {
    static let userAgent = "Robur/1.0 (app personal iOS)"

    struct Product: Identifiable, Hashable {
        let id: String          // barcode
        let name: String
        let brand: String?
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double
        let servingGrams: Double?

        func toFood() -> Food {
            Food(id: "off_\(id)", name: name, brand: brand, kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                 fiber: fiber, servingGrams: servingGrams ?? 100, category: "Open Food Facts", source: "off", barcode: id)
        }
    }

    private struct SearchResponse: Decodable { let products: [RawProduct] }
    private struct BarcodeResponse: Decodable { let status: Int; let product: RawProduct? }
    private struct RawProduct: Decodable {
        let code: String?
        let product_name: String?
        let product_name_es: String?
        let brands: String?
        let serving_quantity: StringOrDouble?
        let nutriments: [String: StringOrDouble]?
    }
    /// OFF devuelve números a veces como string.
    enum StringOrDouble: Decodable {
        case d(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let v = try? c.decode(Double.self) { self = .d(v) }
            else if let s = try? c.decode(String.self), let v = Double(s.replacingOccurrences(of: ",", with: ".")) { self = .d(v) }
            else { self = .d(0) }
        }
        var value: Double { switch self { case .d(let v): return v } }
    }

    private func request(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "OFF", code: 2, userInfo: [NSLocalizedDescriptionKey: "Open Food Facts no responde"])
        }
        return data
    }

    func search(_ text: String) async throws -> [Product] {
        var comps = URLComponents(string: "https://es.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            .init(name: "search_terms", value: text), .init(name: "search_simple", value: "1"), .init(name: "action", value: "process"),
            .init(name: "json", value: "1"), .init(name: "page_size", value: "25"),
            .init(name: "fields", value: "code,product_name,product_name_es,brands,serving_quantity,nutriments"),
        ]
        let data = try await request(comps.url!)
        return try JSONDecoder().decode(SearchResponse.self, from: data).products.compactMap(Self.map)
    }

    func product(barcode: String) async throws -> Product? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=code,product_name,product_name_es,brands,serving_quantity,nutriments")!
        let data = try await request(url)
        let r = try JSONDecoder().decode(BarcodeResponse.self, from: data)
        guard r.status == 1, let p = r.product else { return nil }
        return Self.map(p)
    }

    private static func map(_ p: RawProduct) -> Product? {
        let name = (p.product_name_es?.isEmpty == false ? p.product_name_es : p.product_name) ?? ""
        guard !name.isEmpty, let code = p.code, let n = p.nutriments else { return nil }
        func v(_ k: String) -> Double { n[k]?.value ?? 0 }
        var kcal = v("energy-kcal_100g")
        if kcal == 0 { kcal = v("energy_100g") / 4.184 }
        guard kcal > 0 || v("proteins_100g") > 0 else { return nil }
        return Product(id: code, name: name, brand: p.brands?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces),
                       kcal: kcal, protein: v("proteins_100g"), carbs: v("carbohydrates_100g"), fat: v("fat_100g"), fiber: v("fiber_100g"),
                       servingGrams: p.serving_quantity.map { $0.value > 0 ? $0.value : 100 })
    }
}
