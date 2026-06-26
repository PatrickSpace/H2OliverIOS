//
//  HydrationNotificationScheduler.swift
//  H2Oliver
//
//  Created by Codex on 21/06/26.
//

import Foundation
import UserNotifications

enum HydrationNotificationTestResult {
    case sent(simulatedDate: Date)
    case missingPermission
    case noUpcomingReminder
    case failedToSchedule
}

struct HydrationNotificationDiagnostics {
    let authorizationStatus: UNAuthorizationStatus
    let scheduledReminderCount: Int
    let testReminderCount: Int

    var totalPendingCount: Int {
        scheduledReminderCount + testReminderCount
    }
}

final class HydrationNotificationScheduler {
    static let shared = HydrationNotificationScheduler()

    private let notificationCenter = UNUserNotificationCenter.current()
    private let identifierPrefix = "h2oliver.reminder."
    private let scheduledIdentifierPrefix = "h2oliver.reminder.scheduled."
    private let testIdentifierPrefix = "h2oliver.reminder.test."
    private let maxScheduledReminderCount = 32

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func reschedule(
        settings: HydrationNotificationSettings,
        goal: HydrationGoal,
        todaysIntakeMl: Int,
        requestAuthorizationIfNeeded: Bool = false
    ) async {
        await cancelPendingReminders()

        guard settings.isEnabled else { return }
        guard await canScheduleNotifications(requestAuthorizationIfNeeded: requestAuthorizationIfNeeded) else {
            return
        }

        let requests = makeRequests(settings: settings, goal: goal, todaysIntakeMl: todaysIntakeMl)
        for request in requests {
            try? await notificationCenter.add(request)
        }
    }

    func cancelPendingReminders() async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func diagnostics() async -> HydrationNotificationDiagnostics {
        let settings = await notificationCenter.notificationSettings()
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let scheduledReminderCount = pendingRequests.filter {
            $0.identifier.hasPrefix(scheduledIdentifierPrefix)
        }.count
        let testReminderCount = pendingRequests.filter {
            $0.identifier.hasPrefix(testIdentifierPrefix)
        }.count

        return HydrationNotificationDiagnostics(
            authorizationStatus: settings.authorizationStatus,
            scheduledReminderCount: scheduledReminderCount,
            testReminderCount: testReminderCount
        )
    }

    func sendNextReminderNow(
        settings: HydrationNotificationSettings,
        goal: HydrationGoal,
        todaysIntakeMl: Int
    ) async -> HydrationNotificationTestResult {
        guard await canScheduleNotifications(requestAuthorizationIfNeeded: true) else {
            return .missingPermission
        }

        guard let nextReminder = makeReminderCandidates(
            settings: settings,
            goal: goal,
            todaysIntakeMl: todaysIntakeMl
        ).first else {
            return .noUpcomingReminder
        }

        await cancelPendingTestReminders()

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(testIdentifierPrefix)\(UUID().uuidString)",
            content: nextReminder.content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            return .sent(simulatedDate: nextReminder.date)
        } catch {
            return .failedToSchedule
        }
    }

    private func canScheduleNotifications(requestAuthorizationIfNeeded: Bool) async -> Bool {
        let settings = await notificationCenter.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined where requestAuthorizationIfNeeded:
            return await requestAuthorization()
        default:
            return false
        }
    }

    private func makeRequests(
        settings: HydrationNotificationSettings,
        goal: HydrationGoal,
        todaysIntakeMl: Int
    ) -> [UNNotificationRequest] {
        makeReminderCandidates(settings: settings, goal: goal, todaysIntakeMl: todaysIntakeMl)
            .prefix(maxScheduledReminderCount)
            .map(\.request)
    }

    private func makeReminderCandidates(
        settings: HydrationNotificationSettings,
        goal: HydrationGoal,
        todaysIntakeMl: Int
    ) -> [ReminderCandidate] {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: Date())
        let startHour = min(settings.startHour, settings.endHour)
        let endHour = max(settings.startHour, settings.endHour)
        let intervalMinutes = max(1, settings.intervalMinutes)

        return (0..<7).flatMap { dayOffset -> [ReminderCandidate] in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                return []
            }

            if dayOffset == 0, todaysIntakeMl >= goal.targetMl {
                return []
            }

            let startMinuteOfDay = startHour * 60
            let endMinuteOfDay = endHour * 60

            return stride(from: startMinuteOfDay, through: endMinuteOfDay, by: intervalMinutes).compactMap { minuteOfDay in
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = minuteOfDay / 60
                components.minute = minuteOfDay % 60

                guard let fireDate = calendar.date(from: components), fireDate > Date() else {
                    return nil
                }

                let content = makeReminderContent(
                    goal: goal,
                    todaysIntakeMl: todaysIntakeMl,
                    dayOffset: dayOffset
                )

                let identifier = "\(scheduledIdentifierPrefix)\(day.hydrationDayKey).\(minuteOfDay)"
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                return ReminderCandidate(date: fireDate, content: content, request: request)
            }
        }
    }

    private func cancelPendingTestReminders() async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(testIdentifierPrefix) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func makeReminderContent(
        goal: HydrationGoal,
        todaysIntakeMl: Int,
        dayOffset: Int
    ) -> UNMutableNotificationContent {
        let remainingMl = max(goal.targetMl - (dayOffset == 0 ? todaysIntakeMl : 0), 0)
        let content = UNMutableNotificationContent()
        content.title = "Hora de tomar agua"
        content.body = remainingMl > 0
            ? "Te faltan \(remainingMl) ml para completar tu objetivo de hoy."
            : "Mantén tu racha de hidratación."
        content.sound = .default
        return content
    }

    private struct ReminderCandidate {
        let date: Date
        let content: UNMutableNotificationContent
        let request: UNNotificationRequest
    }
}
