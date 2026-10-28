import Foundation

/// A search or barcode result, not yet saved.
struct FoodResult: Identifiable, Hashable {
    var id: String { "\(source):\(sourceID)" }
    var name: String
    var brand: String?
    var source: String
    var sourceID: String
    var barcode: String?
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double
    var sugarPer100g: Double
    var servings: [ServingOption]

    var sourceLabel: String {
        switch source {
        case "fatsecret": "FatSecret"
        case "usda": "USDA"
        default: "Open Food Facts"
        }
    }

    func makeFood() -> Food {
        Food(name: name, brand: brand, source: source, sourceID: sourceID, barcode: barcode,
             caloriesPer100g: caloriesPer100g, proteinPer100g: proteinPer100g, carbsPer100g: carbsPer100g,
             fatPer100g: fatPer100g, fiberPer100g: fiberPer100g, sugarPer100g: sugarPer100g, servings: servings)
    }
}

/// The Carbs Cloudflare Worker that holds the FatSecret secret (see server/fatsecret-proxy).
struct FatSecretProxy {
    var baseURL: URL
    var token: String

    /// From Info.plist, filled in from Config/Secrets.xcconfig at build time.
    static var configured: FatSecretProxy? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let raw = info["FatSecretProxyURL"] as? String, !raw.isEmpty, !raw.contains("$("),
              let url = URL(string: raw), url.host != nil,
              let token = info["CarbsProxyToken"] as? String, !token.isEmpty, !token.contains("$(") else { return nil }
        return FatSecretProxy(baseURL: url, token: token)
    }
}

/// Food databases: FatSecret (through the Carbs Worker), USDA FoodData Central and Open Food Facts (barcodes).
struct FoodSearchService {
    var usdaKey: String
    var fatSecret: FatSecretProxy? = .configured
    var session: URLSession = .shared

    private let userAgent = "Carbs/0.1 (personal iOS app)"

    func search(_ query: String) async -> [FoodResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        async let fs = (try? searchFatSecret(trimmed)) ?? []
        async let usda = (try? searchUSDA(trimmed)) ?? []
        async let off = (try? searchOpenFoodFacts(trimmed)) ?? []
        let (f, a, b) = await (fs, usda, off)
        // FatSecret first, then the free databases interleaved.
        var merged = f
        for i in 0..<max(a.count, b.count) {
            if i < a.count { merged.append(a[i]) }
            if i < b.count { merged.append(b[i]) }
        }
        return merged
    }

    // MARK: FatSecret

    func searchFatSecret(_ query: String) async throws -> [FoodResult] {
        guard let proxy = fatSecret else { return [] }
        var components = URLComponents(url: proxy.baseURL.appending(path: "search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue(proxy.token, forHTTPHeaderField: "X-Carbs-Token")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return (json["foods"] as? [[String: Any]] ?? []).compactMap(parseFatSecret)
    }

    func parseFatSecret(_ f: [String: Any]) -> FoodResult? {
        guard let id = f["id"] as? String, let name = f["name"] as? String,
              let per = f["per100g"] as? [String: Any] else { return nil }
        func value(_ key: String) -> Double { number(per[key]) ?? 0 }
        let servings = (f["servings"] as? [[String: Any]] ?? []).compactMap { s -> ServingOption? in
            guard let name = s["name"] as? String, let grams = number(s["grams"]), grams > 0 else { return nil }
            return ServingOption(name: name, grams: grams)
        }
        return FoodResult(name: name, brand: f["brand"] as? String, source: "fatsecret", sourceID: id, barcode: nil,
                          caloriesPer100g: value("calories"), proteinPer100g: value("protein"),
                          carbsPer100g: value("carbs"), fatPer100g: value("fat"),
                          fiberPer100g: value("fiber"), sugarPer100g: value("sugar"), servings: servings)
    }

    func lookup(barcode: String) async -> FoodResult? {
        if let found = try? await openFoodFactsProduct(barcode) { return found }
        return try? await searchUSDA(barcode, branded: true).first { $0.barcode?.hasSuffix(barcode.trimmingLeadingZeros) == true }
    }

    // MARK: USDA

    func searchUSDA(_ query: String, branded: Bool = false) async throws -> [FoodResult] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: usdaKey.isEmpty ? "DEMO_KEY" : usdaKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "20"),
            URLQueryItem(name: "dataType", value: branded ? "Branded" : "Foundation,SR Legacy,Branded"),
        ]
        let json = try await fetch(components.url!)
        let foods = json["foods"] as? [[String: Any]] ?? []
        return foods.compactMap(parseUSDA)
    }

    func parseUSDA(_ f: [String: Any]) -> FoodResult? {
        guard let name = f["description"] as? String, let fdcId = f["fdcId"] else { return nil }
        var values: [Int: Double] = [:]
        for n in f["foodNutrients"] as? [[String: Any]] ?? [] {
            guard let id = n["nutrientId"] as? Int, let value = n["value"] as? Double else { continue }
            // Energy can be reported in kJ (1062); only keep kcal.
            if id == 1008 || id == 2047 || id == 2048, (n["unitName"] as? String)?.uppercased() != "KCAL" { continue }
            values[id] = values[id] ?? value
        }
        let protein = values[1003] ?? 0, fat = values[1004] ?? 0, carbs = values[1005] ?? 0
        let calories = values[1008] ?? values[2047] ?? values[2048] ?? (protein * 4 + carbs * 4 + fat * 9)

        var servings: [ServingOption] = []
        if let size = f["servingSize"] as? Double, let unit = (f["servingSizeUnit"] as? String)?.lowercased(),
           unit == "g" || unit == "grm" || unit == "ml" || unit == "mlt" {
            // "1 CONTAINER" → "container", so the diary reads "1 container (150g)" not "1 1 CONTAINER".
            var label = (f["householdServingFullText"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "serving"
            if label.hasPrefix("1 ") { label = String(label.dropFirst(2)) }
            if label == label.uppercased() { label = label.lowercased() }
            servings.append(ServingOption(name: "\(label) (\(size.clean)\(unit.hasPrefix("m") ? "ml" : "g"))", grams: size))
        }
        for m in (f["foodMeasures"] as? [[String: Any]] ?? []).prefix(6) {
            if let text = m["disseminationText"] as? String, let grams = m["gramWeight"] as? Double, grams > 0,
               text.lowercased() != "quantity not specified", !servings.contains(where: { $0.name == text }) {
                servings.append(ServingOption(name: text, grams: grams))
            }
        }
        let brand = (f["brandName"] as? String) ?? (f["brandOwner"] as? String)
        return FoodResult(name: name.capitalizedFoodName, brand: brand?.capitalized, source: "usda", sourceID: "\(fdcId)",
                          barcode: f["gtinUpc"] as? String, caloriesPer100g: calories, proteinPer100g: protein,
                          carbsPer100g: carbs, fatPer100g: fat, fiberPer100g: values[1079] ?? 0,
                          sugarPer100g: values[2000] ?? 0, servings: servings)
    }

    // MARK: Open Food Facts

    func searchOpenFoodFacts(_ query: String) async throws -> [FoodResult] {
        var components = URLComponents(string: "https://search.openfoodfacts.org/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments,serving_size,serving_quantity"),
        ]
        let json = try await fetch(components.url!)
        let products = json["hits"] as? [[String: Any]] ?? []
        return products.compactMap(parseOpenFoodFacts)
    }

    func openFoodFactsProduct(_ barcode: String) async throws -> FoodResult? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=code,product_name,brands,nutriments,serving_size,serving_quantity")!
        let json = try await fetch(url)
        guard let product = json["product"] as? [String: Any] else { return nil }
        return parseOpenFoodFacts(product)
    }

    func parseOpenFoodFacts(_ p: [String: Any]) -> FoodResult? {
        guard let name = (p["product_name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              let code = p["code"] as? String,
              let n = p["nutriments"] as? [String: Any] else { return nil }
        func value(_ key: String) -> Double? { number(n[key]) }
        let protein = value("proteins_100g") ?? 0, carbs = value("carbohydrates_100g") ?? 0, fat = value("fat_100g") ?? 0
        guard let calories = value("energy-kcal_100g") ?? value("energy_100g").map({ $0 / 4.184 }) else { return nil }
        var servings: [ServingOption] = []
        if let grams = number(p["serving_quantity"]), grams > 0 {
            let label = (p["serving_size"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(grams.clean) g"
            servings.append(ServingOption(name: "serving (\(label))", grams: grams))
        }
        // The product API gives brands as "A, B"; the search service gives ["A", "B"].
        let brand = (p["brands"] as? [String])?.first
            ?? (p["brands"] as? String)?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        return FoodResult(name: name, brand: brand, source: "openfoodfacts", sourceID: code, barcode: code,
                          caloriesPer100g: calories, proteinPer100g: protein, carbsPer100g: carbs, fatPer100g: fat,
                          fiberPer100g: value("fiber_100g") ?? 0, sugarPer100g: value("sugars_100g") ?? 0, servings: servings)
    }

    // MARK: Helpers

    private func fetch(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
}

extension String {
    var trimmingLeadingZeros: String {
        let trimmed = drop { $0 == "0" }
        return trimmed.isEmpty ? self : String(trimmed)
    }

    /// USDA names come in ALL CAPS or "Chicken, breast, raw"; tidy the all-caps ones.
    var capitalizedFoodName: String {
        self == uppercased() ? capitalized : self
    }
}
