#!/bin/bash
# fetch_article.sh - 記事URLのHTMLを取得してプレーンテキストに変換する
# Usage: bash fetch_article.sh <URL> [max_chars]
# Output: プレーンテキスト (stdout)

URL="${1:-}"
# 生成AIエージェントのコンテキスト溢れ（Token超過）を防ぐための最大文字数。デフォルト8000文字
MAX_CHARS="${2:-8000}"

if [ -z "$URL" ]; then
    echo "Usage: fetch_article.sh <URL> [max_chars]" >&2
    exit 1
fi

# -------------------------------------------------------------
# Reddit は www.reddit.com だとbot確認が返るため old.reddit.com に書き換えてfetch
# old.reddit.com はJSレンダリング不要のシンプルなHTMLを返すためbot確認が発動しにくい
# -------------------------------------------------------------
if echo "$URL" | grep -qE '(www\.reddit\.com|reddit\.com|redd\.it)'; then
    URL=$(echo "$URL" | sed 's|www\.reddit\.com|old.reddit.com|g; s|^https://reddit\.com|https://old.reddit.com|g')
    REDDIT_FETCH=1
else
    REDDIT_FETCH=0
fi

# -------------------------------------------------------------
# 1. 設定ファイルの読み込みとUser-Agentの決定
# このスクリプトが配置されているディレクトリから config.jsonc を探し、
# User-Agent文字列を取得する。設定ファイルが無い場合はフォールバック値を使用
# -------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$(cd "$SCRIPT_DIR/.." && pwd)/config.jsonc"

if [ ! -f "$CONFIG_PATH" ]; then
    echo "ERROR: config.jsonc not found at: $CONFIG_PATH" >&2
    exit 1
fi
# Reddit は専用UA、それ以外はブラウザUAを使用
if [ "${REDDIT_FETCH:-0}" = "1" ]; then
    USER_AGENT=$(sed '/^[[:space:]]*\/\//d' "$CONFIG_PATH" | jq -r '.user_agents.reddit')
else
    USER_AGENT=$(sed '/^[[:space:]]*\/\//d' "$CONFIG_PATH" | jq -r '.user_agents.browser')
fi

# -------------------------------------------------------------
# 2. 対象URLのHTML取得
# 非常に大きなファイルによるハングアップを防ぐため --max-filesize 2MB を指定
# -------------------------------------------------------------
HTML=$(curl -sL \
    --max-time 15 \
    --max-filesize 2000000 \
    -H "User-Agent: $USER_AGENT" \
    -H "Accept-Language: ja,en;q=0.9" \
    "$URL" 2>/dev/null)

if [ -z "$HTML" ]; then
    echo "WARNING: Could not fetch $URL" >&2
    exit 1
fi

# -------------------------------------------------------------
# 3. 取得したHTMLをPython3でクリーンなプレーンテキストに変換
# 内容理解には不要なコードやヘッダ/フッタを除去し、LLMに優しいテキストデータを目指す
# -------------------------------------------------------------
echo "$HTML" | python3 -c "
import sys, re, html as html_mod

max_chars = $MAX_CHARS
content = sys.stdin.read()

# 3-a. 記事本編に関係ないタグブロックを丸ごと削除する
# script=JSコード, style=CSS, svg=画像コード, nav/footer/header=サイトの共通UI構造
for tag in ['script', 'style', 'svg', 'noscript', 'nav', 'footer', 'header']:
    content = re.sub(
        r'<' + tag + r'[^>]*>.*?</' + tag + r'>',
        ' ', content, flags=re.DOTALL | re.IGNORECASE
    )

# 3-b. 残ったすべてのHTMLタグ (<div...>, <p>, <a> 等) を単純に削除する
content = re.sub(r'<[^>]+>', ' ', content)

# 3-c. &amp; や &quot; などのHTML実体参照文字を自然な記号にデコードする
content = html_mod.unescape(content)

# 3-d. 文字列の最終調整
# 複数のスペースやタブを1つのスペースにし、余分すぎる連続改行（3つ以上）を2つに圧縮
content = re.sub(r'[ \t]+', ' ', content)
content = re.sub(r'\n{3,}', '\n\n', content)
content = content.strip()

# Agentに渡す文字数制限としてスライスする
print(content[:max_chars])
"
