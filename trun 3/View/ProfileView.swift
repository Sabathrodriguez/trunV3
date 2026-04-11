//
//  ProfileView.swift
//  trun
//
//  Created by Claude on 2/24/26.
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    @ObservedObject var profileService: ProfileService
    @ObservedObject var loginManager: LoginManager
    @Binding var isPresented: Bool
    @Binding var showDBInspector: Bool

    @State private var selectedItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var newUsername = ""
    @State private var showUsernameAlert = false
    @State private var usernameAlertTitle = ""
    @State private var usernameAlertMessage = ""
    @State private var isSavingUsername = false
    @ObservedObject private var stravaAuth = StravaAuthService.shared
    
    @AppStorage("showMusicPlayer") private var showMusicPlayer: Bool = true
    @ObservedObject private var consentManager = AnalyticsConsentManager.shared

    private var userEmail: String {
        Auth.auth().currentUser?.email ?? "No email"
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header with back button
            HStack {
                Button(action: { isPresented = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.blue)
                }
                Spacer()
                Text("Profile")
                    .font(.headline)
                Spacer()
                // Invisible spacer to center the title
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .opacity(0)
            }
            .padding(.horizontal)
            
            ScrollView {
            // Profile Image
            ZStack {
                if let urlString = profileService.profileImageURL,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            placeholderImage
                        case .empty:
                            ProgressView()
                        @unknown default:
                            placeholderImage
                        }
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                } else {
                    placeholderImage
                }
                
                if profileService.isUploading {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 100, height: 100)
                    ProgressView()
                }
            }
            
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text("Change Photo")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
            .disabled(profileService.isUploading)
            
            // User Info
            VStack(spacing: 6) {
                if let username = profileService.username {
                    Text(username)
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(userEmail)
                    .font(.headline)
                    .foregroundColor(profileService.username != nil ? .secondary : .primary)
                Text("Member since \(memberSinceText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Set Username (shown only when user has no username)
            if profileService.username == nil {
                VStack(spacing: 10) {
                    Divider()
                    Text("Set a Username")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    HStack {
                        TextField("Username", text: $newUsername)
                            .padding(10)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        
                        Button(action: saveNewUsername) {
                            if isSavingUsername {
                                ProgressView()
                                    .frame(width: 60)
                            } else {
                                Text("Save")
                                    .fontWeight(.semibold)
                                    .frame(width: 60)
                            }
                        }
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .disabled(isSavingUsername)
                    }
                    Divider()
                }
                .padding(.horizontal)
            }
            
            // Strava Connection
            VStack(spacing: 10) {
                Divider()
                if stravaAuth.isAuthenticated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected to Strava")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button("Disconnect") {
                            stravaAuth.logout()
                        }
                        .font(.subheadline)
                        .foregroundColor(.red)
                    }
                } else {
                    Button(action: {
                        stravaAuth.authenticate()
                    }) {
                        HStack {
                            Image(systemName: "figure.run")
                            Text("Connect to Strava")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                Divider()
            }
            .padding(.horizontal)
            
            // Database Routes
//            Button(action: {
//                isPresented = false
//                showDBInspector = true
//            }) {
//                HStack {
//                    Image(systemName: "map")
//                    Text("See all TrunRun routes!")
//                        .fontWeight(.semibold)
//                }
//                .frame(maxWidth: .infinity)
//                .padding()
//                .background(Color.blue)
//                .foregroundColor(.white)
//                .cornerRadius(12)
//            }
//            .padding(.horizontal)
            
            Button(role: .destructive) {
                loginManager.logout()
                isPresented = false
            } label: {
                Text("Log Out")
                    .font(.headline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            Section(header: Text("Run Settings")) {
                Toggle(isOn: $showMusicPlayer) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundColor(.blue)
                        Text("Show Apple Music Player")
                    }
                }
            }
            .padding(.horizontal)

            Section(header: Text("Privacy")) {
                Toggle(isOn: $consentManager.consentGranted) {
                    HStack {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Analytics & Crash Reports")
                            Text("Help improve TrunRun by sharing usage data and crash reports")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
            Spacer()
        }
        .padding(.top, 10)
        .alert(usernameAlertTitle, isPresented: $showUsernameAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(usernameAlertMessage)
        }
        .onAppear {
            profileService.fetchProfileImageURL()
        }
        .onChange(of: selectedItem) { newItem in
            guard let newItem = newItem else { return }
            errorMessage = nil

            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    profileService.uploadProfileImage(uiImage) { result in
                        switch result {
                        case .success:
                            AnalyticsService.logProfilePhotoChanged()
                        case .failure(let error):
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private func saveNewUsername() {
        let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            usernameAlertTitle = "Invalid Username"
            usernameAlertMessage = "Username cannot be empty."
            showUsernameAlert = true
            return
        }
        if trimmed.count < 3 {
            usernameAlertTitle = "Invalid Username"
            usernameAlertMessage = "Username must be at least 3 characters."
            showUsernameAlert = true
            return
        }
        if trimmed.count > 20 {
            usernameAlertTitle = "Invalid Username"
            usernameAlertMessage = "Username must be 20 characters or fewer."
            showUsernameAlert = true
            return
        }

        isSavingUsername = true
        let db = Firestore.firestore()
        db.collection("users")
            .whereField("username", isEqualTo: trimmed)
            .limit(to: 1)
            .getDocuments { [self] snapshot, error in
                if let error = error {
                    DispatchQueue.main.async {
                        isSavingUsername = false
                        usernameAlertTitle = "Error"
                        usernameAlertMessage = error.localizedDescription
                        showUsernameAlert = true
                    }
                    return
                }
                let isTaken = !(snapshot?.documents.isEmpty ?? true)
                if isTaken {
                    DispatchQueue.main.async {
                        isSavingUsername = false
                        usernameAlertTitle = "Username Taken"
                        usernameAlertMessage = "The username \"\(trimmed)\" is already in use. Please choose a different one."
                        showUsernameAlert = true
                    }
                    return
                }
                profileService.saveUsername(trimmed) { result in
                    isSavingUsername = false
                    switch result {
                    case .success:
                        AnalyticsService.logUsernameSet()
                    case .failure(let error):
                        usernameAlertTitle = "Error"
                        usernameAlertMessage = error.localizedDescription
                        showUsernameAlert = true
                    }
                }
            }
    }

    private var placeholderImage: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 100)
            .foregroundColor(.gray)
    }

    private var memberSinceText: String {
        guard let creationDate = Auth.auth().currentUser?.metadata.creationDate else {
            return "unknown"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: creationDate)
    }
}
