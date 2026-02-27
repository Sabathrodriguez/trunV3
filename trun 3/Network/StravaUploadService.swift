//
//  StravaUploadService.swift
//  trun 3
//
//  Created by Sabath Rodriguez on 2/24/26.
//

import Foundation

class StravaUploadService: ObservableObject {

    enum UploadStatus: Equatable {
        case idle
        case uploading
        case processing
        case success(activityID: String)
        case error(String)
    }

    @Published var uploadStatus: UploadStatus = .idle

    /// Uploads a TCX string to Strava and polls until processing completes.
    /// Returns the Strava activity ID on success.
    func uploadRun(tcxString: String, name: String) async throws -> String {
        await MainActor.run { uploadStatus = .uploading }

        let token = try await StravaAuthService.shared.getValidAccessToken()

        let url = URL(string: "https://www.strava.com/api/v3/uploads")!
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // data_type field
        body.appendMultipart(boundary: boundary, name: "data_type", value: "tcx")

        // activity_type field
        body.appendMultipart(boundary: boundary, name: "activity_type", value: "run")

        // name field
        body.appendMultipart(boundary: boundary, name: "name", value: name)

        // TCX file
        if let fileData = tcxString.data(using: .utf8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"run.tcx\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/vnd.garmin.tcx+xml\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }

        guard httpResponse.statusCode == 201 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw StravaError.uploadFailed("HTTP \(httpResponse.statusCode): \(message)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uploadID = json["id"] as? Int else {
            throw StravaError.invalidResponse
        }

        // Poll for processing completion
        await MainActor.run { uploadStatus = .processing }
        let activityID = try await pollUploadStatus(uploadID: uploadID, token: token)

        await MainActor.run { uploadStatus = .success(activityID: activityID) }
        return activityID
    }

    private func pollUploadStatus(uploadID: Int, token: String) async throws -> String {
        let url = URL(string: "https://www.strava.com/api/v3/uploads/\(uploadID)")!

        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let errorStr = json["error"] as? String, !errorStr.isEmpty {
                throw StravaError.uploadFailed(errorStr)
            }

            if let activityID = json["activity_id"] as? Int, activityID != 0 {
                return String(activityID)
            }

            // Still processing, continue polling
        }

        throw StravaError.uploadFailed("Upload processing timed out. Check Strava later.")
    }

    func reset() {
        uploadStatus = .idle
    }
}

// MARK: - Multipart Helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
