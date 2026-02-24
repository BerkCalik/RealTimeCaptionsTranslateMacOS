import Foundation

struct SubtitleViewModelAudioSetupResolution {
    let audioSetupState: AudioSetupState
    let blackHoleCandidates: [AudioInputDevice]
    let setupSteps: [SetupGuideAction]
}

enum SubtitleViewModelAudioSetupStateResolver {
    static func resolve(devices: [AudioInputDevice], selectedDeviceID: String) -> SubtitleViewModelAudioSetupResolution {
        let blackHoleCandidates = AudioSetupDetector.blackHoleCandidates(in: devices)
        let selectedDevice = devices.first(where: { $0.id == selectedDeviceID })
        let isSelectedBlackHole = selectedDevice.map { AudioSetupDetector.isBlackHoleName($0.name) } ?? false

        let state: AudioSetupState
        if blackHoleCandidates.isEmpty {
            state = .blackHoleMissing
        } else if isSelectedBlackHole {
            state = .blackHoleSelected
        } else {
            state = .blackHoleAvailableNotSelected
        }

        let hasBlackHole = blackHoleCandidates.isEmpty == false
        let hasAnyDevice = devices.isEmpty == false
        let setupSteps = [
            SetupGuideAction(
                id: "install",
                title: "Install BlackHole",
                description: "Download and run the official installer.",
                isCompleted: hasBlackHole
            ),
            SetupGuideAction(
                id: "route",
                title: "Route System Audio",
                description: "Set BlackHole as your input route for system audio.",
                isCompleted: isSelectedBlackHole
            ),
            SetupGuideAction(
                id: "refresh",
                title: "Refresh Devices",
                description: "Refresh input devices after install or route changes.",
                isCompleted: hasAnyDevice
            ),
            SetupGuideAction(
                id: "select",
                title: "Select BlackHole",
                description: "Choose a BlackHole device from Input Device.",
                isCompleted: isSelectedBlackHole
            )
        ]

        return SubtitleViewModelAudioSetupResolution(
            audioSetupState: state,
            blackHoleCandidates: blackHoleCandidates,
            setupSteps: setupSteps
        )
    }
}
