//
//  HydrationModels.swift
//  H2Oliver
//
//  Created by Codex o

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
    var intervalMinutes = 30

    var intervalLabel: String {
        if intervalMinutes < 60 {
            return "\(intervalMinutes) min"
        }

        let hours = intervalMinutes / 60
        let minutes = intervalMinutes % 60
        if minutes == 0 {
            return "\(hours) h"
        }
        return "\(hours) h \(minutes) min"
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case startHour
        case endHour
        case intervalMinutes
        case intervalHours
    }

    init(
        isEnabled: Bool = false,
        startHour: Int = 9,
        endHour: Int = 21,
        intervalMinutes: Int = 30
    ) {
        self.isEnabled = isEnabled
        self.startHour = startHour
        self.endHour = endHour
        self.intervalMinutes = max(30, intervalMinutes)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        startHour = try container.decodeIfPresent(Int.self, forKey: .startHour) ?? 9
        endHour = try container.decodeIfPresent(Int.self, forKey: .endHour) ?? 21

        if let intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) {
            self.intervalMinutes = max(30, intervalMinutes)
        } else {
            if let intervalHours = try container.decodeIfPresent(Int.self, forKey: .intervalHours) {
                self.intervalMinutes = max(30, intervalHours * 60)
            } else {
                self.intervalMinutes = 30
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(startHour, forKey: .startHour)
        try container.encode(endHour, forKey: .endHour)
        try container.encode(intervalMinutes, forKey: .intervalMinutes)
    }
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
