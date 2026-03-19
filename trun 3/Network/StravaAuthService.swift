//
//  StravaAuthService.swift
//  trun 3
//
//  Created by Sabath Rodriguez on 2/24/26.
//

import AuthenticationServices
import FirebaseFunctions
import Foundation

class StravaAuthService: NSObject, ObservableObject {
    static let shared = StravaAuthService()

    private let clientID = "205635"
    private let callbackScheme = "trun3strava"

    private let keychainAccessToken = "strava_access_token"
    private let keychainRefreshToken = "strava_refresh_token"
    private let keychainExpiresAt = "strava_token_expires_at"

    private lazy var functions = Functions.functions()

    @Published var isAuthenticated: Bool = false

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: TimeInterval = 0

    override init() {
        super.init()
        loadTokensFromKeychain()
    }

    // MARK: - OAuth Flow

    func authenticate() {
        let authURL = "https://www.strava.com/oauth/authorize"
        let redirectURI = "\(callbackScheme)://localhost"
        let scope = "activity:write,read"

        guard let url = URL(string: "\(authURL)?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scope)&approval_prompt=auto") else {
            return
        }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                print("Strava auth error: \(error.localizedDescription)")
                return
            }

            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                print("Strava auth: no code in callback")
                return
            }

            Task {
                await self.exchangeCodeForTokens(code: code)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        session.start()
    }

    private func exchangeCodeForTokens(code: String) async {
        do {
            let result = try await functions.httpsCallable("stravaTokenExchange").call(["code": code])

            guard let data = result.data as? [String: Any] else {
                throw StravaError.invalidResponse
            }

            try parseTokenData(data)
        } catch {
            print("Strava token exchange error: \(error)")
        }
    }

    func getValidAccessToken() async throws -> String {
        if Date().timeIntervalSince1970 >= expiresAt {
            try await refreshAccessToken()
        }

        guard let token = accessToken else {
            throw StravaError.notAuthenticated
        }
        return token
    }

    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw StravaError.notAuthenticated
        }

        let result = try await functions.httpsCallable("stravaTokenRefresh").call(["refresh_token": refreshToken])

        guard let data = result.data as? [String: Any] else {
            throw StravaError.invalidResponse
        }

        try parseTokenData(data)
    }

    // MARK: - Token Parsing & Storage

    private func parseTokenData(_ data: [String: Any]) throws {
        guard let accessToken = data["access_token"] as? String,
              let refreshToken = data["refresh_token"] as? String,
              let expiresAt = data["expires_at"] as? TimeInterval else {
            throw StravaError.invalidResponse
        }

        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt

        saveTokensToKeychain()

        DispatchQueue.main.async {
            self.isAuthenticated = true
        }
    }

    private func saveTokensToKeychain() {
        _ = KeychainHelper.saveString(key: keychainAccessToken, value: accessToken ?? "")
        _ = KeychainHelper.saveString(key: keychainRefreshToken, value: refreshToken ?? "")
        _ = KeychainHelper.saveString(key: keychainExpiresAt, value: String(expiresAt))
    }

    private func loadTokensFromKeychain() {
        accessToken = KeychainHelper.loadString(key: keychainAccessToken)
        refreshToken = KeychainHelper.loadString(key: keychainRefreshToken)

        if let expiresStr = KeychainHelper.loadString(key: keychainExpiresAt),
           let expires = Double(expiresStr) {
            expiresAt = expires
        }

        isAuthenticated = accessToken != nil && refreshToken != nil
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        expiresAt = 0

        KeychainHelper.delete(key: keychainAccessToken)
        KeychainHelper.delete(key: keychainRefreshToken)
        KeychainHelper.delete(key: keychainExpiresAt)

        DispatchQueue.main.async {
            self.isAuthenticated = false
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension StravaAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Errors

enum StravaError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Strava. Please connect your account."
        case .invalidResponse:
            return "Invalid response from Strava."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        }
    }
}
