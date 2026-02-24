import Cocoa
import SwiftUI

/// メニューバーアイコン直下に吹き出しで表示するフローティング通知パネル
class NotificationPanel: NSPanel {
    private var clickOutsideMonitor: Any?

    override var canBecomeKey: Bool { false }  // フォーカスを奪わない

    init(contentView swiftUIView: some View, anchorButton: NSStatusBarButton) {
        // SwiftUIビューのサイズを計算
        let hostingView = NSHostingView(rootView: swiftUIView)
        let fittingSize = hostingView.fittingSize

        // メニューバーアイコンの位置からパネル位置を算出
        let buttonRect = anchorButton.convert(anchorButton.bounds, to: nil)
        let screenRect = anchorButton.window?.convertToScreen(buttonRect) ?? .zero

        // 吹き出しの矢印先端がアイコン中央に来るように配置
        let x = screenRect.midX - fittingSize.width / 2
        let y = screenRect.minY - fittingSize.height

        super.init(
            contentRect: NSRect(x: x, y: y, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.contentView = hostingView
        self.isFloatingPanel = true
        self.level = .floating
        self.isOpaque = false
        self.hasShadow = false  // SwiftUI側でshadowを描画
        self.backgroundColor = .clear  // 透明にして吹き出し形状を活かす

        setupClickOutsideMonitor()
    }

    /// 外側クリックで閉じる
    private func setupClickOutsideMonitor() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        orderOut(nil)
    }

    deinit {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
