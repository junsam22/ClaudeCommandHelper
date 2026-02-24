# Command Explainer - 実装計画

Claude Codeが実行するコマンドを日本語で要約・解説してメニューバーに表示するツール。
承認・拒否はClaude Code本体のターミナルUIで行う。

## 設計方針

- **メニューバーアプリ** = コマンドの日本語解説を表示する（読み取り専用）
- **ターミナル** = Claude Code組み込みの承認UI で許可/拒否する
- hookは通知だけして即座にexit 0。承認をブロックしない

## 全体像

```
Phase 1a (ルールベース版)     Phase 1b (API版)          Phase 2 (メニューバー通知)
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────────────┐
│ PreToolUse Hook  │     │ PreToolUse Hook  │     │ PreToolUse Hook          │
│       ↓          │     │       ↓          │     │       ↓                  │
│ Python Script    │     │ Python Script    │     │ Python Script            │
│       ↓          │ →   │       ↓          │ →   │       ↓                  │
│ カテゴリ判定      │     │ Claude API(Haiku)│     │ Claude API(Haiku)        │
│       ↓          │     │       ↓          │     │       ↓                  │
│ osascript Dialog │     │ osascript Dialog │     │ メニューバーに通知送信     │
│       ↓          │     │       ↓          │     │       ↓                  │
│ allow / block    │     │ allow / block    │     │ 即座に exit 0             │
└──────────────────┘     └──────────────────┘     │       ↓                  │
 APIキー不要・無料         APIキー必要・高品質解説   │ Claude Code組み込みUIで   │
                                                  │ ターミナル承認            │
                                                  └──────────────────────────┘
                                                   通知のみ。承認はターミナル
```

---

## Phase 2 動作フロー ← 今回実装

```
Claude Codeが Bash ツールを呼び出す
  ↓
PreToolUse hook 発火（stdin に JSON が渡る）
  ↓
command-explainer.py が起動
  ↓
コマンドを抽出
  ↓
セーフリストに含まれる？ ─── Yes → そのまま exit 0（通知なし）
  │
  No
  ↓
Anthropic API (Haiku) で日本語解説を生成
  ↓
危険コマンド判定 → 警告メッセージを付与（rm, git push --force 等）
  ↓
HTTP POST でメニューバーアプリに送信（fire & forget）
  ↓
即座に exit 0（hookは承認をブロックしない）
  ↓
┌─────────────────────────────────┐
│ 同時に2つが表示される：          │
│                                 │
│ 1. メニューバー通知（解説）      │
│    日本語で何をするか表示        │
│    警告がある場合は⚠️表示       │
│    読み取り専用・ボタンなし      │
│                                 │
│ 2. ターミナル承認UI（Claude Code）│
│    Do you want to proceed?      │
│    > 1. Yes                     │
│      2. No                      │
│    ユーザーがここで承認/拒否     │
└─────────────────────────────────┘
```

### メニューバー通知UI

```
┌──────────────────────────────────────┐
│  ターミナルコマンド実行 · 22:01       │
│                                      │
│  「image-*.webp」はWebページ用の画像  │
│  ファイルです。削除すると表示に影響を  │
│  与える可能性があります。             │
│                                      │
│  ⚠️ 削除したファイルは復元できません。│
└──────────────────────────────────────┘
```

- 承認/拒否ボタンなし（通知のみ）
- 外側をクリックで自動的に閉じる
- 次のコマンド通知が来たら前の通知を置き換え

---

## ファイル配置

```
~/.claude/
  └── settings.json          ← hookの設定（パスを指定するだけ）

~/dev/freakapp/ClaudeCommandHelper/
  ├── plan.md                ← この計画書
  ├── command-explainer.py   ← hookスクリプト（通知送信 + exit 0）
  ├── Package.swift          ← Swift Package定義
  └── Sources/
      ├── main.swift             ← エントリポイント
      ├── AppDelegate.swift      ← メニューバー設定・通知管理
      ├── CommandServer.swift    ← HTTPサーバー（localhost:19876）
      └── CommandView.swift      ← SwiftUI 通知ビュー
```

---

## コンポーネント詳細

### command-explainer.py（hookスクリプト）

役割: コマンド解説を生成し、メニューバーアプリに通知を送る。承認はしない。

1. stdinからコマンドを取得
2. セーフリスト判定（読み取り系はスキップ）
3. Haiku APIで日本語解説を生成（APIなしの場合はルールベースにフォールバック）
4. 危険コマンドの警告判定（rm, git push --force 等）
5. HTTP POSTでメニューバーアプリに送信
6. 即座にexit 0

### ClaudeCommandHelper（SwiftUIメニューバーアプリ）

役割: メニューバーに常駐し、コマンド解説の通知を表示する。

- メニューバーアイコン（ターミナルアイコン）
- localhost:19876 でHTTPサーバーを起動
- hookからPOSTを受信 → 即座にACK返却 → 通知ポップオーバー表示
- 通知はクリックで閉じる or 次の通知で置き換え

### 通信プロトコル

```
Hook → App:
  POST http://localhost:19876/command
  {
    "command": "rm image-*.webp",
    "explanation": "「image-*.webp」はWebページ用の画像ファイルです。...",
    "warning": "削除したファイルは復元できません。"   ← optional
  }

App → Hook:
  200 OK {"status": "received"}
  （即座に返却。hookはレスポンスを待たずにexit 0してもOK）
```

---

## セーフリスト（通知をスキップするコマンド）

```python
SAFE_PREFIXES = [
    "ls", "pwd", "cat ", "head ", "tail ", "wc ",
    "grep ", "rg ", "find ", "which ", "type ", "command -v",
    "git status", "git log", "git diff", "git branch",
    "git show", "git remote", "git tag",
    "node -v", "npm -v", "python3 --version", "java -version",
    "echo ", "printf ", "tree ",
]
```

※ 使いながら調整する前提。

## 危険コマンド警告

| パターン | 警告メッセージ |
|----------|---------------|
| `rm` | 削除したファイルは復元できません。 |
| `git push --force` | リモートの変更履歴が上書きされます。 |
| `git reset --hard` | コミットされていない変更は失われます。 |
| `git checkout .` / `git restore .` | コミットされていない変更は失われます。 |
| `git clean` | 未追跡のファイルが削除されます。 |
| `docker rm/rmi/system prune` | 削除したコンテナ/イメージは復元できません。 |

---

## settings.json

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/dev/freakapp/ClaudeCommandHelper/command-explainer.py",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

timeout: Haiku API呼び出し（~3秒）+ HTTP送信で十分な30秒。
承認待ちが不要になったので短くできる。

---

## 実装ステップ

| Step | 内容 | 状態 |
|------|------|------|
| 1 | Phase 1a: ルールベース版 command-explainer.py | ✅ 完了 |
| 2 | Phase 1b: API版（Haiku解説）に改修 | ✅ 完了 |
| 3 | Phase 2: SwiftUIメニューバーアプリ作成 | ✅ 完了 |
| 4 | Phase 2: command-explainer.py を通知専用に改修 | ✅ 完了 |
| 5 | Phase 2: 動作テスト・UI調整 | ⬜ |

---

## 前Phaseからの変更点

| 項目 | Phase 1a/1b | Phase 2 |
|------|-------------|---------|
| 承認方法 | osascriptダイアログ | Claude Code組み込みUI（ターミナル） |
| hookの役割 | 承認ゲート（block/allow） | 通知のみ（常にallow） |
| 解説の表示先 | osascriptダイアログ内 | メニューバー通知 |
| フォーカス | ダイアログがフォーカスを奪う | メニューバー通知はフォーカスを奪わない |
| timeout | 300秒（承認待ち） | 30秒（API呼び出しのみ） |

---

## リスク・注意点

| リスク | 対策 |
|--------|------|
| メニューバーアプリ未起動時 | hookはHTTP送信失敗を無視してexit 0。通知なしでもターミナル承認は動く |
| Haiku API遅延 | hookがexit 0するまでClaude Codeのターミナル承認UIが出ない。API timeout 10秒で制限 |
| Claude Codeが自動許可モード | ターミナル承認UIが出ない → メニューバー通知は出るが承認ステップがなくなる |
| 通知の文字エスケープ | JSON通信なのでosascriptよりエスケープ問題が少ない |

---

## 将来の拡張候補

- コマンド履歴の一覧表示（メニューバーアプリ内）
- 危険度レベルの色分け（赤/黄/緑）
- 通知の自動非表示タイマー設定
- 特定コマンドパターンの通知ミュート機能
