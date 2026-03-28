import Foundation

extension BreakScheduler {
    func persist<T>(_ value: T, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func persistSelectedSetupPreset() {
        if let selectedSetupPreset {
            UserDefaults.standard.set(selectedSetupPreset.rawValue, forKey: Keys.selectedSetupPreset)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.selectedSetupPreset)
        }
    }
}
