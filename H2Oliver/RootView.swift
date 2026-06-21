//
//  RootView.swift
//  H2Oliver
//
//  Created by Codex on 21/06/26.
//

import SwiftUI

struct RootView: View {
    @AppStorage("app.appearance") private var selectedAppearance = AppAppearance.system.rawValue
    @StateObject private var authViewModel = AuthViewModel()

    var body: some View {
        Group {
            if authViewModel.isLoading {
                LoadingView()
            } else if authViewModel.user == nil {
                SignInView(authViewModel: authViewModel)
            } else {
                ContentView(authViewModel: authViewModel)
            }
        }
        .preferredColorScheme(appAppearance.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: authViewModel.isLoading)
        .animation(.easeInOut(duration: 0.2), value: authViewModel.userID)
        .animation(.easeInOut(duration: 0.2), value: selectedAppearance)
    }

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: selectedAppearance) ?? .system
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.waterBlue)
            Text("Preparando H2Oliver")
                .font(.headline)
                .foregroundStyle(Color.mutedAqua)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
    }
}

private struct SignInView: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.waterBlue, .deepAqua],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "drop.fill")
                        .font(.system(size: 54, weight: .black))
                        .foregroundStyle(.white)
                }
                .frame(width: 104, height: 104)
                .shadow(color: .waterBlue.opacity(0.24), radius: 24, x: 0, y: 14)

                Text("H2Oliver")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(Color.ink)

                Text("Registra tus vasos, configura recordatorios y mantén tu historial de hidratación sincronizado.")
                    .font(.body)
                    .foregroundStyle(Color.mutedAqua)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    await authViewModel.signInWithGoogle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text("Continuar con Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.waterBlue, .deepAqua],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .foregroundStyle(.white)
                .shadow(color: .waterBlue.opacity(0.22), radius: 14, x: 0, y: 9)
            }
            .disabled(authViewModel.isLoading)

            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(28)
        .background(AppBackdrop())
    }
}

#Preview {
    RootView()
}
