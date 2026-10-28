import Foundation

/// The config written when `modes.json` does not exist: Writing, Building and Social, each
/// holding the candidate apps that are installed on this Mac.
public enum DefaultModes {
    static let chrome = WebApp.chromeBundleID
    static let claude = "com.anthropic.claudefordesktop"

    static let writingApps = ["md.obsidian", "notion.id", "com.apple.Notes", claude, chrome]
    static let buildingApps = ["com.github.wez.wezterm", "dev.zed.Zed", "com.todesktop.230313mzl4w4u92", chrome, claude]
    static let socialApps = ["com.tinyspeck.slackmacgap", "net.whatsapp.WhatsApp", "com.hnc.Discord"]

    static let focusExit = ExitPolicy(delaySeconds: 10, perPressSeconds: 3, to: ["social": 30])

    public static func make(isInstalled: (String) -> Bool) -> ModesConfig {
        let hasChrome = isInstalled(chrome)
        func web(_ name: String, _ url: String) -> [WebApp] {
            hasChrome ? [WebApp(name: name, url: URL(string: url)!)] : []
        }
        let modes = [
            Mode(id: "writing", name: "Writing", symbol: "pencil", color: "#F0892B", workspace: "W",
                 apps: writingApps.filter(isInstalled), webApps: web("Drive", "https://drive.google.com"),
                 focus: "Writing", exit: focusExit, allow: "Long-form writing, docs, notes, research reading"),
            Mode(id: "building", name: "Building", symbol: "hammer", color: "#2F7CF6", workspace: "B",
                 apps: buildingApps.filter(isInstalled), webApps: web("GitHub", "https://github.com"),
                 focus: "Building", exit: focusExit, allow: "Coding, terminals, editors, docs and issue trackers"),
            Mode(id: "social", name: "Social", symbol: "bubble.left.and.bubble.right", color: "#EB4D3D", workspace: "S",
                 apps: socialApps.filter(isInstalled), allow: "Chat, messages and social feeds"),
        ]
        return ModesConfig(initialMode: "writing", modes: modes)
    }
}
