//
//  HydrationCoreTests.swift
//  H2OliverTests
//
//  Created by Codex on 21/06/26.
//

import XCTest
@testable import H2Oliver

@MainActor
final class HydrationCoreTests: XCTestCase {
    private var storage: UserDefaults!
    private var storageSuiteName: String!

    override func setUp() {
        super.setUp()
        storageSuiteName = "H2OliverTests.\(UUID().uuidString)"
        storage = UserDefaults(suiteName: storageSuiteName)!
        storage.removePersistentDomain(forName: storageSuiteName)
    }

    override func tearDown() {
        storage.removePersistentDomain(forName: storageSuiteName)
        storage = nil
        storageSuiteName = nil
        super.tearDown()
    }

    func testGoalTargetMlForGlassesAndLiters() {
        let glassesGoal = HydrationGoal(unit: .glasses, glasses: 8, liters: 1)
        XCTAssertEqual(glassesGoal.targetMl, 2_000)

        let litersGoal = HydrationGoal(unit: .liters, glasses: 1, liters: 2.25)
        XCTAssertEqual(litersGoal.targetMl, 2_250)
    }

    func testHydrationDayKeyUsesStableLocalFormat() {
        var components = DateComponents()
        components.calendar = .app
        components.timeZone = .current
        components.year = 2026
        components.month = 6
        components.day = 21
        components.hour = 10

        let date = components.date!
        XCTAssertEqual(date.hydrationDayKey, "2026-06-21")
    }

    func testAddGlassAndBottle() {
        let store = makeStore()
        let bottle = Bottle(name: "Tomatodo test", iconName: "waterbottle", capacityMl: 750)

        store.addGlass()
        store.addBottle(bottle)

        XCTAssertEqual(store.selectedDayIntake.entries.count, 2)
        XCTAssertEqual(store.selectedTotalMl, 1_000)
    }

    func testRemoveEntryLocally() {
        let store = makeStore()
        store.addGlass()

        let entry = store.selectedDayIntake.entries[0]
        store.removeEntry(entry)

        XCTAssertTrue(store.selectedDayIntake.entries.isEmpty)
        XCTAssertEqual(store.selectedTotalMl, 0)
    }

    func testBasicSerializationRoundTrip() throws {
        let entry = IntakeEntry(amountMl: 250, sourceName: "Vaso", dayKey: "2026-06-21")
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(IntakeEntry.self, from: encoded)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.amountMl, 250)
        XCTAssertEqual(decoded.dayKey, "2026-06-21")
    }

    func testEntriesGroupByDayKey() {
        let entries = [
            IntakeEntry(amountMl: 250, sourceName: "Vaso", dayKey: "2026-06-21"),
            IntakeEntry(amountMl: 500, sourceName: "Tomatodo", dayKey: "2026-06-21"),
            IntakeEntry(amountMl: 250, sourceName: "Vaso", dayKey: "2026-06-22")
        ]

        let grouped = entries.groupedByDayKey()

        XCTAssertEqual(grouped["2026-06-21"]?.entries.count, 2)
        XCTAssertEqual(grouped["2026-06-21"]?.totalMl, 750)
        XCTAssertEqual(grouped["2026-06-22"]?.totalMl, 250)
    }

    func testLocalCacheIsSeparatedByUserID() {
        let firstUserStore = makeStore(userID: "first-user")
        firstUserStore.addGlass()

        let secondUserStore = makeStore(userID: "second-user")
        XCTAssertEqual(secondUserStore.selectedTotalMl, 0)

        let firstUserReloadedStore = makeStore(userID: "first-user")
        XCTAssertEqual(firstUserReloadedStore.selectedTotalMl, HydrationConstants.standardGlassMl)
    }

    private func makeStore(userID: String = "test-user") -> HydrationStore {
        HydrationStore(
            storage: storage,
            cloudService: NoopHydrationCloudService(),
            userID: userID
        )
    }
}
