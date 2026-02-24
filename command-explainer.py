#!/usr/bin/env python3
"""
Command Explainer - Claude Code PreToolUse Hook
Bashコマンド実行前にAI解説をメニューバーに通知する。

Phase 2: 通知専用。承認はClaude Code組み込みのターミナルUIで行う。
hookは常にexit 0で即座に終了し、承認をブロックしない。
"""

import json
import os
import re
import sys
import urllib.request


MENU_BAR_PORT = 19876
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# --- セーフリスト: 通知をスキップするコマンド ---
SAFE_PREFIXES = [
    # ファイル参照
    "ls", "pwd", "cat ", "head ", "tail ", "wc ",
    # 検索
    "grep ", "rg ", "find ", "which ", "type ", "command -v",
    # git 読み取り
    "git status", "git log", "git diff", "git branch",
    "git show", "git remote", "git tag",
    # バージョン確認
    "node -v", "npm -v", "python3 --version", "java -version",
    # 表示系
    "echo ", "printf ",
    # ディレクトリ確認
    "tree ",
]

# --- カテゴリ判定ルール（APIフォールバック用） ---
CATEGORIES = [
    (r"^npm (install|ci|add)\b", "パッケージ管理", "npmパッケージをインストールします"),
    (r"^npm (run|test|start|exec)\b", "npmスクリプト", "npmスクリプトを実行します"),
    (r"^npx ", "npmスクリプト", "npxでパッケージを実行します"),
    (r"^yarn ", "パッケージ管理", "Yarnでパッケージ操作を行います"),
    (r"^pnpm ", "パッケージ管理", "pnpmでパッケージ操作を行います"),
    (r"^pip3? install", "パッケージ管理", "Pythonパッケージをインストールします"),
    (r"^brew ", "パッケージ管理", "Homebrewでパッケージ操作を行います"),
    (r"^docker compose", "Docker", "Docker Composeでコンテナを操作します"),
    (r"^docker ", "Docker", "Dockerコマンドを実行します"),
    (r"^git (add|commit)\b", "Git コミット", "変更をステージ/コミットします"),
    (r"^git push\b", "Git プッシュ", "リモートに変更をプッシュします"),
    (r"^git (pull|fetch|merge|rebase|cherry-pick)\b", "Git 同期", "リモートと同期します"),
    (r"^git stash", "Git stash", "変更を一時退避します"),
    (r"^git (checkout|switch)\b", "Git ブランチ", "ブランチを切り替えます"),
    (r"^\./gradlew\b", "Gradle", "Gradleタスクを実行します"),
    (r"^gradle\b", "Gradle", "Gradleタスクを実行します"),
    (r"^make\b", "Make", "Makeタスクを実行します"),
    (r"^mkdir\b", "ファイル操作", "ディレクトリを作成します"),
    (r"^(cp|mv)\b", "ファイル操作", "ファイルをコピー/移動します"),
    (r"^rm\b", "ファイル削除", "ファイルを削除します"),
    (r"^chmod\b|^chown\b", "権限変更", "ファイル権限を変更します"),
    (r"^gh ", "GitHub CLI", "GitHub操作を行います"),
    (r"^curl\b|^wget\b", "ネットワーク", "外部にHTTPリクエストを送信します"),
    (r"^ssh\b|^scp\b", "リモート接続", "リモートサーバーに接続します"),
    (r"^python3?\b", "Python", "Pythonスクリプトを実行します"),
    (r"^node\b", "Node.js", "Node.jsスクリプトを実行します"),
    (r"^actionlint\b", "Lint", "GitHub Actionsの構文チェックを行います"),
]


def get_command_from_stdin() -> str:
    """標準入力からBashコマンドを取得"""
    try:
        input_data = json.load(sys.stdin)
        return input_data.get("tool_input", {}).get("command", "")
    except (json.JSONDecodeError, KeyError):
        return ""


def is_safe_command(command: str) -> bool:
    """セーフリストに含まれるか判定"""
    cmd = command.strip()
    for prefix in SAFE_PREFIXES:
        if cmd == prefix.strip() or cmd.startswith(prefix):
            return True
    return False


def _extract_effective_command(command: str) -> str:
    """パイプやチェーンから実質的な先頭コマンドを抽出。cd で始まる場合は次のコマンドを使う。"""
    first_cmd = re.split(r'\s*[|&;]\s*', command)[0].strip()
    if first_cmd.startswith("cd "):
        parts = re.split(r'\s*&&\s*|\s*;\s*', command, maxsplit=1)
        if len(parts) > 1:
            return parts[1].strip()
    return first_cmd


def categorize_command(command: str) -> tuple[str, str]:
    """ルールベースでカテゴリ判定（フォールバック用）"""
    effective = _extract_effective_command(command.strip())

    for pattern, category, description in CATEGORIES:
        if re.search(pattern, effective):
            return category, description

    return "コマンド確認", "以下のコマンドを実行します"


def _load_api_key() -> str | None:
    """プロジェクトの .env ファイルからAPIキーを読み込む。環境変数があればそちらを優先。"""
    key = os.environ.get("ANTHROPIC_API_KEY")
    if key:
        return key
    env_path = os.path.join(SCRIPT_DIR, ".env")
    try:
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith("ANTHROPIC_API_KEY="):
                    return line.split("=", 1)[1]
    except FileNotFoundError:
        pass
    return None


def get_explanation_from_api(command: str) -> str | None:
    """Anthropic API (Haiku) でコマンドを日本語解説"""
    api_key = _load_api_key()
    if not api_key:
        return None

    body = json.dumps({
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 120,
        "messages": [
            {
                "role": "user",
                "content": (
                    "以下のターミナルコマンドが何をするか、日本語1〜2文・最大4行で簡潔に説明してください。\n"
                    "- 非エンジニア向けに、技術用語は避けて平易に\n"
                    "- 説明だけを返してください\n\n"
                    f"```\n{command}\n```"
                ),
            }
        ],
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=body,
        headers={
            "Content-Type": "application/json",
            "X-API-Key": api_key,
            "Anthropic-Version": "2023-06-01",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            return result["content"][0]["text"]
    except Exception:
        return None


def get_explanation(command: str) -> str:
    """コマンドの解説を取得（API → フォールバック）"""
    api_result = get_explanation_from_api(command)
    if api_result:
        return api_result

    category, description = categorize_command(command)
    return f"[{category}] {description}"


WARNING_RULES: list[tuple[str, str, int]] = [
    (r"\brm\b", "削除したファイルは復元できません。", 0),
    (r"git push.*--force|git push.*-f\b", "リモートの変更履歴が上書きされます。", 0),
    (r"git reset --hard", "コミットされていない変更は失われます。", 0),
    (r"git checkout \.|git restore \.", "コミットされていない変更は失われます。", 0),
    (r"git clean\b", "未追跡のファイルが削除されます。", 0),
    (r"docker (rm|rmi|system prune)\b", "削除したコンテナ/イメージは復元できません。", 0),
    (r"drop (table|database)|truncate\b", "データベースの変更は復元できません。", re.IGNORECASE),
]


def get_warning(command: str) -> str | None:
    """危険なコマンドの場合、警告メッセージを返す"""
    cmd = command.strip()
    for pattern, message, flags in WARNING_RULES:
        if re.search(pattern, cmd, flags):
            return message
    return None


def notify_menu_bar(command: str, explanation: str, warning: str | None) -> None:
    """メニューバーアプリに通知を送信（fire & forget）"""
    try:
        payload = {
            "command": command,
            "explanation": explanation,
        }
        if warning:
            payload["warning"] = warning
        body = json.dumps(payload).encode("utf-8")

        req = urllib.request.Request(
            f"http://localhost:{MENU_BAR_PORT}/command",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        with urllib.request.urlopen(req, timeout=3) as resp:
            resp.read()  # レスポンスを読み捨て
    except Exception:
        pass  # アプリ未起動 or 接続失敗 → 無視してexit 0


# --- メインロジック ---


def main():
    command = get_command_from_stdin()

    if not command:
        sys.exit(0)

    # セーフリスト判定
    if is_safe_command(command):
        sys.exit(0)

    # AI解説を取得（API失敗時はルールベースにフォールバック）
    explanation = get_explanation(command)
    warning = get_warning(command)

    # メニューバーアプリに通知（fire & forget）
    notify_menu_bar(command, explanation, warning)

    # 常にexit 0（承認はClaude Codeのターミナルで行う）
    sys.exit(0)


if __name__ == "__main__":
    main()
