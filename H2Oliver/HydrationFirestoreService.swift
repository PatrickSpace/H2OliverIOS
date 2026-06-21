//
//  HydrationFirestoreService.swift
//  H2Oliver
//
//  Created by Codex on 21/06/26.
//

import FirebaseFirestore
import Foundation

struct HydrationCloudSnapshot {
    var goal: HydrationGoal
    var bottles: [Bottle]
    var notificationSettings: HydrationNotificationSettings
    var entries: [IntakeEntry]
    var deletedEntryIDs: Set<UUID>
}

protocol HydrationCloudServicing {
    func fetchSnapshot(userID: String) async throws -> HydrationCloudSnapshot?
    func saveProfile(
        userID: String,
        goal: HydrationGoal,
        bottles: [Bottle],
        notificationSettings: HydrationNotificationSettings
    ) async throws
    func saveEntry(userID: String, entry: IntakeEntry) async throws
    func deleteEntry(userID: String, entryID: UUID) async throws
}

struct NoopHydrationCloudService: HydrationCloudServicing {
    func fetchSnapshot(userID: String) async throws -> HydrationCloudSnapshot? {
        nil
    }

    func saveProfile(
        userID: String,
        goal: HydrationGoal,
        bottles: [Bottle],
        notificationSettings: HydrationNotificationSettings
    ) async throws {}

    func saveEntry(userID: String, entry: IntakeEntry) async throws {}

    func deleteEntry(userID: String, entryID: UUID) async throws {}
}

final class HydrationFirestoreService: HydrationCloudServicing {
    private let database = Firestore.firestore()

    func fetchSnapshot(userID: String) async throws -> HydrationCloudSnapshot? {
        let userReference = userDocument(userID)
        async let profileDocument = userReference.getDocument()
        async let entriesSnapshot = userReference.collection("entries").getDocuments()
        async let deletedEntriesSnapshot = userReference.collection("deletedEntries").getDocuments()

        let profile = try await profileDocument
        let entries = try await entriesSnapshot
        let deletedEntries = try await deletedEntriesSnapshot

        guard profile.exists else {
            return nil
        }

        let data = profile.data() ?? [:]
        return HydrationCloudSnapshot(
            goal: decodeGoal(data["goal"] as? [String: Any]) ?? HydrationGoal(),
            bottles: decodeBottles(data["bottles"] as? [[String: Any]]) ?? Bottle.presets,
            notificationSettings: decodeNotificationSettings(data["notificationSettings"] as? [String: Any]) ?? HydrationNotificationSettings(),
            entries: entries.documents.compactMap { decodeEntry($0.data()) },
            deletedEntryIDs: Set(deletedEntries.documents.compactMap { UUID(uuidString: $0.documentID) })
        )
    }

    func saveProfile(
        userID: String,
        goal: HydrationGoal,
        bottles: [Bottle],
        notificationSettings: HydrationNotificationSettings
    ) async throws {
        try await userDocument(userID).setData([
            "goal": encodeGoal(goal),
            "bottles": bottles.map(encodeBottle),
            "notificationSettings": encodeNotificationSettings(notificationSettings),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func saveEntry(userID: String, entry: IntakeEntry) async throws {
        try await userDocument(userID)
            .collection("entries")
            .document(entry.id.uuidString)
            .setData(encodeEntry(entry), merge: true)
    }

    func deleteEntry(userID: String, entryID: UUID) async throws {
        let userReference = userDocument(userID)
        let batch = database.batch()
        batch.setData([
            "id": entryID.uuidString,
            "deletedAt": FieldValue.serverTimestamp()
        ], forDocument: userReference.collection("deletedEntries").document(entryID.uuidString), merge: true)
        batch.deleteDocument(userReference.collection("entries").document(entryID.uuidString))
        try await batch.commit()
    }

    private func userDocument(_ userID: String) -> DocumentReference {
        database.collection("users").document(userID)
    }

    private func encodeGoal(_ goal: HydrationGoal) -> [String: Any] {
        [
            "unit": goal.unit.rawValue,
            "glasses": goal.glasses,
            "liters": goal.liters,
            "targetMl": goal.targetMl
        ]
    }

    private func decodeGoal(_ data: [String: Any]?) -> HydrationGoal? {
        guard let data else { return nil }
        return HydrationGoal(
            unit: GoalUnit(rawValue: data["unit"] as? String ?? "") ?? .glasses,
            glasses: intValue(data["glasses"]) ?? 8,
            liters: doubleValue(data["liters"]) ?? 2
        )
    }

    private func encodeBottle(_ bottle: Bottle) -> [String: Any] {
        [
            "id": bottle.id.uuidString,
            "name": bottle.name,
            "iconName": bottle.iconName,
            "capacityMl": bottle.capacityMl
        ]
    }

    private func decodeBottles(_ data: [[String: Any]]?) -> [Bottle]? {
        guard let data else { return nil }
        return data.compactMap { item in
            guard
                let idString = item["id"] as? String,
                let id = UUID(uuidString: idString),
                let name = item["name"] as? String,
                let iconName = item["iconName"] as? String,
                let capacityMl = intValue(item["capacityMl"])
            else {
                return nil
            }

            return Bottle(id: id, name: name, iconName: iconName, capacityMl: capacityMl)
        }
    }

    private func encodeNotificationSettings(_ settings: HydrationNotificationSettings) -> [String: Any] {
        [
            "isEnabled": settings.isEnabled,
            "startHour": settings.startHour,
            "endHour": settings.endHour,
            "intervalHours": settings.intervalHours
        ]
    }

    private func decodeNotificationSettings(_ data: [String: Any]?) -> HydrationNotificationSettings? {
        guard let data else { return nil }
        return HydrationNotificationSettings(
            isEnabled: data["isEnabled"] as? Bool ?? false,
            startHour: intValue(data["startHour"]) ?? 9,
            endHour: intValue(data["endHour"]) ?? 21,
            intervalHours: intValue(data["intervalHours"]) ?? 1
        )
    }

    private func encodeEntry(_ entry: IntakeEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "amountMl": entry.amountMl,
            "sourceName": entry.sourceName,
            "createdAt": Timestamp(date: entry.createdAt),
            "dayKey": entry.dayKey
        ]
    }

    private func decodeEntry(_ data: [String: Any]) -> IntakeEntry? {
        guard
            let idString = data["id"] as? String,
            let id = UUID(uuidString: idString),
            let amountMl = intValue(data["amountMl"]),
            let sourceName = data["sourceName"] as? String
        else {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        return IntakeEntry(
            id: id,
            amountMl: amountMl,
            sourceName: sourceName,
            createdAt: createdAt,
            dayKey: data["dayKey"] as? String
        )
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        return (value as? NSNumber)?.intValue
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        return (value as? NSNumber)?.doubleValue
    }
}
