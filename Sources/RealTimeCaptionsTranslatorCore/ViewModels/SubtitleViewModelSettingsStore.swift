import Foundation

struct SubtitleViewModelPersistedSettings {
    var selectedDeviceID: String?
    var fontSize: Double?
    var selectedTranslationModel: TranslationModelOption?
    var selectedLatencyPreset: TranslationLatencyPreset?
    var keepTechWordsOriginal: Bool?
    var isAutoQAEnabled: Bool?
    var selectedQAEnglishLevel: QAEnglishLevel?
    var apiToken: String?
}

struct SubtitleViewModelSettingsStore {
    private let defaults: UserDefaults
    private let tokenStore: any APITokenStoring

    private enum Key: String {
        case selectedDeviceID = "settings.selectedDeviceID"
        case fontSize = "settings.fontSize"
        case selectedTranslationModel = "settings.selectedTranslationModel"
        case selectedLatencyPreset = "settings.selectedLatencyPreset"
        case keepTechWordsOriginal = "settings.keepTechWordsOriginal"
        case isAutoQAEnabled = "settings.isAutoQAEnabled"
        case selectedQAEnglishLevel = "settings.selectedQAEnglishLevel"
        case apiToken = "settings.apiToken"
    }

    init(defaults: UserDefaults, tokenStore: any APITokenStoring) {
        self.defaults = defaults
        self.tokenStore = tokenStore
    }

    func load() -> SubtitleViewModelPersistedSettings {
        var settings = SubtitleViewModelPersistedSettings()

        settings.selectedDeviceID = defaults.string(forKey: Key.selectedDeviceID.rawValue)

        if let storedModelRaw = defaults.string(forKey: Key.selectedTranslationModel.rawValue) {
            settings.selectedTranslationModel = TranslationModelOption(rawValue: storedModelRaw)
        }

        if let storedPresetRaw = defaults.string(forKey: Key.selectedLatencyPreset.rawValue) {
            settings.selectedLatencyPreset = TranslationLatencyPreset(rawValue: storedPresetRaw)
        }

        if defaults.object(forKey: Key.keepTechWordsOriginal.rawValue) != nil {
            settings.keepTechWordsOriginal = defaults.bool(forKey: Key.keepTechWordsOriginal.rawValue)
        }

        if defaults.object(forKey: Key.isAutoQAEnabled.rawValue) != nil {
            settings.isAutoQAEnabled = defaults.bool(forKey: Key.isAutoQAEnabled.rawValue)
        }

        if let storedLevelRaw = defaults.string(forKey: Key.selectedQAEnglishLevel.rawValue) {
            settings.selectedQAEnglishLevel = QAEnglishLevel(rawValue: storedLevelRaw)
        }

        if defaults.object(forKey: Key.fontSize.rawValue) != nil {
            let storedFontSize = defaults.double(forKey: Key.fontSize.rawValue)
            settings.fontSize = max(12, min(72, storedFontSize))
        }

        if let token = tokenStore.loadToken() {
            settings.apiToken = token
        } else if let legacy = defaults.string(forKey: Key.apiToken.rawValue),
                  legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            settings.apiToken = legacy
            tokenStore.saveToken(legacy)
            defaults.removeObject(forKey: Key.apiToken.rawValue)
        } else {
            settings.apiToken = ""
        }
        return settings
    }

    func setSelectedDeviceID(_ value: String) {
        defaults.set(value, forKey: Key.selectedDeviceID.rawValue)
    }

    func setFontSize(_ value: Double) {
        defaults.set(value, forKey: Key.fontSize.rawValue)
    }

    func setSelectedTranslationModel(_ value: TranslationModelOption) {
        defaults.set(value.rawValue, forKey: Key.selectedTranslationModel.rawValue)
    }

    func setSelectedLatencyPreset(_ value: TranslationLatencyPreset) {
        defaults.set(value.rawValue, forKey: Key.selectedLatencyPreset.rawValue)
    }

    func setKeepTechWordsOriginal(_ value: Bool) {
        defaults.set(value, forKey: Key.keepTechWordsOriginal.rawValue)
    }

    func setAutoQAEnabled(_ value: Bool) {
        defaults.set(value, forKey: Key.isAutoQAEnabled.rawValue)
    }

    func setSelectedQAEnglishLevel(_ value: QAEnglishLevel) {
        defaults.set(value.rawValue, forKey: Key.selectedQAEnglishLevel.rawValue)
    }

    func setAPIToken(_ value: String) {
        tokenStore.saveToken(value)
        defaults.removeObject(forKey: Key.apiToken.rawValue)
    }
}
