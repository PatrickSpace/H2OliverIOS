//
//  ContentView.swift
//  H2Oliver
//
//  Created by Patrick Lostaunau on 21/06/26.
//

import SwiftUI
import UIKit
import UserNotifications

struct ContentView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var store = HydrationStore()
    @State private var notificationScheduleTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    AppHeader(store: store)
                    SyncStatusBanner(store: store)
                    WeekScroller(store: store)
                    DailyProgressCard(store: store)
                    QuickLogSection(store: store)
                    HistorySection(store: store)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(AppBackdrop())
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tint(.waterBlue)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        SettingsView(authViewModel: authViewModel, store: store)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.waterBlue)
                    }
                    .accessibilityLabel("Configuración")
                }
            }
            .task {
                store.selectedDate = Calendar.app.startOfDay(for: Date())
                store.configureCloudSync(userID: authViewModel.userID)
                scheduleNotifications()
            }
            .onChange(of: authViewModel.userID) { _, userID in
                store.configureCloudSync(userID: userID)
            }
            .onChange(of: store.goal) { _, _ in
                store.saveGoal()
                scheduleNotifications()
            }
            .onChange(of: store.notificationSettings) { oldSettings, newSettings in
                store.saveNotifications()
                scheduleNotifications(requestAuthorizationIfNeeded: !oldSettings.isEnabled && newSettings.isEnabled)
            }
            .onChange(of: store.selectedTotalMl) { _, _ in
                scheduleNotifications()
            }
        }
    }

    private func scheduleNotifications(requestAuthorizationIfNeeded: Bool = false) {
        notificationScheduleTask?.cancel()
        notificationScheduleTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            await HydrationNotificationScheduler.shared.reschedule(
                settings: store.notificationSettings,
                goal: store.goal,
                todaysIntakeMl: store.intake(for: Date()).totalMl,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            )
        }
    }
}

private struct SyncStatusBanner: View {
    @ObservedObject var store: HydrationStore

    var body: some View {
        if let syncErrorMessage = store.syncErrorMessage {
            HStack(spacing: 10) {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(Color.waterBlue)
                Text(syncErrorMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Spacer()
                Button {
                    store.clearSyncError()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.mutedAqua)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ocultar error de sincronización")
            }
            .padding(12)
            .background(Color.cardSurface.opacity(0.86), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.waterBlue.opacity(0.18), lineWidth: 1)
            }
        }
    }
}

private struct WeekScroller: View {
    @ObservedObject var store: HydrationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.selectedDate = Calendar.app.startOfDay(for: Date())
                    }
                } label: {
                    Label("Hoy", systemImage: "calendar")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Seleccionar hoy")
                Spacer()
                Text(todayText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.mutedAqua)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.weekDays(around: store.selectedDate)) { day in
                            DayChip(
                                day: day,
                                progress: store.progress(for: day.date),
                                isSelected: Calendar.app.isDate(day.date, inSameDayAs: store.selectedDate)
                            )
                            .id(day.id)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    store.selectedDate = day.date
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    proxy.scrollTo(store.selectedDate, anchor: .center)
                }
                .onChange(of: store.selectedDate) { _, newDate in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        proxy.scrollTo(newDate, anchor: .center)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private var todayText: String {
        if Calendar.app.isDateInToday(store.selectedDate) {
            return "Seleccionado"
        }
        return store.selectedDate.formatted(.dateTime.day().month(.abbreviated))
    }
}

private struct AppHeader: View {
    @ObservedObject var store: HydrationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.34))
                    Image(systemName: "drop.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .deepAqua.opacity(0.22), radius: 8, x: 0, y: 5)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 2) {
                    Text("H2Oliver")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)
                    Text(headerSubtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer()
            }

            Text("Tu ritmo de agua, claro y sin fricción.")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [.waterBlue, .deepAqua],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "water.waves")
                .font(.system(size: 86, weight: .light))
                .foregroundStyle(.white.opacity(0.16))
                .offset(x: 10, y: 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: .waterBlue.opacity(0.24), radius: 24, x: 0, y: 14)
    }

    private var headerSubtitle: String {
        if store.hasCompletedSelectedGoal {
            return "Objetivo completado"
        }

        let remaining = max(store.goal.targetMl - store.selectedTotalMl, 0)
        return "Faltan \(remaining) ml hoy"
    }
}

private struct DayChip: View {
    let day: WeekDay
    let progress: Double
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(day.weekdayText.prefix(1))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.86) : Color.mutedAqua)
            Text(day.dayText)
                .font(.title3.weight(.bold))
                .foregroundStyle(isSelected ? Color.white : Color.ink)
            Circle()
                .fill(progress >= 1 ? Color.freshMint : (progress > 0 ? Color.waterBlue : Color.softAqua))
                .frame(width: 8, height: 8)
        }
        .frame(width: 48, height: 78)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(isSelected ? Color.deepAqua : Color.chipSurface)
                .shadow(color: isSelected ? Color.waterBlue.opacity(0.22) : Color.clear, radius: 12, x: 0, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? Color.white.opacity(0.22) : Color.cardStroke, lineWidth: 1)
        }
    }
}

private struct DailyProgressCard: View {
    @ObservedObject var store: HydrationStore

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Progreso diario")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.ink)
                    Text("\(store.selectedTotalMl) / \(store.goal.targetMl) ml")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .foregroundStyle(Color.ink)
                    Text("\(Int(store.goal.targetGlasses.rounded(.up))) vasos aprox. · 1 vaso = \(HydrationConstants.standardGlassMl) ml")
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedAqua)
                }
                Spacer()
                ProgressBadge(isCompleted: store.hasCompletedSelectedGoal)
            }

            WaterProgressBar(progress: store.selectedProgress, isCompleted: store.hasCompletedSelectedGoal)

            HStack {
                StatPill(title: "Objetivo", value: store.goal.displayText)
                StatPill(title: "Falta", value: "\(max(store.goal.targetMl - store.selectedTotalMl, 0)) ml")
            }
        }
        .padding(22)
        .background(Color.cardSurface.opacity(0.9), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.cardStroke, lineWidth: 1)
        }
        .shadow(color: Color.cardShadow, radius: 24, x: 0, y: 14)
    }
}

private struct ProgressBadge: View {
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill((isCompleted ? Color.freshMint : Color.softAqua).opacity(0.92))
            Image(systemName: isCompleted ? "checkmark.seal.fill" : "drop.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(isCompleted ? Color.deepAqua : Color.waterBlue)
        }
        .frame(width: 62, height: 62)
    }
}

private struct WaterProgressBar: View {
    let progress: Double
    let isCompleted: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clampedProgress = min(max(progress, 0), 1)
            let fillWidth = max(10, width * clampedProgress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.softAqua.opacity(0.88))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: isCompleted ? [.freshMint, .deepAqua] : [.skyAqua, .waterBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth)

                HStack {
                    Spacer()
                    Text("\(Int((clampedProgress * 100).rounded()))%")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                }
            }
        }
        .frame(height: 20)
        .clipShape(Capsule())
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.mutedAqua)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.tintedSurface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct QuickLogSection: View {
    @ObservedObject var store: HydrationStore

    var body: some View {
        SectionContainer(title: "Registrar agua", systemImage: "plus.circle.fill") {
            Button {
                store.addGlass()
            } label: {
                Label("Agregar vaso (\(HydrationConstants.standardGlassMl) ml)", systemImage: "drop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryHydrationButtonStyle())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 12)], spacing: 12) {
                ForEach(store.bottles) { bottle in
                    Button {
                        store.addBottle(bottle)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: bottle.iconName)
                                .font(.title2)
                                .foregroundStyle(Color.waterBlue)
                                .frame(width: 38, height: 38)
                                .background(Color.softAqua, in: Circle())
                            Text(bottle.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.ink)
                            Text("\(bottle.capacityMl) ml")
                                .font(.caption)
                                .foregroundStyle(Color.mutedAqua)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(Color.rowSurface, in: RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.cardStroke, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

        }
    }
}

private struct SettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var store: HydrationStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    GoalSettingsView(store: store)
                } label: {
                    SettingsRow(
                        title: "Objetivo",
                        subtitle: store.goal.displayText,
                        systemImage: "target"
                    )
                }

                NavigationLink {
                    NotificationSettingsView(store: store)
                } label: {
                    SettingsRow(
                        title: "Notificaciones",
                        subtitle: store.notificationSettings.isEnabled ? "Activas" : "Desactivadas",
                        systemImage: "bell.badge"
                    )
                }

                NavigationLink {
                    BottleSettingsView(store: store)
                } label: {
                    SettingsRow(
                        title: "Botellas",
                        subtitle: "Agregar o eliminar tomatodos",
                        systemImage: "waterbottle"
                    )
                }

                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsRow(
                        title: "Apariencia",
                        subtitle: "Claro, oscuro o sistema",
                        systemImage: "circle.lefthalf.filled"
                    )
                }
            } header: {
                Text("Preferencias")
            }

            Section {
                Button(role: .destructive) {
                    authViewModel.signOut()
                } label: {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppBackdrop())
        .navigationTitle("Configuración")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}

private struct SettingsRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.mutedAqua)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.waterBlue)
                .frame(width: 34, height: 34)
                .background(Color.softAqua, in: Circle())
        }
        .padding(.vertical, 4)
    }
}

private struct GoalSettingsView: View {
    @ObservedObject var store: HydrationStore

    var body: some View {
        ScrollView {
            GoalSection(store: store)
                .padding(20)
        }
        .background(AppBackdrop())
        .navigationTitle("Objetivo")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct NotificationSettingsView: View {
    @ObservedObject var store: HydrationStore

    var body: some View {
        ScrollView {
            NotificationSection(store: store)
                .padding(20)
        }
        .background(AppBackdrop())
        .navigationTitle("Notificaciones")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct AppearanceSettingsView: View {
    var body: some View {
        ScrollView {
            AppearanceSection()
                .padding(20)
        }
        .background(AppBackdrop())
        .navigationTitle("Apariencia")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct BottleSettingsView: View {
    @ObservedObject var store: HydrationStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AddBottleView(store: store)
                } label: {
                    SettingsRow(
                        title: "Agregar botella",
                        subtitle: "Crea un tomatodo personalizado",
                        systemImage: "plus.circle.fill"
                    )
                }
            }

            Section {
                ForEach(store.bottles) { bottle in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bottle.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.ink)
                            Text("\(bottle.capacityMl) ml")
                                .font(.caption)
                                .foregroundStyle(Color.mutedAqua)
                        }
                    } icon: {
                        Image(systemName: bottle.iconName)
                            .foregroundStyle(Color.waterBlue)
                            .frame(width: 34, height: 34)
                            .background(Color.softAqua, in: Circle())
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: store.deleteBottle)
            } header: {
                Text("Guardadas")
            } footer: {
                Text("Desliza una botella hacia la izquierda para eliminarla.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppBackdrop())
        .navigationTitle("Botellas")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct GoalSection: View {
    @ObservedObject var store: HydrationStore

    var body: some View {
        SectionContainer(title: "Objetivo", systemImage: "target") {
            Picker("Unidad", selection: $store.goal.unit) {
                ForEach(GoalUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .tint(.waterBlue)

            if store.goal.unit == .glasses {
                HydrationStepper(
                    title: "\(store.goal.glasses) vasos al día",
                    systemImage: "drop",
                    value: $store.goal.glasses,
                    range: 1...30
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HydrationDoubleStepper(
                        title: String(format: "%.2f litros al día", store.goal.liters),
                        systemImage: "drop",
                        value: $store.goal.liters,
                        range: 0.5...6,
                        step: 0.25
                    )
                    Text("Equivale a \(Int(store.goal.targetGlasses.rounded(.up))) vasos de \(HydrationConstants.standardGlassMl) ml.")
                        .font(.caption)
                        .foregroundStyle(Color.mutedAqua)
                }
            }
        }
    }
}

private struct NotificationSection: View {
    @ObservedObject var store: HydrationStore
    @State private var testNotificationStatus: String?
    @State private var diagnosticsText: String?

    var body: some View {
        SectionContainer(title: "Recordatorios locales", systemImage: "bell.badge") {
            Toggle(isOn: $store.notificationSettings.isEnabled) {
                Text("Activar notificaciones")
                    .foregroundStyle(Color.ink)
            }
                .tint(.waterBlue)

            VStack(spacing: 12) {
                HydrationStepper(
                    title: "Desde \(formattedHour(store.notificationSettings.startHour))",
                    systemImage: "sunrise",
                    value: $store.notificationSettings.startHour,
                    range: 0...23,
                    isEnabled: store.notificationSettings.isEnabled
                )
                HydrationStepper(
                    title: "Hasta \(formattedHour(store.notificationSettings.endHour))",
                    systemImage: "moon",
                    value: $store.notificationSettings.endHour,
                    range: 0...23,
                    isEnabled: store.notificationSettings.isEnabled
                )
                HydrationStepper(
                    title: "Cada \(store.notificationSettings.intervalLabel)",
                    systemImage: "clock",
                    value: $store.notificationSettings.intervalMinutes,
                    range: 30...360,
                    step: 30,
                    isEnabled: store.notificationSettings.isEnabled
                )
            }

            Text("La app programa recordatorios locales dentro del horario elegido y los cancela cuando completas tu objetivo del día.")
                .font(.caption)
                .foregroundStyle(Color.mutedAqua)

            Button {
                Task {
                    let result = await HydrationNotificationScheduler.shared.sendNextReminderNow(
                        settings: store.notificationSettings,
                        goal: store.goal,
                        todaysIntakeMl: store.intake(for: Date()).totalMl
                    )
                    switch result {
                    case .sent(let simulatedDate):
                        testNotificationStatus = "Enviando ahora la notificación que tocaría a las \(simulatedDate.formatted(date: .omitted, time: .shortened))."
                    case .missingPermission:
                        testNotificationStatus = "No hay permiso de notificaciones. Actívalo en Ajustes de iOS."
                    case .noUpcomingReminder:
                        testNotificationStatus = "No hay una siguiente notificación para simular con la configuración actual."
                    case .failedToSchedule:
                        testNotificationStatus = "iOS no pudo programar la notificación de prueba."
                    }
                }
            } label: {
                Label("Enviar siguiente notificación ahora", systemImage: "bell.and.waves.left.and.right")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(SecondaryHydrationButtonStyle())

            if let testNotificationStatus {
                Text(testNotificationStatus)
                    .font(.caption)
                    .foregroundStyle(Color.mutedAqua)
            }

            Button {
                Task {
                    let diagnostics = await HydrationNotificationScheduler.shared.diagnostics()
                    diagnosticsText = "Permiso: \(diagnostics.authorizationStatus.displayText). Pendientes: \(diagnostics.totalPendingCount) (\(diagnostics.scheduledReminderCount) reales, \(diagnostics.testReminderCount) prueba)."
                }
            } label: {
                Label("Revisar estado de notificaciones", systemImage: "checklist")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(SecondaryHydrationButtonStyle())

            if let diagnosticsText {
                Text(diagnosticsText)
                    .font(.caption)
                    .foregroundStyle(Color.mutedAqua)
            }
        }
    }

    private func formattedHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

}

private struct AppearanceSection: View {
    @AppStorage("app.appearance") private var selectedAppearance = AppAppearance.system.rawValue

    var body: some View {
        SectionContainer(title: "Apariencia", systemImage: "circle.lefthalf.filled") {
            Picker("Modo de color", selection: $selectedAppearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Label(appearance.title, systemImage: appearance.iconName)
                        .tag(appearance.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .tint(.waterBlue)

            HStack(spacing: 10) {
                Image(systemName: currentAppearance.iconName)
                    .foregroundStyle(Color.waterBlue)
                    .frame(width: 34, height: 34)
                    .background(Color.softAqua, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Modo \(currentAppearance.title.lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                    Text(helperText)
                        .font(.caption)
                        .foregroundStyle(Color.mutedAqua)
                }
            }
            .padding(10)
            .background(Color.rowSurface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: selectedAppearance) ?? .system
    }

    private var helperText: String {
        switch currentAppearance {
        case .system:
            "H2Oliver seguirá la apariencia configurada en iOS."
        case .light:
            "La app usará siempre el tema claro."
        case .dark:
            "La app usará siempre el tema oscuro."
        }
    }
}

private extension UNAuthorizationStatus {
    var displayText: String {
        switch self {
        case .notDetermined:
            "sin solicitar"
        case .denied:
            "denegado"
        case .authorized:
            "autorizado"
        case .provisional:
            "provisional"
        case .ephemeral:
            "temporal"
        @unknown default:
            "desconocido"
        }
    }
}

private struct HistorySection: View {
    @ObservedObject var store: HydrationStore

    var body: some View {
        SectionContainer(title: "Registro del día", systemImage: "list.bullet.clipboard") {
            if store.selectedDayIntake.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "drop")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(Color.mutedAqua.opacity(0.55))
                    Text("Aún no hay registros")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.mutedAqua)
                    Text("Agrega un vaso o un tomatodo para empezar este día.")
                        .font(.body)
                        .foregroundStyle(Color.mutedAqua)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 150)
            } else {
                ForEach(store.selectedDayIntake.entries) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.sourceName == "Vaso" ? "drop.fill" : "waterbottle.fill")
                            .foregroundStyle(Color.waterBlue)
                            .frame(width: 34, height: 34)
                            .background(Color.softAqua, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.sourceName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.ink)
                            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Color.mutedAqua)
                        }
                        Spacer()
                        Text("\(entry.amountMl) ml")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.ink)

                        Button(role: .destructive) {
                            store.removeEntry(entry)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Eliminar registro")
                    }
                    .padding(10)
                    .background(Color.rowSurface, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

private struct HydrationStepper: View {
    let title: String
    let systemImage: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var isEnabled = true

    var body: some View {
        HydrationStepperRow(
            title: title,
            systemImage: systemImage,
            isEnabled: isEnabled,
            canDecrease: value > range.lowerBound,
            canIncrease: value < range.upperBound,
            decrease: {
                value = max(range.lowerBound, value - step)
            },
            increase: {
                value = min(range.upperBound, value + step)
            }
        )
    }
}

private struct HydrationDoubleStepper: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var isEnabled = true

    var body: some View {
        HydrationStepperRow(
            title: title,
            systemImage: systemImage,
            isEnabled: isEnabled,
            canDecrease: value > range.lowerBound,
            canIncrease: value < range.upperBound,
            decrease: {
                value = max(range.lowerBound, value - step)
            },
            increase: {
                value = min(range.upperBound, value + step)
            }
        )
    }
}

private struct HydrationStepperRow: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isEnabled ? Color.ink : Color.mutedAqua)

            Spacer()

            HStack(spacing: 10) {
                stepButton(systemName: "minus", isActive: isEnabled && canDecrease, action: decrease)
                Divider()
                    .frame(height: 26)
                    .overlay(Color.mutedAqua.opacity(0.18))
                stepButton(systemName: "plus", isActive: isEnabled && canIncrease, action: increase)
            }
        }
    }

    private func stepButton(systemName: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .foregroundStyle(isActive ? Color.waterBlue : Color.mutedAqua.opacity(0.55))
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(isActive ? Color.softAqua.opacity(0.9) : Color.tintedSurface.opacity(0.72))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isActive)
    }
}

private struct AddBottleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: HydrationStore
    @State private var name = "Mi tomatodo"
    @State private var capacityMl = 750
    @State private var iconName = "waterbottle.fill"

    private let iconOptions = ["waterbottle", "waterbottle.fill", "drop.circle", "drop.circle.fill"]

    var body: some View {
        Form {
            Section("Tomatodo") {
                TextField("Nombre", text: $name)
                Stepper(value: $capacityMl, in: 100...3000, step: 50) {
                    Text("\(capacityMl) ml netos")
                }
            }

            Section("Icono") {
                Picker("Icono", selection: $iconName) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Label(icon, systemImage: icon).tag(icon)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("Guardados") {
                ForEach(store.bottles) { bottle in
                    Label("\(bottle.name) - \(bottle.capacityMl) ml", systemImage: bottle.iconName)
                }
                .onDelete(perform: store.deleteBottle)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackdrop())
        .tint(.waterBlue)
        .navigationTitle("Nueva botella")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    store.addBottle(name: name, capacityMl: capacityMl, iconName: iconName)
                    dismiss()
                }
            }
        }
    }
}

private struct SectionContainer<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.ink)

            content
        }
        .padding(18)
        .background(Color.cardSurface.opacity(0.78), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.cardStroke, lineWidth: 1)
        }
        .shadow(color: Color.cardShadow.opacity(0.72), radius: 18, x: 0, y: 10)
    }
}

struct AppBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [.hydrationBackground, .mistAqua, .backdropBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.skyAqua.opacity(0.28))
                .frame(width: 220, height: 220)
                .blur(radius: 12)
                .offset(x: 86, y: -76)
        }
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(Color.freshMint.opacity(0.16))
                .frame(width: 180, height: 180)
                .blur(radius: 18)
                .offset(x: -88, y: 180)
        }
        .ignoresSafeArea()
    }
}

private struct PrimaryHydrationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [.waterBlue, .deepAqua],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .shadow(color: .waterBlue.opacity(configuration.isPressed ? 0.12 : 0.22), radius: 14, x: 0, y: 9)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct SecondaryHydrationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(Color.waterBlue)
            .background(Color.softAqua.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension Color {
    static let hydrationBackground = adaptive(light: Color(red: 0.93, green: 0.98, blue: 1), dark: Color(red: 0.03, green: 0.08, blue: 0.11))
    static let mistAqua = adaptive(light: Color(red: 0.84, green: 0.95, blue: 0.98), dark: Color(red: 0.05, green: 0.14, blue: 0.18))
    static let backdropBottom = adaptive(light: .white, dark: Color(red: 0.02, green: 0.05, blue: 0.07))
    static let softAqua = adaptive(light: Color(red: 0.83, green: 0.94, blue: 0.98), dark: Color(red: 0.08, green: 0.24, blue: 0.30))
    static let skyAqua = adaptive(light: Color(red: 0.19, green: 0.78, blue: 0.94), dark: Color(red: 0.23, green: 0.82, blue: 0.98))
    static let waterBlue = adaptive(light: Color(red: 0.03, green: 0.45, blue: 0.88), dark: Color(red: 0.29, green: 0.74, blue: 1))
    static let deepAqua = adaptive(light: Color(red: 0.02, green: 0.30, blue: 0.46), dark: Color(red: 0.05, green: 0.43, blue: 0.62))
    static let freshMint = adaptive(light: Color(red: 0.46, green: 0.91, blue: 0.71), dark: Color(red: 0.42, green: 0.96, blue: 0.75))
    static let ink = adaptive(light: Color(red: 0.06, green: 0.15, blue: 0.20), dark: Color(red: 0.90, green: 0.97, blue: 0.99))
    static let mutedAqua = adaptive(light: Color(red: 0.33, green: 0.48, blue: 0.55), dark: Color(red: 0.63, green: 0.78, blue: 0.84))
    static let tintedSurface = adaptive(light: Color(red: 0.91, green: 0.97, blue: 0.99), dark: Color(red: 0.07, green: 0.17, blue: 0.21))
    static let cardSurface = adaptive(light: .white, dark: Color(red: 0.06, green: 0.13, blue: 0.16))
    static let chipSurface = adaptive(light: Color.white.opacity(0.72), dark: Color(red: 0.08, green: 0.18, blue: 0.22).opacity(0.86))
    static let rowSurface = adaptive(light: Color.white.opacity(0.82), dark: Color(red: 0.08, green: 0.18, blue: 0.22).opacity(0.9))
    static let cardStroke = adaptive(light: Color.white.opacity(0.72), dark: Color(red: 0.33, green: 0.62, blue: 0.72).opacity(0.22))
    static let cardShadow = adaptive(light: Color.deepAqua.opacity(0.1), dark: Color.black.opacity(0.36))

    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView(authViewModel: AuthViewModel())
                .preferredColorScheme(.light)
                .previewDisplayName("Claro")

            ContentView(authViewModel: AuthViewModel())
                .preferredColorScheme(.dark)
                .previewDisplayName("Oscuro")
        }
    }
}
