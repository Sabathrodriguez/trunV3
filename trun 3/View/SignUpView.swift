//
//  SignUpView.swift
//  trun
//
//  Created by Claude on 3/27/26.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignUpView: View {
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String = ""
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isCheckingUsername = false

    @ObservedObject var loginManager: LoginManager
    var showSignIn: () -> Void

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                Spacer()

                Text("trun")
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 10)
                    .padding(.bottom, 10)

                Text("Create Account")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))

                VStack(spacing: 15) {
                    TextField("Email", text: $email)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .foregroundColor(.white)
                        .accentColor(.white)

                    TextField("Username", text: $username)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .foregroundColor(.white)
                        .accentColor(.white)

                    SecureField("Password", text: $password)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .accentColor(.white)

                    Button(action: {
                        validateAndSignUp()
                    }) {
                        if isCheckingUsername {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.5))
                                .cornerRadius(12)
                        } else {
                            Text("Sign Up")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(isCheckingUsername)

                    Text("Password must contain 1 special character and 1 number.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 30)

                Button(action: showSignIn) {
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundColor(.white.opacity(0.7))
                        Text("Sign In")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
                .padding(.top, 10)

                Spacer()
                Spacer()
            }
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Validation & Sign Up

    private func validateAndSignUp() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        // Username validation
        if trimmedUsername.isEmpty {
            showValidationAlert(title: "Invalid Username", message: "Username cannot be empty.")
            return
        }
        if trimmedUsername.count < 3 {
            showValidationAlert(title: "Invalid Username", message: "Username must be at least 3 characters.")
            return
        }
        if trimmedUsername.count > 20 {
            showValidationAlert(title: "Invalid Username", message: "Username must be 20 characters or fewer.")
            return
        }

        // Email validation
        if !checkEmail(email: email) {
            showValidationAlert(title: "Invalid Email", message: "Please enter a valid email address.")
            return
        }

        // Password validation
        if password.count < 6 {
            showValidationAlert(title: "Invalid Password", message: "Password must be at least 6 characters long.")
            return
        }
        let nonAlphanumeric = CharacterSet.alphanumerics.inverted
        if password.rangeOfCharacter(from: nonAlphanumeric) == nil {
            showValidationAlert(title: "Invalid Password", message: "Password must contain at least 1 special character.")
            return
        }
        let digits = CharacterSet.decimalDigits
        if password.rangeOfCharacter(from: digits) == nil {
            showValidationAlert(title: "Invalid Password", message: "Password must contain at least 1 number.")
            return
        }

        // Check username uniqueness and email availability, then sign up
        isCheckingUsername = true
        checkUsernameAvailability(trimmedUsername) { isUsernameAvailable in
            DispatchQueue.main.async {
                guard let isUsernameAvailable else {
                    isCheckingUsername = false
                    showValidationAlert(title: "Network Error", message: "Could not verify username availability. Please check your connection and try again.")
                    return
                }
                if !isUsernameAvailable {
                    isCheckingUsername = false
                    showValidationAlert(title: "Username Taken", message: "The username \"\(trimmedUsername)\" is already in use. Please choose a different one.")
                    return
                }
                checkEmailAvailability(email) { isEmailAvailable in
                    DispatchQueue.main.async {
                        isCheckingUsername = false
                        if isEmailAvailable {
                            signUp(username: trimmedUsername)
                        } else {
                            showValidationAlert(title: "Email Already in Use", message: "An account with this email already exists. Please sign in or use a different email.")
                        }
                    }
                }
            }
        }
    }

    private func showValidationAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func checkUsernameAvailability(_ username: String, completion: @escaping (Bool?) -> Void) {
        let db = Firestore.firestore()
        db.collection("usernames").document(username.lowercased()).getDocument { snapshot, error in
            if let error = error {
                AppLogger.auth.error("Error checking username availability: \(error.localizedDescription)")
                completion(nil)
                return
            }
            let isTaken = snapshot?.exists ?? false
            completion(!isTaken)
        }
    }

    private func checkEmailAvailability(_ email: String, completion: @escaping (Bool) -> Void) {
        Auth.auth().fetchSignInMethods(forEmail: email) { methods, error in
            if let error = error {
                AppLogger.auth.error("Error checking email availability: \(error.localizedDescription)")
                completion(false)
                return
            }
            // If methods is nil or empty, no account exists with this email
            let isAvailable = (methods ?? []).isEmpty
            completion(isAvailable)
        }
    }

    private func checkEmail(email: String) -> Bool {
        var emailCharacters = CharacterSet()
        emailCharacters.insert(charactersIn: "@")
        emailCharacters.insert(charactersIn: "com")
        return email.rangeOfCharacter(from: emailCharacters) != nil
    }

    private func signUp(username: String) {
        Auth.auth().createUser(withEmail: email, password: password) { authResult, authError in
            if let authError = authError {
                showValidationAlert(title: "Sign Up Failed", message: authError.localizedDescription)
                return
            }

            guard let user = authResult?.user else { return }

            // Set Firebase Auth displayName
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = username
            changeRequest.commitChanges { _ in }

            // Save username to Firestore
            let db = Firestore.firestore()
            let batch = db.batch()

            let userRef = db.collection("users").document(user.uid)
            batch.setData([
                "username": username,
                "email": email,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: userRef, merge: true)

            // Reserve the username so availability checks stay fast and unauthenticated
            let usernameRef = db.collection("usernames").document(username.lowercased())
            batch.setData(["uid": user.uid], forDocument: usernameRef)

            batch.commit { firestoreError in
                if let firestoreError = firestoreError {
                    AppLogger.auth.error("Error saving user data to Firestore: \(firestoreError.localizedDescription)")
                } else {
                    AnalyticsService.logSignUp(method: "email")
                }
            }
        }
    }
}

#Preview {
    SignUpView(loginManager: LoginManager(), showSignIn: {})
}
