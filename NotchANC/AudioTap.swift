// How loud what's playing is, in a few frequency bands, for the pill's visualizer. A Core Audio tap hears the
// Mac's whole output (macOS asks once for System Audio Recording); nothing is stored, and it runs only while
// the pill shows something playing.

import Accelerate
import CoreAudio
import Foundation

final class AudioTap: ObservableObject {
    static let bands = 5
    @Published private(set) var levels = [Float](repeating: 0, count: bands)   // 0…1, low to high

    var isRunning = false {
        didSet { if isRunning != oldValue { isRunning ? start() : stop() } }
    }

    private static let size = 1024   // samples per analysis, about 21 ms at 48 kHz
    private static let edges: [Float] = [40, 150, 400, 1000, 2500, 8000]   // band edges in Hz
    private static let swing: Float = 9   // dB off a band's running average that takes its bar to full or least height
    private let queue = DispatchQueue(label: "NotchANC.AudioTap")
    private let dft = try? vDSP.DiscreteFourierTransform(count: size, direction: .forward,
                                                         transformType: .complexComplex, ofType: Float.self)
    private let hann = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var sampleRate: Float = 48000
    // Touched only on `queue`.
    private var samples: [Float] = []
    private var averages = [Float](repeating: -120, count: bands)
    private var shown = [Float](repeating: 0, count: bands)

    private func start() {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { return stop() }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchANC visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device) == noErr else { return stop() }
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr, rate > 0 { sampleRate = Float(rate) }
        guard AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue, { [weak self] _, input, _, _, _ in
            self?.consume(input)
        }) == noErr, AudioDeviceStart(device, proc) == noErr else { return stop() }
    }

    private func stop() {
        if let proc {
            AudioDeviceStop(device, proc)
            AudioDeviceDestroyIOProcID(device, proc)
        }
        if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        proc = nil
        device = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
        queue.async { [weak self] in
            guard let self else { return }
            samples.removeAll()
            shown = [Float](repeating: 0, count: Self.bands)
            DispatchQueue.main.async { self.levels = [Float](repeating: 0, count: Self.bands) }
        }
    }

    // The tap delivers mono 32-bit float samples.
    private func consume(_ input: UnsafePointer<AudioBufferList>) {
        guard let buffer = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).first,
              let data = buffer.mData else { return }
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        samples.append(contentsOf: UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
        guard samples.count >= Self.size, let dft else { return }
        let frame = vDSP.multiply(Array(samples.suffix(Self.size)), hann)
        samples.removeAll(keepingCapacity: true)
        let (re, im) = dft.transform(real: frame, imaginary: [Float](repeating: 0, count: Self.size))
        let binWidth = sampleRate / Float(Self.size)
        for band in 0..<Self.bands {
            let low = max(1, Int(Self.edges[band] / binWidth))
            let high = min(Self.size / 2, max(low + 1, Int(Self.edges[band + 1] / binWidth)))
            var power: Float = 0
            for bin in low..<high { power += re[bin] * re[bin] + im[bin] * im[bin] }
            let db = 10 * log10(power / Float(high - low) + 1e-12)
            // Each bar rests at half height on its band's running average (about a second) and moves with what
            // stands out from it, so quiet and loud tracks both move and steady sound never pins the bars.
            // A jump far off the average (music starting after silence) resets it, or every bar would sit at full
            // height until the average caught up.
            averages[band] = abs(db - averages[band]) > 2 * Self.swing ? db : averages[band] * 0.95 + db * 0.05
            let level = db < -100 ? 0 : min(max(0.5 + (db - averages[band]) / Self.swing, 0.1), 1)
            shown[band] = max(level, shown[band] - 0.08)   // rises at once, falls smoothly
        }
        let out = shown
        DispatchQueue.main.async { [weak self] in self?.levels = out }
    }
}
