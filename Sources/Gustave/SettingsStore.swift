import Combine
import Foundation
import GustaveCore

@MainActor
final class SettingsStore: ObservableObject {
    private static let key = "settings"

    @Published var settings: Settings {
        didSet { UserDefaults.standard.set(settings.encoded(), forKey: Self.key) }
    }

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key) ?? Data()
        settings = Settings.decoded(from: data)
    }
}
