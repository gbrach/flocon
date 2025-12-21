import AppKit

/// One request to the GitHub releases API, at launch (silent unless an update exists) and from "Check for Updates…".
/// Releases are tagged by version (e.g. "v1.1.0"); GitHub's "latest" endpoint returns the newest non-prerelease.
enum UpdateChecker {
    static let releasePage = URL(string: "https://github.com/gbrach/flocon/releases/latest")!
    /// FLOCON_UPDATE_URL (e.g. a file:// URL) replaces the GitHub endpoint, for testing a release before publishing it.
    private static var api: URL {
        ProcessInfo.processInfo.environment["FLOCON_UPDATE_URL"].flatMap(URL.init(string:))
            ?? URL(string: "https://api.github.com/repos/gbrach/flocon/releases/latest")!
    }

    /// First dotted number in the text, e.g. "Flocon v1.2.3" -> [1, 2, 3].
    static func version(in text: String) -> [Int]? {
        guard let range = text.range(of: #"\d+(\.\d+)*"#, options: .regularExpression) else { return nil }
        return text[range].split(separator: ".").compactMap { Int($0) }
    }

    static func isNewer(_ remote: [Int], than local: [Int]) -> Bool {
        for index in 0..<max(remote.count, local.count) {
            let r = index < remote.count ? remote[index] : 0
            let l = index < local.count ? local[index] : 0
            if r != l { return r > l }
        }
        return false
    }

    static func run(silent: Bool = false) {
        var request = URLRequest(url: api, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let name = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["tag_name"] as? String
            DispatchQueue.main.async { MainActor.assumeIsolated { present(releaseName: name, silent: silent) } }
        }.resume()
    }

    @MainActor private static func present(releaseName: String?, silent: Bool) {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let alert = NSAlert()
        if let releaseName, let remote = version(in: releaseName), let local = version(in: current) {
            if isNewer(remote, than: local) {
                alert.messageText = "Flocon \(remote.map(String.init).joined(separator: ".")) is available"
                alert.informativeText = "You have \(current). Download the new version and drag it to Applications."
                NSApp.activate(ignoringOtherApps: true)
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releasePage) }
                return
            }
            if silent { return }
            alert.messageText = "Flocon is up to date"
            alert.informativeText = "You have the latest version (\(current))."
        } else {
            if silent { return }
            alert.messageText = "Couldn’t check for updates"
            alert.informativeText = "Check your connection and try again."
        }
        alert.runModal()
    }
}
