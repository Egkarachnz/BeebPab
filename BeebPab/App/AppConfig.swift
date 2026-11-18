import Foundation

enum AppConfig {
    /// Raw URL of `presets/presets.json` in your GitHub repo.
    static let presetsURLString = "https://raw.githubusercontent.com/Egkarachnz/BeebPab/main/presets/presets.json"

    static var presetsURL: URL? {
        guard !presetsURLString.contains("YOUR_GITHUB_USER") else { return nil }
        return URL(string: presetsURLString)
    }
}
