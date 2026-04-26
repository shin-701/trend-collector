#!/bin/bash
set -e

# SKILL_DIR の特定
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SKILL_DIR}/config.jsonc"

# jqが使えるかチェック
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

# config.jsonc からコメントを除去して一時ファイルに保存（jqでパースするため）
TEMP_CONFIG=$(mktemp)
sed '/^[[:space:]]*\/\//d' "$CONFIG_FILE" > "$TEMP_CONFIG"

# 出力ディレクトリの取得
LOG_DIR_REL="$(jq -r '.output.log_directory' "$TEMP_CONFIG")"
# ワークスペース（Vault）ルートを絶対パスで特定する
# SKILL_DIR (.agents/skills/trend-collector) の3階層上がVaultのルート
VAULT_ROOT="$(cd "${SKILL_DIR}/../../.." && pwd)"
LOG_DIR="${VAULT_ROOT}/${LOG_DIR_REL}"
mkdir -p "$LOG_DIR"

DATE_STR=$(date +%Y-%m-%d)
HATENA_LOG="${LOG_DIR}/${DATE_STR}_hatena.txt"
HN_LOG="${LOG_DIR}/${DATE_STR}_hn.txt"
REDDIT_LOG="${LOG_DIR}/${DATE_STR}_reddit.txt"

HN_URL=$(jq -r '.sources.hacker_news.url' "$TEMP_CONFIG")

echo "Starting parallel collection..."

# 並列実行 (設定ファイルは元のconfig.jsoncを渡す。各スクリプト内でコメント除去されるため)
bash "${SKILL_DIR}/scripts/collect_hatena.sh" "$CONFIG_FILE" > "$HATENA_LOG" &
PID_HATENA=$!

bash "${SKILL_DIR}/scripts/collect_hn.sh" "$HN_URL" "$CONFIG_FILE" > "$HN_LOG" &
PID_HN=$!

bash "${SKILL_DIR}/scripts/collect_reddit.sh" "$CONFIG_FILE" > "$REDDIT_LOG" &
PID_REDDIT=$!

# すべての完了を待機
wait $PID_HATENA
wait $PID_HN
wait $PID_REDDIT

echo "Collection finished."
echo "Logs saved to:"
echo " - $HATENA_LOG"
echo " - $HN_LOG"
echo " - $REDDIT_LOG"

# 一時ファイルの削除
rm "$TEMP_CONFIG"
