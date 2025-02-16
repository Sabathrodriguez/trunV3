//
//  Main.swift
//  trun
//
//  Created by Sabath  Rodriguez on 1/20/25.
//

import SwiftUI

class LoginManager : ObservableObject {
    @Published var isLoggedIn = false
    
    func login() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                self.isLoggedIn = true
            }
        }
    }
}

struct MainView : View {
    @StateObject public var loginManager = LoginManager()
    
    var body: some View {
        if loginManager.isLoggedIn {
            ContentView(loginManager: loginManager)
        } else {
            LoginView(loginManager: loginManager)
        }
    }
}
