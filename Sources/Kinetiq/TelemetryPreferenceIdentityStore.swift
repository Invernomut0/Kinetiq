// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Invernomut0Telemetry

/// A pseudonymous analytics UUID is not a credential. Store it in app-local preferences,
/// never accessing or migrating an older Keychain item that could request authorization.
actor TelemetryPreferenceIdentityStore: InstallationIdentityStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, productID: String) {
        self.defaults = defaults
        key = Self.preferenceKey(productID: productID)
    }

    static func preferenceKey(productID: String) -> String {
        "\(productID).telemetry.installationID"
    }

    func load() throws -> UUID? {
        guard let stored = defaults.object(forKey: key) else { return nil }
        guard let text = stored as? String, let identity = UUID(uuidString: text) else {
            throw InstallationIdentityError.invalidStoredIdentity
        }
        return identity
    }

    func save(_ identity: UUID) {
        defaults.set(identity.uuidString, forKey: key)
    }

    func delete() {
        defaults.removeObject(forKey: key)
    }
}