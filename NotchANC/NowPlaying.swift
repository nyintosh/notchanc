// What's playing, from any app. MediaRemote refuses non-Apple processes since macOS 15.4,
// but Apple's own osascript may load it, so a small JXA loop prints a JSON line on every change.
// ponytail: private MRNowPlayingRequest polled once a second; switch if Apple ships a public API.

import Foundation

struct Track: Decodable, Equatable {
    let playing: Bool
    let title: String
    let artist: String

    var text: String { artist.isEmpty ? title : "\(title) — \(artist)" }

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

    private let script = """
    ObjC.import("Foundation");
    $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/").load;
    const R = $.NSClassFromString("MRNowPlayingRequest");
    const out = $.NSFileHandle.fileHandleWithStandardOutput;
    const str = (info, k) => { const v = info.objectForKey(k); return v.isNil() ? "" : ObjC.unwrap(v); };
    let last = null;
    while (true) {
      const item = R.localNowPlayingItem;
      const info = item.isNil() ? null : item.nowPlayingInfo;
      const s = !info || info.isNil() ? "{}" : JSON.stringify({
        playing: R.localIsPlaying,
        title: str(info, "kMRMediaRemoteNowPlayingInfoTitle"),
        artist: str(info, "kMRMediaRemoteNowPlayingInfoArtist")
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self?.buffer.removeAll()
                self?.start()
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
            if !line.isEmpty { onChange?(Track.parse(line)) }
        }
    }
}
