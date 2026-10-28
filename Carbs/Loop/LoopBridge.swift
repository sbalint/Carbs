import Foundation
import SwiftData
import UIKit

/// Hands meals to Loop through Loop's App Group. Carbs only writes suggestions; Loop decides
/// nothing on its own and every carb entry is confirmed by the user in Loop.
enum LoopBridge {
    /// Meals older than this aren't offered (Loop also refuses stale suggestions).
    static let offerWindow: TimeInterval = 6 * 3600
    /// Handled suggestions are kept this long so Carbs can show their status.
    static let keepHandled: TimeInterval = 2 * 86400

    static var appGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LoopAppGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    static var urlScheme: String {
        (Bundle.main.object(forInfoDictionaryKey: "LoopURLScheme") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "loop"
    }

    static var fileURL: URL? {
        guard let appGroup,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        return container.appending(path: "Carbs/meal-suggestions.json")
    }

    static var isAvailable: Bool { fileURL != nil }

    /// Local calendar day plus meal, so a late dinner stays on its own day.
    static func groupKey(for entry: FoodEntry) -> String {
        let d = Calendar.current.dateComponents([.year, .month, .day], from: entry.timestamp)
        return String(format: "%04d-%02d-%02d|%d", d.year ?? 0, d.month ?? 0, d.day ?? 0, entry.meal)
    }

    /// Carb-weighted absorption so a manual change on one food still counts.
    static func absorption(for entries: [FoodEntry]) -> Int {
        let carbs = entries.map(\.carbs).reduce(0, +)
        guard carbs > 0 else { return 180 }
        let weighted = entries.map { Double($0.absorptionMinutes) * $0.carbs }.reduce(0, +) / carbs
        return Int((weighted / 5).rounded() * 5)
    }

    // MARK: Sync

    /// Brings the shared file and the diary in line:
    /// 1. entries Loop has handled get that status in Carbs;
    /// 2. pending entries from the last few hours become one suggestion per meal;
    /// 3. old handled suggestions are pruned.
    /// Returns the current suggestions keyed by group.
    @MainActor
    @discardableResult
    static func sync(context: ModelContext, mealNames: [String], now: Date = .now) -> [String: LoopMealSuggestion] {
        guard let url = fileURL else { return [:] }
        var result: [String: LoopMealSuggestion] = [:]
        coordinate(url) { file in
            let handled = file.suggestions.filter { $0.status != .pending && ($0.handledAt ?? $0.updatedAt) > now - keepHandled }
            let since = now - offerWindow
            let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.timestamp >= since })
            let recent = (try? context.fetch(descriptor)) ?? []
            let byID = Dictionary(uniqueKeysWithValues: recent.map { ($0.id.uuidString, $0) })

            for suggestion in handled {
                for id in suggestion.entryIDs {
                    guard let entry = byID[id], entry.loopStatus == .pending else { continue }
                    entry.loopStatus = suggestion.status == .dismissed ? .dismissed : .accepted
                }
            }

            let pending = recent.filter { $0.loopStatus == .pending && $0.carbs >= 1 }
            var suggestions = handled
            for (key, entries) in Dictionary(grouping: pending, by: groupKey(for:)) {
                let sorted = entries.sorted { $0.timestamp < $1.timestamp }
                let existing = file.suggestions.first { $0.groupKey == key && $0.status == .pending }
                var s = LoopMealSuggestion(
                    id: existing?.id ?? UUID().uuidString,
                    groupKey: key,
                    mealName: mealNames[safe: sorted[0].meal] ?? "Meal",
                    startDate: sorted[0].timestamp,
                    carbs: (sorted.map(\.carbs).reduce(0, +) * 10).rounded() / 10,
                    absorptionMinutes: absorption(for: sorted),
                    foods: sorted.map(\.name),
                    entryIDs: sorted.map(\.id.uuidString),
                    status: .pending,
                    updatedAt: now,
                    handledAt: nil)
                if let existing, existing.carbs == s.carbs, existing.startDate == s.startDate,
                   existing.absorptionMinutes == s.absorptionMinutes, existing.entryIDs == s.entryIDs {
                    s.updatedAt = existing.updatedAt
                }
                suggestions.append(s)
            }
            file.suggestions = suggestions.sorted { $0.startDate < $1.startDate }
            for s in file.suggestions where s.status == .pending { result[s.groupKey] = s }
        }
        try? context.save()
        return result
    }

    /// Offers already-handled entries to Loop again.
    @MainActor
    static func resend(_ entries: [FoodEntry], context: ModelContext, mealNames: [String]) {
        guard let url = fileURL else { return }
        let ids = Set(entries.map(\.id.uuidString))
        coordinate(url) { file in
            for i in file.suggestions.indices {
                file.suggestions[i].entryIDs.removeAll { ids.contains($0) }
            }
            file.suggestions.removeAll { $0.entryIDs.isEmpty }
        }
        for entry in entries where entry.carbs >= 1 { entry.loopStatus = .pending }
        sync(context: context, mealNames: mealNames)
    }

    /// Opens Loop's carb entry screen filled in with this suggestion.
    @MainActor
    static func open(_ suggestion: LoopMealSuggestion) async -> Bool {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "carb-entry"
        components.queryItems = [URLQueryItem(name: "carbs-suggestion", value: suggestion.id)]
        guard let url = components.url else { return false }
        return await UIApplication.shared.open(url)
    }

    // MARK: File access

    /// Read-modify-write under a file coordinator, since Loop writes the same file.
    private static func coordinate(_ url: URL, _ change: (inout LoopSuggestionFile) -> Void) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { url in
            var file = (try? Data(contentsOf: url)).flatMap { try? LoopSuggestionFile.decoder.decode(LoopSuggestionFile.self, from: $0) }
                ?? LoopSuggestionFile()
            change(&file)
            if let data = try? LoopSuggestionFile.encoder.encode(file) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
