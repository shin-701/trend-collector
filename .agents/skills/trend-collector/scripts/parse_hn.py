import sys, re, os, html as html_mod

# 標準入力からパイプで渡されたHacker NewsのHTML全体を読み込む
content = sys.stdin.read()
hn_base = 'https://news.ycombinator.com/'

# -------------------------------------------------------------
# 1. スコア（ポイント）の抽出
# HNのスコア表示用タグ: <span id="score_123456">NN points</span>
# ここから item_id とそのスコアを抽出し、辞書 (scores_data) に格納する
# -------------------------------------------------------------
score_pattern = re.compile(
    r'<span[^>]+id="score_(\d+)"[^>]*>(\d+) points</span>',
    re.IGNORECASE
)
scores_data = {iid: sc for iid, sc in score_pattern.findall(content)}

# -------------------------------------------------------------
# 2. 記事タイトルと元URLの抽出
# HNのタイトル表示用タグ: <span class="titleline"><a href="元URL">タイトル</a>
# -------------------------------------------------------------
title_pattern = re.compile(
    r'<span[^>]+class="titleline"[^>]*><a href="([^"]+)"[^>]*>([^<]+)</a>',
    re.IGNORECASE
)
titles_data = title_pattern.findall(content)

# -------------------------------------------------------------
# 3. 全ての item?id (コメントページのID) の出現順リストを作成
# Hacker NewsのHTML構造では、タイトルのすぐ下の行にコメントリンクが付く。
# その順番をリストとして保持しておくことで、後ほどタイトルと紐付ける。
# -------------------------------------------------------------
itemid_all = re.findall(r'item\?id=(\d+)', content)

# 処理済み item_id を保持するセット（重複防止用）
seen_ids = set()
# itemid_all リストをどこまで読み進めたかを管理するカーソル
item_cursor = 0

# -------------------------------------------------------------
# 4. 記事ごとに情報を組み立てて出力
# -------------------------------------------------------------
for article_url, title in titles_data:
    # HTMLエンティティ（&amp;など）を通常の文字にデコードして前後の空白を削除
    title = html_mod.unescape(title).strip()
    hn_comment_url = ''
    item_id = ''

    # パターンA: 記事のリンク先が外部サイトではなくHN内のスレッドである場合 (例: Ask HN, Show HN)
    if article_url.startswith('item?id='):
        item_id = article_url.split('=')[1]
        hn_comment_url = hn_base + article_url
        original_url = hn_comment_url
        
    # パターンB: 通常の外部記事リンクの場合
    else:
        original_url = article_url
        
        # タイトル行に対応する item_id（=コメントページへのリンク）を見つけるため、
        # まだ使われていない次の item_id を `itemid_all` から探して割り当てる
        while item_cursor < len(itemid_all):
            candidate = itemid_all[item_cursor]
            item_cursor += 1
            if candidate not in seen_ids:
                item_id = candidate
                hn_comment_url = hn_base + 'item?id=' + candidate
                break

    # 割り当てられた item_id が空っぽ、または既に処理済みの場合はスキップ（異常系対応）
    if not item_id or item_id in seen_ids:
        continue
    
    seen_ids.add(item_id)

    # 辞書からスコアを取得。見つからなければ '0' とする
    score = scores_data.get(item_id, '0')
    
    threshold = int(os.environ.get('HN_THRESHOLD', '0'))
    if int(score) < threshold:
        continue
    
    # 最終出力をパイプ区切りで標準出力に表示 (シェルスクリプト側で後続処理される)
    print(f'{score}|{title}|{hn_comment_url}|{original_url}')
