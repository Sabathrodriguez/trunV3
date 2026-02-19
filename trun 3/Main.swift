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
        try? Auth.auth().signOut()
    }
}

struct MainView : View {
    @StateObject public var loginManager = LoginManager()
    
    var body: some View {
//        if loginManager.isLoggedIn {
            ContentView(loginManager: loginManager)
//        } else {
//            LoginView(loginManager: loginManager)
//        }
    }
}
