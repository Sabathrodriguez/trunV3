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

    @State private var selectedItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @ObservedObject private var stravaAuth = StravaAuthService.shared

    private var userEmail: String {
        Auth.auth().currentUser?.email ?? "No email"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
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
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                    } else {
                        placeholderImage
                    }

                    if profileService.isUploading {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 120, height: 120)
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
                VStack(spacing: 8) {
                    Text(userEmail)
                        .font(.headline)
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

                Spacer()

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
            }
            .padding(.top, 40)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
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
                            if case .failure(let error) = result {
                                errorMessage = error.localizedDescription
                            }
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
            .frame(width: 120, height: 120)
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
