//
//  trunApp.swift
//  trun
//
//  Created by Sabath  Rodriguez on 11/16/24.
//

import SwiftUI
import SwiftData
import Firebase
import GoogleSignIn
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore
import FirebaseAppCheck
import FirebaseCrashlytics

class TrunAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}

@main
struct trunApp: App {
    init() {
        let providerFactory = TrunAppCheckProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        FirebaseApp.configure()
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

        // Debug: check if App Check can get a token
        AppCheck.appCheck().token(forcingRefresh: true) { token, error in
            if let error = error {
                AppLogger.auth.error("App Check token error: \(error)")
            } else if let token = token {
                AppLogger.auth.debug("App Check token OK: \(token.token.prefix(20))...")
            }
        }
        
        let settings = Firestore.firestore().settings
//        settings.host = "localhost/:8080" // Default port for Firestore emulator
//        settings.isPersistenceEnabled = false
//        settings.isSSLEnabled = false
//        Firestore.firestore().settings = settings
        
//        Auth.auth().useEmulator(withHost: "localhost", port: 9099)
//        Database.database().useEmulator(withHost: "localhost", port: 9000)
    }

    var body: some Scene {
        WindowGroup {
            var log: LoginManager = LoginManager()
//            ContentView(loginManager: log).onOpenURL { url in
            MainView().onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
        .modelContainer(for: Run.self)
    }
}
