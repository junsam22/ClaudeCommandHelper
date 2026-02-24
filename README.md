# ClaudeCommandHelper

Claude Codeが実行するBashコマンドを日本語で解説し、macOSメニューバーに通知表示するツール。

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Python](https://img.shields.io/badge/Python-3.11%2B-green)

## 概要

Claude Codeの[PreToolUse Hook](https://docs.anthropic.com/en/docs/claude-code/hooks)と連携し、Bashコマンド実行前にメニューバーで「何をするコマンドか」を日本語で表示します。

- 非エンジニアでもコマンドの内容がわかる簡潔な解説
- 危険なコマンド（`rm`, `git push --force` 等）には警告を表示
- Claude Codeの承認UIはブロックしない（通知のみ）

## 動作フロー

```
Claude Codeが Bash ツールを呼び出す
  ↓
PreToolUse hook 発火
  ↓
command-explainer.py が起動
  ↓
セーフリストに含まれる？ → Yes → exit 0（通知なし）
  ↓ No
Anthropic API (Haiku) で日本語解説を生成
  ↓
メニューバーアプリに HTTP POST で通知
  ↓
即座に exit 0（承認はClaude Codeのターミナルで行う）
```

## セットアップ

### 1. ビルド

```bash
swift build --configuration release
```

### 2. .app バンドル作成

```bash
APP_DIR="ClaudeCommandHelper.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/release/ClaudeCommandHelper "$APP_DIR/Contents/MacOS/"
```

`Info.plist` と アイコンは `scripts/generate-icon.swift` で生成できます。

```bash
swift scripts/generate-icon.swift
cp /tmp/ClaudeCommandHelper.icns "$APP_DIR/Contents/Resources/"
codesign --force --deep --sign - "$APP_DIR"
```

### 3. APIキーの設定

プロジェクトルートに `.env` ファイルを作成：

```
ANTHROPIC_API_KEY=your-api-key-here
```

APIキーがない場合はルールベースのカテゴリ判定にフォールバックします。

### 4. Claude Code Hook の設定

`~/.claude/settings.json` に以下を追加：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/ClaudeCommandHelper/command-explainer.py",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

### 5. 起動

`ClaudeCommandHelper.app` をダブルクリック、またはDockに配置して起動。

## 操作方法

| 操作 | 動作 |
|------|------|
| 新しいコマンド実行時 | メニューバーに吹き出し通知が自動表示 |
| 画面の他の場所をクリック | 吹き出しが閉じる |
| メニューバーアイコンを左クリック | 直前の通知を再表示/非表示（トグル） |
| メニューバーアイコンを右クリック | 終了メニュー |

## 通信プロトコル

Hook → App 間は `localhost:19876` でHTTP通信します。

```json
POST http://localhost:19876/command
{
  "command": "rm -rf dist/",
  "explanation": "distフォルダを削除します",
  "warning": "削除したファイルは復元できません。"
}
```

## ファイル構成

```
ClaudeCommandHelper/
├── Package.swift              # Swift Package 定義
├── Sources/
│   ├── main.swift             # エントリポイント
│   ├── AppDelegate.swift      # メニューバー・通知管理
│   ├── CommandServer.swift    # TCP サーバー（HTTP受信）
│   ├── CommandView.swift      # SwiftUI 通知ビュー
│   └── NotificationPanel.swift # フローティングパネル
├── command-explainer.py       # PreToolUse Hook スクリプト
├── scripts/
│   └── generate-icon.swift    # アプリアイコン生成
└── .env                       # APIキー（.gitignore対象）
```

## ライセンス

MIT
