import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var server: CommandServer!
    private var notificationPanel: NotificationPanel?
    private var lastCommandInfo: CommandInfo?
    private var rightClickMenu: NSMenu!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        startServer()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Claude Menu Helper")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // 右クリック用メニュー
        rightClickMenu = NSMenu()
        let titleItem = NSMenuItem(title: "Claude Menu Helper", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        rightClickMenu.addItem(titleItem)
        rightClickMenu.addItem(NSMenuItem.separator())
        rightClickMenu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // 右クリック → メニュー表示
            statusItem.menu = rightClickMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil  // 次回のクリックで action が発火するよう解除
        } else {
            // 左クリック → 通知トグル
            toggleNotification()
        }
    }

    // MARK: - Server

    private func startServer() {
        server = CommandServer()
        server.delegate = self
        server.start()
    }

    // MARK: - Notification

    private func toggleNotification() {
        // 表示中なら閉じる
        if notificationPanel?.isVisible == true {
            notificationPanel?.dismiss()
            notificationPanel = nil
            return
        }

        // 直前の通知があれば再表示
        if let info = lastCommandInfo {
            showNotification(info: info)
        }
    }

    private func showNotification(info: CommandInfo) {
        notificationPanel?.dismiss()
        notificationPanel = nil

        guard let button = statusItem.button else { return }

        let view = CommandView(
            command: info.command,
            explanation: info.explanation,
            warning: info.warning
        )

        let panel = NotificationPanel(contentView: view, anchorButton: button)
        panel.orderFrontRegardless()
        notificationPanel = panel
    }
}

// MARK: - CommandServerDelegate

extension AppDelegate: CommandServerDelegate {
    func serverDidReceiveCommand(_ info: CommandInfo) {
        DispatchQueue.main.async { [weak self] in
            self?.lastCommandInfo = info
            self?.showNotification(info: info)
        }
    }
}
