#!/bin/bash
# collect_reddit.sh - config.jsoncを参照してRedditサブレッドを並列取得する
# Usage: bash collect_reddit.sh <path-to-config.jsonc>
# Output: カテゴリ|サブレッド名|タイトル|ups|コメント数|URL (1行1記事、stdout)

set -euo pipefail

CONFIG="${1:-config.jsonc}"

# -------------------------------------------------------------
# 1. 設定ファイルの読み込み
# config.jsonc から User-Agent とサブレッド一覧を取得する
# -------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: config.jsonc not found at: $CONFIG" >&2
    exit 1
fi

# config から Reddit 用の UA を取得
USER_AGENT=$(sed '/^[[:space:]]*\/\//d' "$CONFIG" | jq -r '.user_agents.reddit')

# config から Reddit API のアクセスパラメータを取得
REDDIT_BASE_URL=$(sed '/^[[:space:]]*\/\//d' "$CONFIG" | jq -r '.sources.reddit.base_url')
REDDIT_SORT=$(sed '/^[[:space:]]*\/\//d' "$CONFIG" | jq -r '.sources.reddit.sort')
REDDIT_TIME=$(sed '/^[[:space:]]*\/\//d' "$CONFIG" | jq -r '.sources.reddit.time_filter')
REDDIT_LIMIT=$(sed '/^[[:space:]]*\/\//d' "$CONFIG" | jq -r '.sources.reddit.limit_per_subreddit')

# jqコマンドを使用して、カテゴリとサブレッド名を抽出する
# 期待結果: "r/LocalLLaMA|AI" という形式の文字列リストになる
SUBREDDITS=$(sed '/^[[:space:]]*\/\//d' "$CONFIG" | jq -r '.sources.reddit.subreddits | to_entries[] | .key as $cat | .value[] | "\(.)|\($cat)"')

if [ -z "$SUBREDDITS" ]; then
    echo "ERROR: No subreddits found in config.jsonc" >&2
    exit 1
fi

REDDIT_THRESHOLDS_JSON=$(sed '/^[[:space:]]*\/\//d' "$CONFIG" | jq -c '.thresholds.reddit // {}')

# -------------------------------------------------------------
# 2. 一時ディレクトリの準備
# 並列取得した各サブレッドの結果ファイルをこのディレクトリ配下に出力する
# スクリプト終了時（正常・異常問わず）に自動削除されるようtrapを設定
# -------------------------------------------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# -------------------------------------------------------------
# 3. 1サブレッドに対してJSON情報を取得し、jqでパースする関数
# old.reddit.comのJSONレスポンスを利用することで、複雑なWebスクレイピングを回避
# -------------------------------------------------------------
fetch_subreddit() {
    local full_name="$1"   # 例: r/LocalLLaMA
    local category="$2"    # 例: AI
    local clean_name="${full_name#r/}"  # 先頭の 'r/' を取り除いた名前
    local out_file="$WORK_DIR/${clean_name}.txt"

    # bot判定回避: リクエスト前に 0〜2 秒のランダムスリープ
    sleep "$(awk 'BEGIN{srand(); print int(rand()*3)}')"
    local response
    response=$(curl -s --max-time 15 \
        -H "User-Agent: $USER_AGENT" \
        "${REDDIT_BASE_URL}/r/${clean_name}/${REDDIT_SORT}.json?t=${REDDIT_TIME}&limit=${REDDIT_LIMIT}" \
        2>/dev/null) || true

    # 3-b. JSON が正常に取得できた場合のみ parse
    # children配列をイテレートし、各記事のメタデータ（タイトル、ups、コメント数、URL）を結合して書き出す
    # 閾値 (REDDIT_THRESHOLDS_JSON) に基づいて、カテゴリごとの基準以上のupsのものだけを抽出する
    if [ -n "$response" ]; then
        echo "$response" | jq -r \
            --arg sub "$full_name" \
            --arg cat "$category" \
            --argjson thrs "$REDDIT_THRESHOLDS_JSON" \
            '.data.children[]? | select( .data.ups >= ($thrs[$cat] // $thrs["default"] // 0) ) | "\($cat)|\($sub)|\(.data.title)|\(.data.ups)|\(.data.num_comments)|https://www.reddit.com\(.data.permalink)"' \
            > "$out_file" 2>/dev/null || true
    fi
}

# bashのサブシェル（並列実行）から関数にアクセスできるようexport
export -f fetch_subreddit
export WORK_DIR USER_AGENT REDDIT_BASE_URL REDDIT_SORT REDDIT_TIME REDDIT_LIMIT REDDIT_THRESHOLDS_JSON

# -------------------------------------------------------------
# 4. 全サブレッドを並列取得（同時実行数を MAX_PARALLEL に制限してbot検知を回避）
# セマフォ方式: 実行中プロセス数が上限に達したら wait で1つ終わるまで待機
# -------------------------------------------------------------
MAX_PARALLEL=4
declare -a PIDS=()
while IFS='|' read -r name category; do
    # 同時実行数が上限に達したら1プロセス終わるまで待機
    while [ "${#PIDS[@]}" -ge "$MAX_PARALLEL" ]; do
        # 完了したプロセスをPIDS配列から除去
        NEW_PIDS=()
        for pid in "${PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                NEW_PIDS+=("$pid")
            fi
        done
        PIDS=("${NEW_PIDS[@]}")
        [ "${#PIDS[@]}" -ge "$MAX_PARALLEL" ] && sleep 0.5
    done
    fetch_subreddit "$name" "$category" &
    PIDS+=($!)
done <<< "$SUBREDDITS"

# 残りの全プロセスの完了を待機
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

# -------------------------------------------------------------
# 5. 結果の結合と出力
# 出力形式: カテゴリ|サブレッド名|タイトル(英語)|ups|コメント数|URL
# この出力は呼び出し元のAgentが読み取り、フィルタリングや翻訳に利用する
# -------------------------------------------------------------
if ls "$WORK_DIR"/*.txt 1>/dev/null 2>&1; then
    cat "$WORK_DIR"/*.txt
else
    echo "WARNING: No results collected from Reddit" >&2
fi
