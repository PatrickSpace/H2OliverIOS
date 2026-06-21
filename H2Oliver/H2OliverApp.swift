//
//  H2OliverApp.swift
//  H2Oliver
//
//  Created by Patrick Lostaunau on 21/06/26.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn
import UserNotifications

@main
struct H2OliverApp: App {
    private let notificationDelegate = HydrationNotificationDelegate()

    init() {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

final class HydrationNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
