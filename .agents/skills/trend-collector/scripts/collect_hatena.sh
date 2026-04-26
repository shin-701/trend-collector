#!/bin/bash
# collect_hatena.sh - config.jsoncのURLからはてなブックマーク人気記事をRSSで並列取得する
# Usage: bash collect_hatena.sh <path-to-config.jsonc>
# Output: カテゴリ|ブクマ数|タイトル|元記事URL (ブクマ数降順・重複除去済み、stdout)

set -euo pipefail

CONFIG="${1:-config.jsonc}"

# -------------------------------------------------------------
# 1. 設定ファイルの読み込み
# config.jsonc から User-Agent と対象URLリストを取得する
# -------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: config.jsonc not found at: $CONFIG" >&2
    exit 1
fi

USER_AGENT=$(sed '/^[[:space:]]*\/\//d' "$CONFIG" | jq -r '.user_agents.hatena')

# jqコマンドを使用して、config.jsoncから対象となるURLリストを一括取得する
URLS=$(sed '/^[[:space:]]*\/\//d' "$CONFIG" | jq -r '.sources.hatena_bookmark.urls[]')

if [ -z "$URLS" ]; then
    echo "ERROR: No hatena_bookmark URLs found in config.jsonc" >&2
    exit 1
fi

HATENA_THRESHOLD=$(sed '/^[[:space:]]*\/\//d' "$CONFIG" | jq -r '.thresholds.hatena_bookmark // 0')

# -------------------------------------------------------------
# 2. 一時ディレクトリの準備
# 並列取得した各RSSの結果ファイルをこのディレクトリ配下に出力する
# スクリプト終了時（正常・異常問わず）に自動削除されるようtrapを設定
# -------------------------------------------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# -------------------------------------------------------------
# 3. 1URLに対してRSSを取得し、Python3でパースする関数
# -------------------------------------------------------------
fetch_hatena_rss() {
    local url="$1"
    
    # 3-a. 対象URLをRSSフィードのURLへと正規化する
    # 検索ページ（search/text?）の場合は '&mode=rss' を付与
    # 通常のカテゴリページの場合は末尾に '.rss' を付与
    local rss_url="$url"
    if [[ "$url" == *"search/text?"* ]]; then
        if [[ "$url" != *"mode=rss"* ]]; then
            rss_url="${url}&mode=rss"
        fi
    elif [[ "$url" != *".rss" ]]; then
        rss_url="${url}.rss"
    fi

    # 3-b. ファイル名衝突を防ぐため、URLのMD5ハッシュから最初の8文字で一意のファイル名を生成
    local safe_name
    safe_name=$(echo "$rss_url" | md5sum | cut -c1-8)
    local out_file="$WORK_DIR/${safe_name}.txt"

    # FEED_URLをPythonに渡すためにエクスポート
    export FEED_URL="$url"

    # 3-c. curlでRSS(XML)を取得。失敗してもエラーで止まらないように '|| true' を設定
    local xml
    xml=$(curl -sL --max-time 15 -H "User-Agent: $USER_AGENT" "$rss_url" 2>/dev/null) || true

    if [ -z "$xml" ]; then
        return
    fi

    # 3-d. 取得したXMLをPython3スクリプトへパイプで渡し、ブクマ数・タイトル・URLを抽出
    echo "$xml" | python3 -c "
import sys, re, os, html as html_mod

content = sys.stdin.read()
# <item>タグ（1つの記事ブロック）単位で分割
items = re.split(r'<item[^>]*>', content)[1:]

# 全ての<item>をパースする
for item in items:
    # XMLタグから各種情報を正規表現で抜き出し
    title_m = re.search(r'<title>(.*?)</title>', item, re.DOTALL)
    link_m = re.search(r'<link>(.*?)</link>', item, re.DOTALL)
    count_m = re.search(r'<hatena:bookmarkcount>(\d+)</hatena:bookmarkcount>', item, re.IGNORECASE)
    date_m = re.search(r'<dc:date>(.*?)</dc:date>', item, re.IGNORECASE)
    
    if title_m and link_m:
        # 日付フィルター（過去10日以内の記事のみに絞る。古い検索結果が残り続けるのを防ぐ）
        if date_m:
            date_str = date_m.group(1)[:10]  # 'YYYY-MM-DD' を抽出
            import datetime
            threshold_date = (datetime.datetime.now() - datetime.timedelta(days=10)).strftime('%Y-%m-%d')
            if date_str < threshold_date:
                continue
        # タイトル内のCDATAやHTMLエンティティを適切に取り除く
        title = title_m.group(1).replace('<![CDATA[', '').replace(']]>', '')
        title = html_mod.unescape(re.sub(r'<[^>]+>', '', title).strip())
        
        url = link_m.group(1).strip()
        count = count_m.group(1) if count_m else '0'
        threshold = int(os.environ.get('HATENA_THRESHOLD', '0'))
        if int(count) < threshold:
            continue
        
        # はてな自身のポータルページなど、純粋な外部記事ではないリンクを除外
        # カテゴリの判定
        import urllib.parse
        feed_url = os.environ.get('FEED_URL', '')
        category = 'IT総合'
        if 'q=' in feed_url:
            q_match = re.search(r'q=([^&]+)', feed_url)
            if q_match:
                category = urllib.parse.unquote(q_match.group(1))
        elif 'hotentry/it/' in feed_url:
            category = urllib.parse.unquote(feed_url.split('/')[-1])
            
        print(f'{category}|{count}|{title}|{url}')
" >> "$out_file" 2>/dev/null || true
}

# bashのサブシェル（並列実行環境）から関数・変数を呼び出せるようにエクスポート
export -f fetch_hatena_rss
export WORK_DIR USER_AGENT HATENA_THRESHOLD

# -------------------------------------------------------------
# 4. 全URLに対するRSS取得をバックグラウンドジョブとして並列実行
# -------------------------------------------------------------
declare -a PIDS=()
while IFS= read -r url; do
    [ -z "$url" ] && continue
    fetch_hatena_rss "$url" &
    PIDS+=($!)
done <<< "$URLS"

# 起動したすべてのバックグラウンドジョブの完了を待機
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

# -------------------------------------------------------------
# 5. 取得結果の集計・整形
# sort : ブクマ数(2カラム目)を数値(n)・降順(r)でソート
# awk  : URL(4カラム目)をキーとし、同一URLの重複を排除(seen配列を利用)
# head : 全件出力（上位20件等の制限撤廃済）
# -------------------------------------------------------------
if ls "$WORK_DIR"/*.txt 1>/dev/null 2>&1; then
    cat "$WORK_DIR"/*.txt | \
        grep -v '^$' | \
        sort -t'|' -k2 -rn | \
        awk -F'|' '!seen[$4]++'
else
    echo "WARNING: No results collected from Hatena Bookmark" >&2
fi
