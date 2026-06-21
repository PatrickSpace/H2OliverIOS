//
//  HydrationModels.swift
//  H2Oliver
//
//  Created by Codex on 21/06/26.
//

import Foundation

enum HydrationConstants {
    static let standardGlassMl = 250
}

enum GoalUnit: String, CaseIterable, Codable, Identifiable {
    case glasses
    case liters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glasses:
            "Vasos"
        case .liters:
            "Litros"
        }
    }
}

struct HydrationGoal: Codable, Equatable {
    var unit: GoalUnit = .glasses
    var glasses: Int = 8
    var liters: Double = 2

    var targetMl: Int {
        switch unit {
        case .glasses:
            glasses * HydrationConstants.standardGlassMl
        case .liters:
            Int((liters * 1000).rounded())
        }
    }

    var targetGlasses: Double {
        Double(targetMl) / Double(HydrationConstants.standardGlassMl)
    }

    var displayText: String {
        switch unit {
        case .glasses:
            "\(glasses) vasos"
        case .liters:
            String(format: "%.1f L", liters)
        }
    }
}

struct Bottle: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var iconName: String
    var capacityMl: Int

    static let presets: [Bottle] = [
        Bottle(name: "Tomatodo mini", iconName: "waterbottle", capacityMl: 500),
        Bottle(name: "Tomatodo diario", iconName: "waterbottle.fill", capacityMl: 750),
        Bottle(name: "Botella grande", iconName: "drop.circle.fill", capacityMl: 1000)
    ]
}

struct IntakeEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var amountMl: Int
    var sourceName: String
    var createdAt: Date = Date()
    var dayKey: String = Date().hydrationDayKey

    init(
        id: UUID = UUID(),
        amountMl: Int,
        sourceName: String,
        createdAt: Date = Date(),
        dayKey: String? = nil
    ) {
        self.id = id
        self.amountMl = amountMl
        self.sourceName = sourceName
        self.createdAt = createdAt
        self.dayKey = dayKey ?? createdAt.hydrationDayKey
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case amountMl
        case sourceName
        case createdAt
        case dayKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        amountMl = try container.decode(Int.self, forKey: .amountMl)
        sourceName = try container.decode(String.self, forKey: .sourceName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        dayKey = try container.decodeIfPresent(String.self, forKey: .dayKey) ?? createdAt.hydrationDayKey
    }
}

struct DayIntake: Codable, Equatable {
    var dayKey: String
    var entries: [IntakeEntry] = []

    var totalMl: Int {
        entries.reduce(0) { $0 + $1.amountMl }
    }
}

extension Sequence where Element == IntakeEntry {
    func groupedByDayKey() -> [String: DayIntake] {
        reduce(into: [:]) { records, entry in
            var day = records[entry.dayKey] ?? DayIntake(dayKey: entry.dayKey)
            day.entries.append(entry)
            day.entries.sort { $0.createdAt > $1.createdAt }
            records[entry.dayKey] = day
        }
    }
}

struct HydrationNotificationSettings: Codable, Equatable {
    var isEnabled = false
    var startHour = 9
    var endHour = 21
    var intervalHours = 1
}

struct WeekDay: Identifiable, Equatable {
    let date: Date
    let weekdayText: String
    let dayText: String

    var id: Date { date }
}

extension Calendar {
    static var app: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_PE")
        calendar.timeZone = .current
        return calendar
    }
}

extension Date {
    var hydrationDayKey: String {
        Self.dayKeyFormatter.string(from: self)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .app
        formatter.locale = Locale(identifier: "es_PE")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
