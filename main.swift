import AppKit
import Foundation
import UserNotifications

// terminal-notifier-compatible subset built on UNUserNotification (macOS 11+).
//
// Two modes:
//   CLI  — invoked with flags by Herdr's `delivery = "system"` path: posts a notification,
//          tagging it with the Herdr pane that most recently changed state.
//   GUI  — launched with no flags, which is how macOS starts us when a banner is clicked:
//          reads the tagged pane out of the notification and focuses it in Herdr.

let args = CommandLine.arguments

/// Locate the `herdr` binary.
///
/// In CLI mode we inherit Herdr's own PATH, so a PATH scan finds it. In GUI mode
/// LaunchServices starts us with a bare PATH (/usr/bin:/bin:/usr/sbin:/sbin), which
/// is why CLI mode records the resolved path in the notification's userInfo and GUI
/// mode prefers that. The candidate list is the last resort for both.
func resolveHerdrBinary(hint: String? = nil) -> String? {
    let fm = FileManager.default

    if let hint = hint, fm.isExecutableFile(atPath: hint) { return hint }

    if let override = ProcessInfo.processInfo.environment["HERDR_BIN"],
       fm.isExecutableFile(atPath: override) {
        return override
    }

    if let path = ProcessInfo.processInfo.environment["PATH"] {
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/herdr"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
    }

    let home = fm.homeDirectoryForCurrentUser.path
    let fallbacks = [
        "/opt/homebrew/bin/herdr",   // Homebrew, Apple silicon
        "/usr/local/bin/herdr",      // Homebrew, Intel
        "\(home)/.local/bin/herdr",
        "\(home)/.cargo/bin/herdr",  // cargo install
    ]
    return fallbacks.first { fm.isExecutableFile(atPath: $0) }
}

func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    return v.hasPrefix("-") ? nil : v
}

func has(_ flag: String) -> Bool { args.contains(flag) }

func fail(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
}

@discardableResult
func run(_ launchPath: String, _ arguments: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = arguments
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

/// The agent with the highest `state_change_seq` is the one whose transition
/// triggered this notification. Cheaper and far more robust than parsing the
/// "workspace · tab · name" body string.
func mostRecentlyChangedPane(_ herdrBin: String) -> String? {
    let (status, out) = run(herdrBin, ["agent", "list"])
    guard status == 0, let data = out.data(using: .utf8) else { return nil }
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let result = root["result"] as? [String: Any],
          let agents = result["agents"] as? [[String: Any]] else { return nil }

    var best: (seq: Int, pane: String)?
    for a in agents {
        guard let pane = a["pane_id"] as? String,
              let seq = a["state_change_seq"] as? Int else { continue }
        if best == nil || seq > best!.seq { best = (seq, pane) }
    }
    return best?.pane
}

// MARK: - GUI mode (banner clicked)

final class ClickHandler: NSObject, UNUserNotificationCenterDelegate, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // If no click response arrives shortly, we were launched for some other
        // reason — don't linger as a stray process.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo

        // `pane focus` is directional; `agent focus <pane_id>` is the by-id call,
        // and it switches workspace and tab as needed to reveal the pane.
        if let pane = info["pane_id"] as? String, !pane.isEmpty,
           let herdrBin = resolveHerdrBinary(hint: info["herdr_bin"] as? String) {
            run(herdrBin, ["agent", "focus", pane])
        }

        // Bring the terminal hosting Herdr to the front.
        if let bundleID = info["activate"] as? String, !bundleID.isEmpty {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = running.first {
                app.activate(options: [.activateAllWindows])
            } else {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.openApplication(at: url,
                                                       configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }

        completionHandler()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(0) }
    }
}

let isCLI = has("-message") || has("-title") || has("-list") || has("-remove")

if !isCLI {
    let app = NSApplication.shared
    let handler = ClickHandler()
    app.delegate = handler
    app.setActivationPolicy(.accessory)
    app.run()
    exit(0)
}

// MARK: - CLI mode

let center = UNUserNotificationCenter.current()
let sem = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0

// -list [ID|ALL]
if has("-list") {
    center.getDeliveredNotifications { notes in
        print("GroupID\tTitle\tSubtitle\tMessage\tDelivered At")
        let fmt = ISO8601DateFormatter()
        for n in notes {
            let c = n.request.content
            let group = c.threadIdentifier.isEmpty ? "(null)" : c.threadIdentifier
            let sub = c.subtitle.isEmpty ? "(null)" : c.subtitle
            print("\(group)\t\(c.title)\t\(sub)\t\(c.body)\t\(fmt.string(from: n.date))")
        }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 5)
    exit(exitCode)
}

// -remove ID|ALL
if has("-remove") {
    let target = value("-remove") ?? "ALL"
    if target == "ALL" {
        center.removeAllDeliveredNotifications()
    } else {
        center.getDeliveredNotifications { notes in
            let ids = notes.filter { $0.request.content.threadIdentifier == target }
                           .map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: ids)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 5)
    }
    usleep(200_000)
    exit(0)
}

// Herdr passes an empty -message for body-less toasts (`herdr notification show "test"`).
// A title alone is a perfectly valid notification, so only bail if both are missing.
let message = value("-message") ?? ""
let titleArg = value("-title") ?? ""
if message.isEmpty && titleArg.isEmpty {
    fail("usage: herdr-notify -message TEXT [-title TEXT] [-subtitle TEXT] [-sound NAME] [-group ID]")
    exit(1)
}

center.requestAuthorization(options: [.alert, .sound]) { granted, err in
    if let err = err {
        fail("authorization error: \(err.localizedDescription)")
        exitCode = 1
        sem.signal()
        return
    }
    guard granted else {
        fail("notification authorization denied — enable it in System Settings > Notifications")
        exitCode = 1
        sem.signal()
        return
    }

    let content = UNMutableNotificationContent()
    content.title = titleArg.isEmpty ? "Notification" : titleArg
    content.body = message
    if let s = value("-subtitle") { content.subtitle = s }
    if let g = value("-group") { content.threadIdentifier = g }

    if let s = value("-sound"), s.lowercased() != "none" {
        content.sound = s.lowercased() == "default"
            ? .default
            : UNNotificationSound(named: UNNotificationSoundName("\(s).aiff"))
    }

    var info: [String: String] = [:]
    if let activate = value("-activate") { info["activate"] = activate }
    if let herdrBin = resolveHerdrBinary() {
        info["herdr_bin"] = herdrBin
        if let pane = mostRecentlyChangedPane(herdrBin) { info["pane_id"] = pane }
    }
    content.userInfo = info

    let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    center.add(req) { err in
        if let err = err {
            fail("deliver failed: \(err.localizedDescription)")
            exitCode = 1
        }
        sem.signal()
    }
}

if sem.wait(timeout: .now() + 15) == .timedOut {
    fail("timed out waiting for notification center")
    exitCode = 1
}
usleep(300_000)  // grace period so the daemon picks it up before we exit
exit(exitCode)
