import Foundation
import Combine
import MudCore

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var modeInActiveTab: Mode = .up
    @Published var lighting: Lighting
    @Published var theme: Theme
    @Published var viewToggles: Set<ViewToggle>
    @Published var upModeZoomLevel: Double
    @Published var downModeZoomLevel: Double
    @Published var sidebarVisible: Bool
    @Published var quitOnClose: Bool
    @Published var allowRemoteContent: Bool
    @Published var enabledExtensions: Set<String>
    @Published var doccAlertMode: DocCAlertMode
    var openSettingsAction: (() -> Void)?

    private static let lightingKey = "Mud-Lighting"
    private static let themeKey = "Mud-Theme"
    private static let upModeZoomKey = "Mud-UpModeZoomLevel"
    private static let downModeZoomKey = "Mud-DownModeZoomLevel"
    private static let sidebarVisibleKey = "Mud-SidebarVisible"
    private static let quitOnCloseKey = "Mud-QuitOnClose"
    private static let allowRemoteContentKey = "Mud-AllowRemoteContent"
    private static let enabledExtensionsKey = "Mud-EnabledExtensions"
    private static let doccAlertModeKey = "Mud-DoccAlertMode"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.lightingKey) ?? ""
        self.lighting = Lighting(rawValue: raw) ?? .auto
        let themeRaw = UserDefaults.standard.string(forKey: Self.themeKey) ?? ""
        self.theme = Theme(rawValue: themeRaw) ?? .earthy
        self.viewToggles = Set(ViewToggle.allCases.filter { $0.isEnabled })
        let defaults = UserDefaults.standard
        self.upModeZoomLevel = defaults.object(forKey: Self.upModeZoomKey) as? Double ?? 1.0
        self.downModeZoomLevel = defaults.object(forKey: Self.downModeZoomKey) as? Double ?? 1.0
        self.sidebarVisible = defaults.bool(forKey: Self.sidebarVisibleKey)
        self.quitOnClose = defaults.object(forKey: Self.quitOnCloseKey) as? Bool ?? true
        self.allowRemoteContent = defaults.object(forKey: Self.allowRemoteContentKey) as? Bool ?? true
        let allExtensions = Set(RenderExtension.registry.keys)
        if let saved = defaults.array(forKey: Self.enabledExtensionsKey) as? [String] {
            self.enabledExtensions = Set(saved).intersection(allExtensions)
        } else {
            self.enabledExtensions = allExtensions
        }
        let doccRaw = defaults.string(forKey: Self.doccAlertModeKey) ?? ""
        self.doccAlertMode = DocCAlertMode(rawValue: doccRaw) ?? .extended
    }

    func saveLighting(_ lighting: Lighting) {
        UserDefaults.standard.set(lighting.rawValue, forKey: Self.lightingKey)
    }

    func saveTheme(_ theme: Theme) {
        UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
    }

    func saveZoomLevels() {
        UserDefaults.standard.set(upModeZoomLevel, forKey: Self.upModeZoomKey)
        UserDefaults.standard.set(downModeZoomLevel, forKey: Self.downModeZoomKey)
    }

    func saveSidebarVisible() {
        UserDefaults.standard.set(sidebarVisible, forKey: Self.sidebarVisibleKey)
    }

    func saveQuitOnClose() {
        UserDefaults.standard.set(quitOnClose, forKey: Self.quitOnCloseKey)
    }

    func saveAllowRemoteContent() {
        UserDefaults.standard.set(allowRemoteContent, forKey: Self.allowRemoteContentKey)
    }

    func saveEnabledExtensions() {
        UserDefaults.standard.set(Array(enabledExtensions), forKey: Self.enabledExtensionsKey)
    }

    func saveDoccAlertMode() {
        UserDefaults.standard.set(doccAlertMode.rawValue, forKey: Self.doccAlertModeKey)
    }

    func toggle(_ option: ViewToggle) {
        if viewToggles.contains(option) {
            viewToggles.remove(option)
        } else {
            viewToggles.insert(option)
        }
        option.save(viewToggles.contains(option))
    }
}
