//
//  LoginScreen.swift
//  trun
//
//  Created by Sabath Rodriguez on 1/8/25.
//

import SwiftUI
import FirebaseCore
import Firebase
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift
import Foundation
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @State private var error: String = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isAuthenticated = false
    @State private var forgotpassword = false
    @State private var currentNonce: String?
    
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var loginManager: LoginManager
    
    var body: some View {
        ZStack {
            // BACKGROUND IMAGE
            // Assuming "freedom" exists in Assets.xcassets
            Image("freedom")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .edgesIgnoringSafeArea(.all)
                .overlay(Color.black.opacity(0.4)) // Dark overlay for text readability
            
            VStack(spacing: 20) {
                Spacer()
                
                // LOGO / TITLE
                Text("trun")
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 10)
                    .padding(.bottom, 20)
                
                VStack(spacing: 15) {
                    // INPUT FIELDS
                    TextField("Email", text: $username)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .foregroundColor(.white) // Ensure text is visible
                        .accentColor(.white)
                    
                    SecureField("Password", text: $password)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .accentColor(.white)
                    
                    // LOGIN BUTTON
                    Button(action: {
                        if authenticateUser() {
                            signIn(email: username, password: password)
                        }
                    }) {
                        Text("Sign In")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    // SIGN UP BUTTON
                    Button(action: {
                        if authenticateUser() {
                            signUp(email: username, password: password)
                        }
                    }) {
                        Text("Create Account")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                    
                    Text("Password must contain 1 special character and 1 number.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 30)
                
                Button("Forgot Password?") {
                    forgotpassword = true
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.top)
                
                Spacer()
                
                // GOOGLE SIGN IN
                VStack {
                    Button(action: {
                        Task {
                            do {
                                try await googleOauth()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "globe")
                            Text("Continue with Google")
                        }
                        .foregroundColor(.black)
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(25)
                        .padding(.horizontal, 30)
                    }
                    
                    // APPLE SIGN IN
                    SignInWithAppleButton(.signIn, onRequest: { request in
                        let nonce = randomNonceString()
                        currentNonce = nonce
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = sha256(nonce)
                    }, onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            Task {
                                do {
                                    try await appleSignIn(authorization: authorization)
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        case .failure(let err):
                            self.error = err.localizedDescription
                        }
                    })
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(25)
                    .padding(.horizontal, 30)

                    if !error.isEmpty {
                        Text(error).foregroundColor(.red).font(.caption).padding(.top)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $forgotpassword) {
            VStack(spacing: 20) {
                Text("Reset Password")
                    .font(.title2.bold())
                
                TextField("Enter your email", text: $username)
                    .padding()
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                
                Button(action: {
                    resetPassword()
                }) {
                    Text("Send Reset Link")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }
            .padding()
            .presentationDetents([.medium])
        }
    }
        
    func resetPassword() {
        Auth.auth().sendPasswordReset(withEmail: username) { error in
            if let error = error {
                print("Unable to reset password: \(error.localizedDescription)")
            } else {
                print("Successfully sent password reset email!")
                forgotpassword = false
            }
        }
    }
    
    func googleOauth() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            print("No Firebase client ID found")
            return
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("No root view controller found")
            return
        }
        
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        let user = result.user
        guard let idToken = user.idToken?.tokenString else {
            print("ID token missing")
            return
        }
        
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
        let _ = try await Auth.auth().signIn(with: credential)
        loginManager.isLoggedIn = true
    }
        
    func logout() async throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }
        
    func authenticateUser() -> Bool {
        if (checkEmail(email: username) && checkPassword(password: password)) {
            return true
        } else {
            return false
        }
    }
    
    func checkEmail(email: String) -> Bool {
        var emailCharacters = CharacterSet()
        emailCharacters.insert(charactersIn: "@")
        emailCharacters.insert(charactersIn: "com")
        if email.rangeOfCharacter(from: emailCharacters) == nil {
            return false
        }
        return true
    }
    
    func checkPassword(password: String) -> Bool {
        if (password.count < 6) {
            return false
        }
        let nonAlphanumericCharacters = CharacterSet.alphanumerics.inverted
        if password.rangeOfCharacter(from: nonAlphanumericCharacters) == nil {
            return false
        }
        let digitsCharacters = CharacterSet.decimalDigits
        if password.rangeOfCharacter(from: digitsCharacters) == nil {
            return false
        }
        return true
    }
    
    func signUp(email: String, password: String) {
        Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
            if let error = error {
                print("Error signing up: \(error.localizedDescription)")
            } else {
                loginManager.isLoggedIn = true
                print("User signed up successfully")
            }
        }
    }
    
    func signIn(email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                print("Error signing in: \(error.localizedDescription)")
            } else {
                loginManager.isLoggedIn = true
                print("User signed in successfully")
            }
        }
    }

    func appleSignIn(authorization: ASAuthorization) async throws {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            print("Unable to fetch Apple ID token")
            return
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
        let _ = try await Auth.auth().signIn(with: credential)
        loginManager.isLoggedIn = true
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in charset[Int(byte) % charset.count] }
        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    LoginView(loginManager: LoginManager())
}
