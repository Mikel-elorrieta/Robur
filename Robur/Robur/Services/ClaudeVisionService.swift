import Foundation
import UIKit

/// Envía una foto de comida a la API de Claude y devuelve alimentos estimados con macros.
struct ClaudeVisionService {

    struct FoodEstimate: Identifiable, Decodable {
        var id = UUID()
        var name: String
        var grams: Double
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var confidence: String?
        enum CodingKeys: String, CodingKey { case name, grams, kcal, protein, carbs, fat, confidence }
    }
    struct Analysis: Decodable {
        var dishName: String
        var items: [FoodEstimate]
        var notes: String?
        var totalKcal: Double { items.reduce(0) { $0 + $1.kcal } }
    }

    enum VisionError: LocalizedError {
        case noKey, badResponse(String), badJSON
        var errorDescription: String? {
            switch self {
            case .noKey: "Falta la API key de Anthropic. Ponla en Ajustes."
            case .badResponse(let s): "La API ha respondido con error: \(s)"
            case .badJSON: "No he podido interpretar la respuesta de la IA."
            }
        }
    }

    static let prompt = """
    Eres un nutricionista. Analiza la foto y estima qué alimentos hay y en qué cantidad (gramos) para UNA ración tal y como se ve en la imagen.
    Devuelve SOLO un JSON válido, sin markdown ni texto alrededor, con este formato exacto:
    {"dishName":"nombre corto del plato","items":[{"name":"alimento","grams":0,"kcal":0,"protein":0,"carbs":0,"fat":0,"confidence":"alta|media|baja"}],"notes":"aviso breve si algo es dudoso"}
    Los valores kcal/protein/carbs/fat son TOTALES para los gramos indicados (no por 100 g). Usa nombres en español. Si hay varios alimentos, sepáralos.
    """

    func analyze(image: UIImage, apiKey: String, model: String) async throws -> Analysis {
        guard !apiKey.isEmpty else { throw VisionError.noKey }
        let resized = image.resized(maxSide: 1024)
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { throw VisionError.badJSON }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                    ["type": "text", "text": Self.prompt],
                ],
            ]],
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
            throw VisionError.badResponse(msg)
        }
        // Extraer el texto de la respuesta
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else { throw VisionError.badJSON }
        let json = Self.extractJSON(from: text)
        guard let jd = json.data(using: .utf8) else { throw VisionError.badJSON }
        do { return try JSONDecoder().decode(Analysis.self, from: jd) } catch { throw VisionError.badJSON }
    }

    /// Por si el modelo envuelve el JSON en ```json ... ```
    private static func extractJSON(from text: String) -> String {
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
