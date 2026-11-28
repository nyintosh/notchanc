// Files parked on the pill: dropped onto it, kept by path until removed, dragged back out to use.
// The files themselves stay where they are.

import Foundation

final class Shelf: ObservableObject {
    static let key = "shelf"

    @Published private(set) var files: [URL]
    private let defaults = UserDefaults.standard

    // A file deleted or moved since it was shelved is dropped.
    init() {
        files = (defaults.stringArray(forKey: Self.key) ?? []).filter(FileManager.default.fileExists).map(URL.init(fileURLWithPath:))
    }

    func add(_ new: [URL]) { set(Self.adding(new, to: files)) }

    func remove(_ file: URL) { set(files.filter { $0 != file }) }

    private func set(_ files: [URL]) {
        guard files != self.files else { return }
        self.files = files
        defaults.set(files.map(\.path), forKey: Self.key)
    }

    // In the order dropped, each file once.
    static func adding(_ new: [URL], to files: [URL]) -> [URL] {
        new.reduce(into: files) { if !$0.contains($1) { $0.append($1) } }
    }
}
