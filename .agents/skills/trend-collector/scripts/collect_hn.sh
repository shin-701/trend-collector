#!/bin/bash
# collect_hn.sh - Hacker Newsのトップページから記事一覧を取得する
# Usage: bash collect_hn.sh <HN_URL>
# Output: ポイント数|タイトル(英語)|HNコメントページURL|元記事URL (1行1記事、stdout)

set -euo pipefail

HN_URL="${1:-https://news.ycombinator.com/}"
CONFIG_PATH="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.jsonc}"

# -------------------------------------------------------------
# 1. 設定ファイルの読み込みとUser-Agentの決定
# このスクリプトが配置されているディレクトリから config.jsonc を探し、
# User-Agent文字列を取得する。設定ファイルが無い場合はフォールバック値を使用
# -------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$CONFIG_PATH" ]; then
    echo "ERROR: config.jsonc not found at: $CONFIG_PATH" >&2
    exit 1
fi
USER_AGENT=$(sed '/^[[:space:]]*\/\//d' "$CONFIG_PATH" | jq -r '.user_agents.browser')

HN_THRESHOLD=$(sed '/^[[:space:]]*\/\//d' "$CONFIG_PATH" | jq -r '.thresholds.hacker_news // 0')
export HN_THRESHOLD

# -------------------------------------------------------------
# 2. Hacker NewsトップページのHTML取得
# curlでページ全体のHTMLを一括取得する
# -------------------------------------------------------------
HTML=$(curl -sL --max-time 15 \
    -H "User-Agent: $USER_AGENT" \
    "$HN_URL" 2>/dev/null)

if [ -z "$HTML" ]; then
    echo "ERROR: Could not fetch Hacker News" >&2
    exit 1
fi

# -------------------------------------------------------------
# 3. 取得したHTMLを parse_hn.py でパースして記事情報を抽出
# bashのヒアドキュメント内で複雑なPythonの正規表現を書くとエスケープ地獄になるため、
# パースロジックは独立したPythonファイルに委譲して呼び出す構成にしている
# -------------------------------------------------------------
echo "$HTML" | python3 "${SCRIPT_DIR}/parse_hn.py"
