import SwiftUI

// MARK: - カラーパレット

private enum BubbleColors {
    static let background = Color(red: 0.11, green: 0.12, blue: 0.19)   // #1C1F30 ダークネイビー
    static let commandBg  = Color(red: 0.15, green: 0.16, blue: 0.24)   // コマンド欄の背景
    static let warningBg  = Color.orange.opacity(0.12)

    static let primary    = Color.white
    static let secondary  = Color.white.opacity(0.55)
    static let tertiary   = Color.white.opacity(0.35)
    static let warning    = Color(red: 1.0, green: 0.72, blue: 0.30)    // 暖かいオレンジ
}

// MARK: - 吹き出し形状

struct BubbleShape: Shape {
    var arrowWidth: CGFloat = 14
    var arrowHeight: CGFloat = 8
    var cornerRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let bodyRect = CGRect(
            x: rect.minX,
            y: rect.minY + arrowHeight,
            width: rect.width,
            height: rect.height - arrowHeight
        )

        var path = Path()

        // 矢印（上部中央）
        let arrowMid = rect.midX
        path.move(to: CGPoint(x: arrowMid, y: rect.minY))
        path.addLine(to: CGPoint(x: arrowMid + arrowWidth / 2, y: bodyRect.minY))
        path.addLine(to: CGPoint(x: arrowMid - arrowWidth / 2, y: bodyRect.minY))
        path.closeSubpath()

        // 角丸の本体
        path.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        return path
    }
}

// MARK: - メインビュー

struct CommandView: View {
    let command: String
    let explanation: String
    let warning: String?

    private let bubbleWidth: CGFloat = 468

    var body: some View {
        ZStack(alignment: .top) {
            // 吹き出し背景
            BubbleShape()
                .fill(BubbleColors.background)
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)

            // コンテンツ
            VStack(alignment: .leading, spacing: 14) {
                header
                explanationSection
                commandSection
                if let warning = warning {
                    warningSection(warning)
                }
            }
            .padding(.top, 8 + 16)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(width: bubbleWidth)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 11))
                .foregroundStyle(BubbleColors.secondary)
            Text("コマンド実行")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BubbleColors.secondary)
            Spacer()
            Text(Date(), style: .time)
                .font(.system(size: 11))
                .foregroundStyle(BubbleColors.tertiary)
        }
    }

    // MARK: - 解説

    private var explanationSection: some View {
        Text(explanation)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(BubbleColors.primary)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - コマンド原文

    private var commandSection: some View {
        HStack(spacing: 0) {
            Text("$ ")
                .foregroundStyle(BubbleColors.tertiary)
            Text(command)
                .foregroundStyle(BubbleColors.secondary)
        }
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(3)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubbleColors.commandBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 警告

    private func warningSection(_ warning: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(BubbleColors.warning)
            Text(warning)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BubbleColors.warning)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubbleColors.warningBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
