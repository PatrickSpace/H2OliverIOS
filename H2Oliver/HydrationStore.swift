//
//  HydrationStore.swift
//  H2Oliver
//
//  Created by Codex on 21/06/26.
//

import Combine
import Foundation

@MainActor
final class HydrationStore: ObservableObject {
    @Published var selectedDate: Date = Date()
    @Published var goal = HydrationGoal()
    @Published var bottles: [Bottle] = Bottle.presets
    @Published var notificationSettings = HydrationNotificationSettings()
    @Published private(set) var records: [String: DayIntake] = [:]
    @Published var syncErrorMessage: String?
    @Published private(set) var isSyncing = false

    private let cloudService: HydrationCloudServicing
    private let storage: UserDefaults
    private var cloudUserID: String?
    private var isApplyingCloudSnapshot = false
    private var deletedEntryIDs: Set<UUID> = []

    init(
        storage: UserDefaults = .standard,
        cloudService: HydrationCloudServicing? = nil,
        userID: String? = nil
    ) {
        self.storage = storage
        self.cloudService = cloudService ?? HydrationFirestoreService()

        if let userID {
            cloudUserID = userID
            loadLocalData(for: userID)
        }
    }

    var selectedDayKey: String {
        selectedDate.hydrationDayKey
    }

    var selectedDayIntake: DayIntake {
        records[selectedDayKey] ?? DayIntake(dayKey: selectedDayKey)
    }

    var selectedTotalMl: Int {
        selectedDayIntake.totalMl
    }

    var selectedProgress: Double {
        guard goal.targetMl > 0 else { return 0 }
        return min(Double(selectedTotalMl) / Double(goal.targetMl), 1)
    }

    var hasCompletedSelectedGoal: Bool {
        selectedTotalMl >= goal.targetMl
    }

    var allEntries: [IntakeEntry] {
        records.values.flatMap(\.entries).filter { !deletedEntryIDs.contains($0.id) }
    }

    func intake(for date: Date) -> DayIntake {
        records[date.hydrationDayKey] ?? DayIntake(dayKey: date.hydrationDayKey)
    }

    func progress(for date: Date) -> Double {
        guard goal.targetMl > 0 else { return 0 }
        return min(Double(intake(for: date).totalMl) / Double(goal.targetMl), 1)
    }

    func addGlass() {
        addIntake(amountMl: HydrationConstants.standardGlassMl, sourceName: "Vaso")
    }

    func addBottle(_ bottle: Bottle) {
        addIntake(amountMl: bottle.capacityMl, sourceName: bottle.name)
    }

    func addBottle(name: String, capacityMl: Int, iconName: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let bottle = Bottle(
            name: trimmedName.isEmpty ? "Tomatodo" : trimmedName,
            iconName: iconName,
            capacityMl: max(100, capacityMl)
        )
        bottles.append(bottle)
        saveBottles()
    }

    func deleteBottle(at offsets: IndexSet) {
        let idsToDelete = Set(offsets.map { bottles[$0].id })
        bottles.removeAll { idsToDelete.contains($0.id) }
        if bottles.isEmpty {
            bottles = Bottle.presets
        }
        saveBottles()
    }

    func removeEntry(_ entry: IntakeEntry) {
        deletedEntryIDs.insert(entry.id)
        var day = records[entry.dayKey] ?? DayIntake(dayKey: entry.dayKey)
        day.entries.removeAll { $0.id == entry.id }
        records[entry.dayKey] = day
        saveRecords()
        saveDeletedEntryIDs()
        deleteEntryFromCloud(entryID: entry.id)
    }

    func weekDays(around date: Date) -> [WeekDay] {
        let calendar = Calendar.app
        let startOfSelectedWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return (-14..<21).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfSelectedWeek) else {
                return nil
            }
            return WeekDay(
                date: day,
                weekdayText: Self.weekdayFormatter.string(from: day).uppercased(),
                dayText: Self.dayFormatter.string(from: day)
            )
        }
    }

    func saveAll() {
        saveRecords()
        saveGoal()
        saveBottles()
        saveNotifications()
    }

    func saveGoal() {
        encode(goal, forKey: storageKey("goal"))
        saveProfileToCloud()
    }

    func saveNotifications() {
        encode(notificationSettings, forKey: storageKey("notifications"))
        saveProfileToCloud()
    }

    func clearSyncError() {
        syncErrorMessage = nil
    }

    func configureCloudSync(userID: String?) {
        guard cloudUserID != userID else { return }
        cloudUserID = userID
        syncErrorMessage = nil

        guard let userID else {
            resetLocalState()
            return
        }

        loadLocalData(for: userID)
        fetchCloudData(for: userID)
    }

    private func addIntake(amountMl: Int, sourceName: String) {
        let entry = IntakeEntry(amountMl: amountMl, sourceName: sourceName, dayKey: selectedDayKey)
        var day = selectedDayIntake
        day.entries.insert(entry, at: 0)
        records[selectedDayKey] = day
        saveRecords()
        saveEntryToCloud(entry)
    }

    private func fetchCloudData(for userID: String) {
        runCloudOperation(failureMessage: "No se pudo sincronizar con Firestore.") { store in
            if let snapshot = try await store.cloudService.fetchSnapshot(userID: userID) {
                store.applyCloudSnapshot(snapshot)
            } else {
                store.saveProfileToCloud()
                store.uploadLocalEntriesToCloud()
                store.syncDeletedEntryIDsToCloud()
            }
        }
    }

    private func applyCloudSnapshot(_ snapshot: HydrationCloudSnapshot) {
        isApplyingCloudSnapshot = true

        let localEntries = allEntries
        deletedEntryIDs.formUnion(snapshot.deletedEntryIDs)
        let mergedEntries = mergeEntries(localEntries + snapshot.entries)
            .filter { !deletedEntryIDs.contains($0.id) }
        goal = snapshot.goal
        bottles = snapshot.bottles.isEmpty ? Bottle.presets : snapshot.bottles
        notificationSettings = snapshot.notificationSettings
        records = mergedEntries.groupedByDayKey()
        saveDeletedEntryIDs()
        saveAll()

        isApplyingCloudSnapshot = false
        uploadLocalEntriesToCloud()
        syncDeletedEntryIDsToCloud()
    }

    private func saveRecords() {
        encode(records, forKey: storageKey("records"))
    }

    private func saveBottles() {
        encode(bottles, forKey: storageKey("bottles"))
        saveProfileToCloud()
    }

    private func saveProfileToCloud() {
        guard !isApplyingCloudSnapshot, let cloudUserID else { return }

        let goal = goal
        let bottles = bottles
        let notificationSettings = notificationSettings

        runCloudOperation(failureMessage: "No se pudo guardar tu perfil en Firestore.") { store in
            try await store.cloudService.saveProfile(
                userID: cloudUserID,
                goal: goal,
                bottles: bottles,
                notificationSettings: notificationSettings
            )
        }
    }

    private func saveEntryToCloud(_ entry: IntakeEntry) {
        guard !isApplyingCloudSnapshot, let cloudUserID else { return }

        runCloudOperation(failureMessage: "No se pudo guardar el registro en Firestore.") { store in
            try await store.cloudService.saveEntry(userID: cloudUserID, entry: entry)
        }
    }

    private func deleteEntryFromCloud(entryID: UUID) {
        guard let cloudUserID else { return }

        runCloudOperation(failureMessage: "No se pudo eliminar el registro en Firestore.") { store in
            try await store.cloudService.deleteEntry(userID: cloudUserID, entryID: entryID)
        }
    }

    private func uploadLocalEntriesToCloud() {
        guard !isApplyingCloudSnapshot, let cloudUserID else { return }
        let entries = allEntries

        runCloudOperation(failureMessage: "No se pudieron subir todos los registros locales.") { store in
            for entry in entries {
                try await store.cloudService.saveEntry(userID: cloudUserID, entry: entry)
            }
        }
    }

    private func syncDeletedEntryIDsToCloud() {
        guard let cloudUserID, !deletedEntryIDs.isEmpty else { return }
        let entryIDs = deletedEntryIDs

        runCloudOperation(failureMessage: "No se pudieron sincronizar algunos borrados.") { store in
            for entryID in entryIDs {
                try await store.cloudService.deleteEntry(userID: cloudUserID, entryID: entryID)
            }
        }
    }

    private func runCloudOperation(
        failureMessage: String,
        operation: @escaping @MainActor (HydrationStore) async throws -> Void
    ) {
        Task {
            self.isSyncing = true
            do {
                try await operation(self)
                self.syncErrorMessage = nil
            } catch {
                self.syncErrorMessage = "\(failureMessage) \(error.localizedDescription)"
            }
            self.isSyncing = false
        }
    }

    private func mergeEntries(_ entries: [IntakeEntry]) -> [IntakeEntry] {
        Dictionary(grouping: entries, by: \.id)
            .compactMap { _, duplicates in
                duplicates.max { $0.createdAt < $1.createdAt }
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func loadLocalData(for userID: String) {
        records = decode([String: DayIntake].self, forKey: storageKey("records", userID: userID)) ?? [:]
        goal = decode(HydrationGoal.self, forKey: storageKey("goal", userID: userID)) ?? HydrationGoal()
        bottles = decode([Bottle].self, forKey: storageKey("bottles", userID: userID)) ?? Bottle.presets
        notificationSettings = decode(HydrationNotificationSettings.self, forKey: storageKey("notifications", userID: userID)) ?? HydrationNotificationSettings()
        deletedEntryIDs = decode(Set<UUID>.self, forKey: storageKey("deletedEntries", userID: userID)) ?? []
    }

    private func resetLocalState() {
        records = [:]
        goal = HydrationGoal()
        bottles = Bottle.presets
        notificationSettings = HydrationNotificationSettings()
        deletedEntryIDs = []
    }

    private func storageKey(_ key: String, userID: String? = nil) -> String {
        let namespace = userID ?? cloudUserID ?? "signed-out"
        return "hydration.\(key).\(namespace)"
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        storage.set(data, forKey: key)
    }

    private func saveDeletedEntryIDs() {
        encode(deletedEntryIDs, forKey: storageKey("deletedEntries"))
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = storage.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .app
        formatter.locale = Locale(identifier: "es_PE")
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .app
        formatter.locale = Locale(identifier: "es_PE")
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()
}
