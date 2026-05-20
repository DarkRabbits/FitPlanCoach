import Foundation

@MainActor
final class LocalStore: ObservableObject {
    @Published private(set) var currentMetrics: BodyMetrics?
    @Published private(set) var previousMetrics: BodyMetrics?
    @Published private(set) var dietEntries: [DietEntry] = []
    @Published private(set) var latestEnergySummary: DailyEnergySummary?
    @Published private(set) var bodyGoal: BodyGoal?

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key {
        static let currentMetrics = "currentMetrics"
        static let previousMetrics = "previousMetrics"
        static let dietEntries = "dietEntries"
        static let latestEnergySummary = "latestEnergySummary"
        static let bodyGoal = "bodyGoal"
    }

    init() {
        currentMetrics = load(BodyMetrics.self, key: Key.currentMetrics)
        previousMetrics = load(BodyMetrics.self, key: Key.previousMetrics)
        dietEntries = load([DietEntry].self, key: Key.dietEntries) ?? []
        latestEnergySummary = load(DailyEnergySummary.self, key: Key.latestEnergySummary)
        bodyGoal = load(BodyGoal.self, key: Key.bodyGoal)
    }

    var todayDietEntries: [DietEntry] {
        dietEntries
            .filter { Calendar.current.isDateInToday($0.date) }
            .sorted { $0.date < $1.date }
    }

    var todayIntakeCalories: Double {
        todayDietEntries.reduce(0) { $0 + $1.calories }
    }

    func ingest(metrics: BodyMetrics) {
        if let currentMetrics {
            if currentMetrics.fingerprint != metrics.fingerprint {
                previousMetrics = currentMetrics
                self.currentMetrics = metrics
            } else {
                self.currentMetrics = metrics
            }
        } else {
            currentMetrics = metrics
        }

        save(currentMetrics, key: Key.currentMetrics)
        save(previousMetrics, key: Key.previousMetrics)
    }

    func addDietEntry(_ entry: DietEntry) {
        dietEntries.append(entry)
        save(dietEntries, key: Key.dietEntries)
    }

    func deleteDietEntries(at offsets: IndexSet) {
        let ids = offsets.map { todayDietEntries[$0].id }
        dietEntries.removeAll { ids.contains($0.id) }
        save(dietEntries, key: Key.dietEntries)
    }

    func deleteDietEntry(id: UUID) {
        dietEntries.removeAll { $0.id == id }
        save(dietEntries, key: Key.dietEntries)
    }

    func updateEnergySummary(_ summary: DailyEnergySummary) {
        latestEnergySummary = summary
        save(summary, key: Key.latestEnergySummary)
    }

    func updateBodyGoal(_ goal: BodyGoal) {
        bodyGoal = goal
        save(goal, key: Key.bodyGoal)
    }

    func clearBodyGoal() {
        bodyGoal = nil
        save(Optional<BodyGoal>.none, key: Key.bodyGoal)
    }

    private func save<T: Encodable>(_ value: T?, key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }

        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
