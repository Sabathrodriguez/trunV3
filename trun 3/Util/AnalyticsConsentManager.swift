import Foundation
import FirebaseAnalytics
import FirebaseCrashlytics

/// Manages user consent for Firebase Analytics and Crashlytics data collection.
/// Consent state is persisted in UserDefaults and applied on each app launch.
final class AnalyticsConsentManager: ObservableObject {
    static let shared = AnalyticsConsentManager()

    private let consentKey = "analyticsConsentGranted"
    private let hasPromptedKey = "analyticsConsentPrompted"

    @Published var consentGranted: Bool {
        didSet {
            UserDefaults.standard.set(consentGranted, forKey: consentKey)
            applyConsent()
        }
    }

    var hasPromptedUser: Bool {
        get { UserDefaults.standard.bool(forKey: hasPromptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasPromptedKey) }
    }

    private init() {
        self.consentGranted = UserDefaults.standard.bool(forKey: consentKey)
    }

    /// Call once after FirebaseApp.configure() to apply the persisted consent state.
    func configure() {
        applyConsent()
    }

    private func applyConsent() {
        Analytics.setAnalyticsCollectionEnabled(consentGranted)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(consentGranted)
    }
}
