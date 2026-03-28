//
//  ProfileView.swift
//  trun
//
//  Created by Claude on 2/24/26.
//

import SwiftUI
import PhotosUI
import FirebaseAuth

struct ProfileView: View {
    @ObservedObject var profileService: ProfileService
    @ObservedObject var loginManager: LoginManager
    @Binding var isPresented: Bool
    @Binding var showDBInspector: Bool

    @State private var selectedItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @ObservedObject private var stravaAuth = StravaAuthService.shared
    
    @AppStorage("showMusicPlayer") private var showMusicPlayer: Bool = true

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
            Button(action: {
                isPresented = false
                showDBInspector = true
            }) {
                HStack {
                    Image(systemName: "map")
                    Text("See all TrunRun routes!")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)

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

            Spacer()
        }
        .padding(.top, 10)
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
                        if case .failure(let error) = result {
                            errorMessage = error.localizedDescription
                        }
                    }
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
