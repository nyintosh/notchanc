// What's playing, from any app. MediaRemote refuses non-Apple processes since macOS 15.4,
// but Apple's own osascript may load it, so a small JXA loop prints a JSON line on every change.
// ponytail: private MRNowPlayingRequest polled once a second; switch if Apple ships a public API.

import Foundation

struct Track: Decodable, Equatable {
    var playing: Bool
    let title: String
    let artist: String
    var bundle: String?      // the player app, e.g. com.apple.Music
    var elapsed: Double?     // seconds into the track when `timestamp` was taken
    var duration: Double?
    var timestamp: Double?   // seconds since 1970

    var text: String { artist.isEmpty ? title : "\(title) — \(artist)" }

    // Players report the position only when it jumps (play, pause, seek); in between it runs with the clock.
    func position(at now: Date) -> Double? {
        guard let elapsed, let timestamp else { return nil }
        return playing ? elapsed + now.timeIntervalSince1970 - timestamp : elapsed
    }

    // What play/pause will report, shown the moment it's pressed: the position stops or runs on from now.
    func toggled(at now: Date) -> Track {
        var t = self
        t.playing.toggle()
        t.elapsed = position(at: now)
        t.timestamp = t.elapsed == nil ? nil : now.timeIntervalSince1970
        return t
    }

    // nil for "{}" (nothing loaded) or an item without a title.
    static func parse(_ line: String) -> Track? {
        guard let t = try? JSONDecoder().decode(Track.self, from: Data(line.utf8)), !t.title.isEmpty else { return nil }
        return t
    }
}

final class NowPlaying {
    var onChange: ((Track?) -> Void)?
    private var proc: Process?
    private var buffer = Data()
    private var retry: TimeInterval = 5   // doubles while osascript keeps failing (e.g. an older macOS), up to 5 minutes

    private let script = """
    ObjC.import("Foundation");
    $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/").load;
    const R = $.NSClassFromString("MRNowPlayingRequest");
    const out = $.NSFileHandle.fileHandleWithStandardOutput;
    const str = (info, k) => { const v = info.objectForKey(k); return v.isNil() ? "" : ObjC.unwrap(v); };
    const num = (info, k) => { const v = info.objectForKey(k); return v.isNil() ? null : ObjC.unwrap(v); };
    let last = null;
    while (true) {
      const item = R.localNowPlayingItem;
      const info = item.isNil() ? null : item.nowPlayingInfo;
      const client = R.localNowPlayingPlayerPath.isNil() ? null : R.localNowPlayingPlayerPath.client;
      const time = !info || info.isNil() ? null : info.objectForKey("kMRMediaRemoteNowPlayingInfoTimestamp");
      const s = !info || info.isNil() ? "{}" : JSON.stringify({
        playing: R.localIsPlaying,
        title: str(info, "kMRMediaRemoteNowPlayingInfoTitle"),
        artist: str(info, "kMRMediaRemoteNowPlayingInfoArtist"),
        bundle: !client || client.isNil() || client.bundleIdentifier.isNil() ? null : ObjC.unwrap(client.bundleIdentifier),
        elapsed: num(info, "kMRMediaRemoteNowPlayingInfoElapsedTime"),
        duration: num(info, "kMRMediaRemoteNowPlayingInfoDuration"),
        timestamp: !time || time.isNil() ? null : time.timeIntervalSince1970
      });
      // An empty line when nothing changed: a heartbeat whose failed write ends this
      // process within a second once NotchANC quits or crashes.
      out.writeData($((s === last ? "" : s) + "\\n").dataUsingEncoding($.NSUTF8StringEncoding));
      last = s;
      delay(1);
    }
    """

    // Runs for the app's lifetime and restarts itself if osascript ever exits.
    func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-l", "JavaScript", "-e", script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.consume(d) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + self.retry) {
                    self.buffer.removeAll()
                    self.start()
                }
                self.retry = min(self.retry * 2, 300)
            }
        }
        guard (try? p.run()) != nil else { return }
        proc = p
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...nl)
            retry = 5   // it's working
            if !line.isEmpty { onChange?(Track.parse(line)) }
        }
    }

    // One short osascript per press; the loop above reports the new state within a second. osascript has to stay
    // a moment after sending: exiting at once drops the command before MediaRemote delivers it.
    func send(_ command: MediaCommand) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-l", "JavaScript", "-e", """
        ObjC.import("Foundation");
        $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/").load;
        ObjC.bindFunction("MRMediaRemoteSendCommand", ["bool", ["int", "id"]]);
        $.MRMediaRemoteSendCommand(\(command.rawValue), $());
        delay(0.5);
        """]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

// MediaRemote's command numbers.
enum MediaCommand: Int {
    case togglePlayPause = 2, nextTrack = 4, previousTrack = 5
}
