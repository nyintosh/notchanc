// Whether sound is going to headphones: any Bluetooth output (AirPods, Beats, other headsets)
// or the headphone jack. Watches the default output device and, for the jack, its data source.

import CoreAudio

final class AudioOutput {
    var onChange: (() -> Void)?
    private(set) var toHeadphones = false
    private var watched: Set<AudioObjectID> = []

    func start() {
        watch(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
        update()
    }

    private func update() {
        let device = Self.value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal) ?? 0
        // Plugging into the jack changes the device's data source, not the default device.
        // ponytail: listeners on devices no longer in use stay registered; they only re-run this check.
        if watched.insert(device).inserted {
            watch(device, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput)
        }
        let transport = Self.value(device, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal)
        let source = Self.value(device, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput)
        let now = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
            || source == 0x6864_706E   // 'hdpn', the headphone jack
        guard now != toHeadphones else { return }
        toHeadphones = now
        onChange?()
    }

    private func watch(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(id, &address, .main) { [weak self] _, _ in self?.update() }
    }

    private static func value(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &v) == noErr ? v : nil
    }
}
