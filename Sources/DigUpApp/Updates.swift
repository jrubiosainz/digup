import AppKit
import Sparkle

/// In-app updates, with Sparkle. Once a day DigUp reads its appcast (`SUFeedURL` in Info.plist); a newer version is
/// downloaded, checked against the EdDSA key in Info.plist (`SUPublicEDKey`) and Apple's signature, put in place of this
/// copy and reopened, after one click. Finder can't replace a running app, and DigUp runs most of the time.
///
/// DigUp lives in the menu bar, so an update the daily check finds doesn't pop up over whatever you're doing (Sparkle's
/// "gentle reminders"): it waits in the menu ("Update to DigUp 0.6.1…"), as a dot on the menubar mark, and in the
/// window's status bar, until you open it. Checks you ask for show Sparkle's window at once.
///
/// Biblo has no update channel of its own yet: without `SUFeedURL` in Info.plist none of this runs, and no menu offers
/// a check (`hasFeed`).
final class Updates: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private let model: AppModel
    private var controller: SPUStandardUpdaterController!
    /// Sparkle's window closed: what the windows held goes, unless one of Biblo's windows is open.
    var onSessionEnded: () -> Void = {}

    init(model: AppModel) {
        self.model = model
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    /// Dev and test runs (their own defaults suite) don't check: Sparkle keeps its state in the app's real defaults.
    /// `-debugUpdates YES` lets one check anyway.
    static var hasFeed: Bool { !((Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "").isEmpty }

    func start() {
        guard Self.hasFeed else { return log("updates: off (no SUFeedURL in Info.plist)") }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "defaultsSuite") == nil || defaults.bool(forKey: "debugUpdates") else { return }
        controller.startUpdater()
        log("updates: \(controller.updater.automaticallyChecksForUpdates ? "checking daily" : "automatic checks off") "
            + "at \(controller.updater.feedURL?.absoluteString ?? "no feed")")
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    /// "Check for Updates…" and the waiting update's menu item: Sparkle's window, in front.
    func checkNow() {
        controller.checkForUpdates(nil)
    }

    /// A check in the background, as the daily one (for `-debugUpdateCheck`).
    func checkInBackground() {
        controller.updater.checkForUpdatesInBackground()
    }

    // MARK: Gentle reminders

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// An update the daily check found waits for you to open it.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                             andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if handleShowingUpdate {
            // Sparkle's window comes up in front, like Biblo's own windows.
            bringAppToFront()
        } else {
            model.updateAvailable = update.displayVersionString
            log("updates: \(update.displayVersionString) is available; waiting in the menu")
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        model.updateAvailable = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        model.updateAvailable = nil
        onSessionEnded()
    }

    // MARK: What happened (logged)

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        log("updates: found \(item.displayVersionString) (\(item.versionString))")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        log("updates: up to date")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        log("updates: \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        log("updates: installing \(item.displayVersionString)")
    }
}
