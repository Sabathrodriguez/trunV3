//
//  ProfileService.swift
//  trun
//
//  Created by Claude on 2/24/26.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

class ProfileService: ObservableObject {
    @Published var profileImageURL: String?
    @Published var username: String?
    @Published var isUploading = false

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    /// Upload a profile image to Firebase Storage and save the download URL to Firestore.
    func uploadProfileImage(_ image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(ProfileError.notAuthenticated))
            return
        }

        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            completion(.failure(ProfileError.compressionFailed))
            return
        }

        isUploading = true

        let ref = storage.reference().child("profileImages/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        ref.putData(imageData, metadata: metadata) { [weak self] _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.isUploading = false
                    completion(.failure(error))
                }
                return
            }

            ref.downloadURL { [weak self] url, error in
                guard let self = self else { return }

                if let error = error {
                    DispatchQueue.main.async {
                        self.isUploading = false
                        completion(.failure(error))
                    }
                    return
                }

                guard let downloadURL = url?.absoluteString else {
                    DispatchQueue.main.async {
                        self.isUploading = false
                        completion(.failure(ProfileError.noDownloadURL))
                    }
                    return
                }

                // Save the download URL to Firestore
                self.db.collection("users").document(uid).setData([
                    "photoURL": downloadURL,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true) { error in
                    DispatchQueue.main.async {
                        self.isUploading = false
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            self.profileImageURL = downloadURL
                            completion(.success(downloadURL))
                        }
                    }
                }
            }
        }
    }

    /// Fetch the current user's profile data (image URL and username) from Firestore.
    func fetchProfileImageURL() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("Error fetching profile data: \(error)")
                return
            }
            let data = snapshot?.data()
            let url = data?["photoURL"] as? String
            let name = data?["username"] as? String
            DispatchQueue.main.async {
                self?.profileImageURL = url
                self?.username = name
            }
        }
    }

    /// Fetch a specific user's profile image URL from Firestore.
    func fetchProfileImageURL(for uid: String, completion: @escaping (String?) -> Void) {
        db.collection("users").document(uid).getDocument { snapshot, error in
            if let error = error {
                print("Error fetching profile image URL: \(error)")
                completion(nil)
                return
            }
            let url = snapshot?.data()?["photoURL"] as? String
            completion(url)
        }
    }

    enum ProfileError: LocalizedError {
        case notAuthenticated
        case compressionFailed
        case noDownloadURL

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be signed in to update your profile."
            case .compressionFailed:
                return "Failed to compress the image."
            case .noDownloadURL:
                return "Failed to get the image download URL."
            }
        }
    }
}
