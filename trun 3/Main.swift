//
//  Main.swift
//  trun
//
//  Created by Sabath  Rodriguez on 1/20/25.
//

import SwiftUI
import FirebaseAuth

class LoginManager : ObservableObject {
    @Published var isLoggedIn = false
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        // Firebase persists the auth token in the Keychain automatically.
        // Listen for auth state changes so the app stays in sync on launch and
        // after the OS kills/restores the session.
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                withAnimation {
                    self?.isLoggedIn = user != nil
                }
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func login() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                self.isLoggedIn = true
            }
        }
    }

    func logout() {
        AnalyticsService.logLogout()
        try? Auth.auth().signOut()
    }
}

enum AuthScreen {
    case signIn
    case signUp
}

struct MainView : View {
    @StateObject public var loginManager = LoginManager()
    @ObservedObject private var consentManager = AnalyticsConsentManager.shared
    @State private var authScreen: AuthScreen = .signIn
    @State private var showConsentPrompt = false

    var body: some View {
        Group {
            if loginManager.isLoggedIn {
                ContentView(loginManager: loginManager)
            } else {
                switch authScreen {
                case .signIn:
                    LoginView(loginManager: loginManager, showSignUp: {
                        withAnimation { authScreen = .signUp }
                    })
                case .signUp:
                    SignUpView(loginManager: loginManager, showSignIn: {
                        withAnimation { authScreen = .signIn }
                    })
                }
            }
        }
        .onAppear {
            if !consentManager.hasPromptedUser {
                showConsentPrompt = true
            }
        }
        .alert("Help Improve TrunRun", isPresented: $showConsentPrompt) {
            Button("Allow") {
                consentManager.consentGranted = true
                consentManager.hasPromptedUser = true
            }
            Button("Don't Allow", role: .cancel) {
                consentManager.consentGranted = false
                consentManager.hasPromptedUser = true
            }
        } message: {
            Text("We use Firebase Analytics and Crashlytics to understand how the app is used and to fix crashes. No personal data is sold or shared with third parties. You can change this anytime in your profile settings.")
        }
    }
}
