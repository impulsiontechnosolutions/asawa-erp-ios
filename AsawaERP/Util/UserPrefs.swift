//
//  UserPrefs.swift
//  AsawaERP
//
//  Tiny UserDefaults-backed store. iOS equivalent of Android's UserPrefs.kt.
//  Email is not secret (it's the logged-in user's username), so UserDefaults
//  is fine. If you ever need to store an API token or password, switch this
//  file to use Keychain.
//

import Foundation

final class UserPrefs {

    static let shared = UserPrefs()

    private enum Keys {
        static let email = "asawa.user.email"
        static let lastLoginUser = "asawa.user.lastLoginUser"
        static let loginPingDone = "asawa.user.loginPingDone"
    }

    var email: String? {
        get { UserDefaults.standard.string(forKey: Keys.email) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.email) }
    }

    var lastLoginUser: String? {
        get { UserDefaults.standard.string(forKey: Keys.lastLoginUser) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastLoginUser) }
    }

    var loginPingDone: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.loginPingDone) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.loginPingDone) }
    }
}
