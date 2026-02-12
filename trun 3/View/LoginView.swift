//
//  LoginScreen.swift
//  trun
//
//  Created by Sabath  Rodriguez on 1/8/25.
//

import SwiftUI
import FirebaseCore
import Firebase
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift
import Foundation

struct LoginView: View {
    @State private var error: String = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isAuthenticated = false
    @State private var forgotpassword = false
    
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var loginManager: LoginManager
    
    var body: some View {
        VStack {
            VStack {
                // Username TextField
                TextField("Username", text: $username)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(5.0)
                    .padding(.bottom, 20)
                
                // Password SecureField
                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(5.0)
                    .padding(.bottom, 20)
                
                VStack {
                    // Login Button
                    Button(action: {
                        if (authenticateUser()) {
                            signIn(email: username, password: password)
                        }
                    }) {
                        Text("Sign In")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 220, height: 50)
                            .background(Color.blue)
                            .cornerRadius(15.0)
                    }
                                        
                    VStack {
                        //Signup Button
                        Button(action: {
                            // Here, you would typically validate credentials
                            // For this example, we'll just set `isLoggedIn` to true
                            
                            if (authenticateUser()) {
                                signUp(email: username, password: password)
                            }
                        }) {
                            Text("Sign Up")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(width: 220, height: 50)
                                .background(Color.blue)
                                .cornerRadius(15.0)
                        }
                        Text("Password must contain 1 special character and 1 number.")
                            .font(.caption2)
                    }
                    
                    Button(action: {
                        forgotpassword = true
                    }) {
                        Text("Forgot Password?")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    // sign in with google button
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
                                Image(systemName: "person.badge.key.fill")
                                Text("Sign in with Google")
                            }
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        if !error.isEmpty {
                            Text(error).foregroundColor(.red).font(.caption)
                        }
                    }
                }
            }
            .padding()
            .sheet(isPresented: $forgotpassword) {
                VStack {
                    TextField("Email:", text: $username)
                        .padding()
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .background(colorScheme == .dark ? Color(.systemGray4) : Color(.systemGray6))
                        .cornerRadius(20)
                    Button(action: {
                        resetPassword()
                    }) {
                        Text("Send Reset Link")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(width: 250, height: 50)
                            .background(Color.blue)
                            .cornerRadius(15.0)
                    }
                    .padding()
                }
                    .presentationDetents([.medium])
            }
            
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
        var authResult = try await Auth.auth().signIn(with: credential)
        // Handle authResult (e.g., update UI to show logged-in user)
        loginManager.isLoggedIn = true
        
    }
        
    func logout() async throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }
        
    func authenticateUser() -> Bool {
        // Here you would typically check against a backend service
        // For demonstration, we'll just check if both fields are not empty
        if (checkEmail(email: username) && checkPassword(password: password)) {
            return true
//            signIn(email: username, password: password)
        } else {
            // Handle error, e.g., show an alert
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
        // check for 1 special character
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
}

#Preview {
    LoginView(loginManager: LoginManager())
}
