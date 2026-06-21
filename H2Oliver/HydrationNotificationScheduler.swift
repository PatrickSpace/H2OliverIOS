//
//  HydrationNotificationScheduler.swift
//  H2Oliver
//
//  Created by Codex on 21/06/26.
//

import Foundation
import UserNotifications
//kmkmkm
final class HydrationNotificationScheduler {
    static let shared = HydrationNotificationScheduler()

    private let notificationCenter = UNUserNotificationCenter.current()
    private let identifierPrefix = "h2oliver.reminder."

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

    func sendNextReminderNow(
        settings: HydrationNotificationSettings,
        goal: HydrationGoal,
        todaysIntakeMl: Int
    ) async -> Date? {
        guard await canScheduleNotifications(requestAuthorizationIfNeeded: true) else {
            return nil
        }

        guard let nextReminder = makeReminderCandidates(
            settings: settings,
            goal: goal,
            todaysIntakeMl: todaysIntakeMl
        ).first else {
            return nil
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)test.\(UUID().uuidString)",
            content: nextReminder.content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            return nextReminder.date
        } catch {
            return nil
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
        makeReminderCandidates(settings: settings, goal: goal, todaysIntakeMl: todaysIntakeMl).map(\.request)
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
        let interval = max(1, settings.intervalHours)

        return (0..<7).flatMap { dayOffset -> [ReminderCandidate] in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                return []
            }

            if dayOffset == 0, todaysIntakeMl >= goal.targetMl {
                return []
            }

            return stride(from: startHour, through: endHour, by: interval).compactMap { hour in
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = hour
                components.minute = 0

                guard let fireDate = calendar.date(from: components), fireDate > Date() else {
                    return nil
                }

                let content = makeReminderContent(
                    goal: goal,
                    todaysIntakeMl: todaysIntakeMl,
                    dayOffset: dayOffset
                )

                let identifier = "\(identifierPrefix)\(day.hydrationDayKey).\(hour)"
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                return ReminderCandidate(date: fireDate, content: content, request: request)
            }
        }
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
