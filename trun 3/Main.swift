//
//  Main.swift
//  trun
//
//  Created by Sabath  Rodriguez on 1/20/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn
import AuthenticationServices
import CryptoKit

class LoginManager : ObservableObject {
    @Published var isLoggedIn = false
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

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

    /// The sign-in provider for the current user.
    enum AuthProvider {
        case email, google, apple, unknown
    }

    var currentAuthProvider: AuthProvider {
        guard let providerID = Auth.auth().currentUser?.providerData.first?.providerID else {
            return .unknown
        }
        switch providerID {
        case "password":        return .email
        case "google.com":      return .google
        case "apple.com":       return .apple
        default:                return .unknown
        }
    }

    /// Re-authenticate with email/password, then delete.
    func deleteAccountWithEmail(password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            completion(.failure(Self.deletionError("No user signed in.")))
            return
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        user.reauthenticate(with: credential) { [weak self] _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            self?.performDeletion(completion: completion)
        }
    }

    /// Re-authenticate with Google, then delete.
    func deleteAccountWithGoogle(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            completion(.failure(Self.deletionError("Unable to present Google sign-in.")))
            return
        }
        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
                guard let idToken = result.user.idToken?.tokenString else {
                    await MainActor.run { completion(.failure(Self.deletionError("Google sign-in: ID token missing."))) }
                    return
                }
                let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
                try await Auth.auth().currentUser?.reauthenticate(with: credential)
                self.performDeletion(completion: completion)
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    /// Re-authenticate with Apple, then delete. Returns a nonce for the ASAuthorizationController request.
    func prepareAppleReauth() -> String {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        return Self.sha256(nonce)
    }

    func deleteAccountWithApple(authorization: ASAuthorization, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            completion(.failure(Self.deletionError("Unable to fetch Apple ID token.")))
            return
        }
        let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: nil)
        Task {
            do {
                try await Auth.auth().currentUser?.reauthenticate(with: credential)
                self.performDeletion(completion: completion)
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    /// Delete user data from Firestore, Storage, and Firebase Auth.
    private func performDeletion(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            DispatchQueue.main.async { completion(.failure(Self.deletionError("No user signed in."))) }
            return
        }

        let uid = user.uid
        let db = Firestore.firestore()
        let storage = Storage.storage()

        // Delete Firestore user document
        db.collection("users").document(uid).delete()

        // Delete profile image from Storage (best-effort)
        storage.reference().child("profileImages/\(uid).jpg").delete(completion: nil)

        // Delete the Firebase Auth account
        user.delete { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    private static func deletionError(_ message: String) -> NSError {
        NSError(domain: "LoginManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
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
