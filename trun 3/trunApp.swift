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

@main
struct trunApp: App {
    init() {
        FirebaseApp.configure()
        
//        let settings = Firestore.firestore().settings
//        settings.host = "localhost:8080" // Default port for Firestore emulator
//        settings.isPersistenceEnabled = false
//        settings.isSSLEnabled = false
//        Firestore.firestore().settings = settings
        
//        Auth.auth().useEmulator(withHost: "localhost", port: 9099)
//        Database.database().useEmulator(withHost: "localhost", port: 9000)
    }

    var body: some Scene {
        WindowGroup {
            var log: LoginManager = LoginManager()
            ContentView(loginManager: log).onOpenURL { url in
//            MainView().onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
