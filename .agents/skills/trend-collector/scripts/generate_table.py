#!/usr/bin/env python3
"""
generate_table.py
=================
収集ログ（hatena / hn / reddit）を読み込み、Markdownテーブルを生成して
指定の出力ファイルに追記する。

Usage:
    python3 generate_table.py <output_md_path> [<log_dir>] [<date>]

Arguments:
    output_md_path  追記先のMarkdownファイルパス
    log_dir         ログディレクトリ (省略時: config.jsonc の output.log_directory)
    date            対象日付 YYYY-MM-DD (省略時: 今日)
"""

import sys
import os
import re
import json
import datetime
import time

# ── 設定 ──────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SKILL_DIR  = os.path.dirname(SCRIPT_DIR)
CONFIG_PATH = os.path.join(SKILL_DIR, "config.jsonc")

# Google翻訳の1リクエストあたりの最大文字数
TRANSLATE_CHUNK_MAX = 4000
# レート制限対策のウェイト（秒）
TRANSLATE_WAIT = 0.3
# 既に日本語と判定する閾値（ASCII以外の文字が全体の30%以上なら日本語扱い）
JP_RATIO_THRESHOLD = 0.30


# ── ユーティリティ ─────────────────────────────────

def load_config():
    """config.jsonc を読み込む（コメント行を除去してパース）"""
    with open(CONFIG_PATH, encoding="utf-8") as f:
        raw = f.read()
    # // コメント行を除去
    cleaned = re.sub(r"^\s*//.*$", "", raw, flags=re.MULTILINE)
    return json.loads(cleaned)


def is_japanese(text: str) -> bool:
    """文字列が主に日本語かどうかを判定する"""
    if not text:
        return True
    non_ascii = sum(1 for c in text if ord(c) > 127)
    return (non_ascii / len(text)) >= JP_RATIO_THRESHOLD


def translate_titles(titles: list[str]) -> list[str]:
    """
    英語タイトルのリストを日本語に一括翻訳する。
    すでに日本語のものはそのまま返す。
    deep-translator が使えない場合はオリジナルをそのまま返す。
    """
    try:
        from deep_translator import GoogleTranslator
    except ImportError:
        print("[WARNING] deep-translator がインストールされていません。タイトルは翻訳せずに出力します。", file=sys.stderr)
        return titles

    translator = GoogleTranslator(source="auto", target="ja")
    results = []

    for title in titles:
        if is_japanese(title):
            results.append(title)
            continue
        try:
            translated = translator.translate(title)
            results.append(translated if translated else title)
        except Exception as e:
            print(f"[WARNING] 翻訳失敗: {title!r} -> {e}", file=sys.stderr)
            results.append(title)
        time.sleep(TRANSLATE_WAIT)

    return results


# ── ログパーサ ─────────────────────────────────────

def parse_hatena(path: str) -> list[dict]:
    """
    フォーマット: カテゴリ|ブクマ数|タイトル|URL[|興味度]
    （collect_hatena.sh の出力形式）
    末尾カラムが ★★★/★★/★ なら興味度として取り出す。
    タイトルに '|' が含まれる可能性があるため、先頭2フィールドと末尾URLを確定させ残りをタイトルとする。
    """
    RATINGS = {"★★★", "★★", "★"}
    articles = []
    if not os.path.exists(path):
        print(f"[WARNING] ログが見つかりません: {path}", file=sys.stderr)
        return articles

    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) < 4:
                continue
            category = parts[0].strip()
            score    = parts[1].strip()
            # 末尾カラムが興味度なら取り出し、そうでなければURLとして扱う
            if parts[-1].strip() in RATINGS:
                rating = parts[-1].strip()
                url    = parts[-2].strip()
                title  = "|".join(parts[2:-2]).strip()
            else:
                rating = "-"
                url    = parts[-1].strip()
                title  = "|".join(parts[2:-1]).strip()
            articles.append({
                "category": category,
                "score":    score,
                "title":    title,
                "url":      url,
                "rating":   rating,
            })
    return articles


def parse_hn(path: str) -> list[dict]:
    """
    フォーマット: ポイント|タイトル|HN_URL|元記事URL[|興味度]
    （collect_hn.sh の出力形式）
    末尾カラムが ★★★/★★/★ なら興味度として取り出す。
    """
    RATINGS = {"★★★", "★★", "★"}
    articles = []
    if not os.path.exists(path):
        print(f"[WARNING] ログが見つかりません: {path}", file=sys.stderr)
        return articles

    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) < 4:
                continue
            score = parts[0].strip()
            if parts[-1].strip() in RATINGS:
                rating = parts[-1].strip()
                hn_url = parts[-3].strip()   # 末尾から3番目 = HN コメントページURL
                title  = "|".join(parts[1:-3]).strip()
            else:
                rating = "-"
                hn_url = parts[-2].strip()   # 末尾から2番目 = HN コメントページURL
                title  = "|".join(parts[1:-2]).strip()
            articles.append({
                "score":  score,
                "title":  title,
                "url":    hn_url,
                "rating": rating,
            })
    return articles


def parse_reddit(path: str) -> list[dict]:
    """
    フォーマット: カテゴリ|サブレッド|タイトル|ups|コメント数|URL[|興味度]
    （collect_reddit.sh の出力形式）
    末尾カラムが ★★★/★★/★ なら興味度として取り出す。
    """
    RATINGS = {"★★★", "★★", "★"}
    articles = []
    if not os.path.exists(path):
        print(f"[WARNING] ログが見つかりません: {path}", file=sys.stderr)
        return articles

    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) < 6:
                continue
            category  = parts[0].strip()
            subreddit = parts[1].strip()
            if parts[-1].strip() in RATINGS:
                rating   = parts[-1].strip()
                url      = parts[-2].strip()
                comments = parts[-3].strip()
                ups      = parts[-4].strip()
                title    = "|".join(parts[2:-4]).strip()
            else:
                rating   = "-"
                url      = parts[-1].strip()
                comments = parts[-2].strip()
                ups      = parts[-3].strip()
                title    = "|".join(parts[2:-3]).strip()
            articles.append({
                "category":  category,
                "subreddit": subreddit,
                "title":     title,
                "ups":       ups,
                "comments":  comments,
                "url":       url,
                "rating":    rating,
            })
    return articles


# ── Markdownテーブル生成 ──────────────────────────

def build_hatena_table(articles: list[dict]) -> str:
    """はてブ用テーブルを生成する"""
    header = "| タイトル | ブクマ数 | カテゴリ | 興味度 |\n|---------|---------|----------|--------\n"
    rows = []
    titles = [a["title"] for a in articles]
    translated = translate_titles(titles)

    for art, t in zip(articles, translated):
        row = f"| [{t}]({art['url']}) | {art['score']} users | {art['category']} | {art.get('rating', '-')} |"
        rows.append(row)

    return header + "\n".join(rows) + "\n"


def build_hn_table(articles: list[dict]) -> str:
    """HN用テーブルを生成する"""
    header = "| タイトル | ポイント | 興味度 |\n|---------|----------|--------\n"
    rows = []
    titles = [a["title"] for a in articles]
    translated = translate_titles(titles)

    for art, t in zip(articles, translated):
        row = f"| [{t}]({art['url']}) | {art['score']}pt | {art.get('rating', '-')} |"
        rows.append(row)

    return header + "\n".join(rows) + "\n"


def build_reddit_tables(articles: list[dict]) -> str:
    """Reddit用テーブルをカテゴリごとにグループ化して生成する"""
    # カテゴリ順を保持しながらグループ化
    category_order = []
    by_category: dict[str, list[dict]] = {}
    for art in articles:
        cat = art["category"]
        if cat not in by_category:
            by_category[cat] = []
            category_order.append(cat)
        by_category[cat].append(art)

    sections = []
    for cat in category_order:
        arts = by_category[cat]
        titles = [a["title"] for a in arts]
        translated = translate_titles(titles)

        header = f"### {cat}\n\n| タイトル | 投票数 | コメント数 | サブレッド | 興味度 |\n|---------|--------|-----------|------------|--------\n"
        rows = []
        for art, t in zip(arts, translated):
            row = f"| [{t}]({art['url']}) | {art['ups']} ups | {art['comments']} | {art['subreddit']} | {art.get('rating', '-')} |"
            rows.append(row)
        sections.append(header + "\n".join(rows) + "\n")

    return "\n".join(sections)


# ── メイン ────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 generate_table.py <output_md_path> [<log_dir>] [<date>]")
        sys.exit(1)

    output_path = sys.argv[1]
    config      = load_config()
    log_dir_rel = config.get("output", {}).get("log_directory", "11_ideas/logs")

    # ワークスペースルートは SKILL_DIR の 3 階層上（.agents/skills/trend-collector）
    workspace_root = os.path.abspath(os.path.join(SKILL_DIR, "../../.."))
    log_dir = sys.argv[2] if len(sys.argv) >= 3 else os.path.join(workspace_root, log_dir_rel)
    date    = sys.argv[3] if len(sys.argv) >= 4 else datetime.date.today().isoformat()

    print(f"[INFO] 対象日付: {date}")
    print(f"[INFO] ログディレクトリ: {log_dir}")
    print(f"[INFO] 出力ファイル: {output_path}")

    hatena_log = os.path.join(log_dir, f"{date}_hatena.txt")
    hn_log     = os.path.join(log_dir, f"{date}_hn.txt")
    reddit_log = os.path.join(log_dir, f"{date}_reddit.txt")

    # ── パース ──
    hatena_articles  = parse_hatena(hatena_log)
    hn_articles      = parse_hn(hn_log)
    reddit_articles  = parse_reddit(reddit_log)

    print(f"[INFO] はてな: {len(hatena_articles)}件 / HN: {len(hn_articles)}件 / Reddit: {len(reddit_articles)}件")

    # ── テーブル生成 ──
    print("[INFO] タイトルを翻訳中...")
    hatena_table  = build_hatena_table(hatena_articles)
    hn_table      = build_hn_table(hn_articles)
    reddit_tables = build_reddit_tables(reddit_articles)

    # ── Markdownブロック組み立て ──
    output_block = f"""
---

## はてブIT（日本市場）

### 全記事一覧

{hatena_table}
---

## Hacker News（グローバル）

### 全記事一覧

{hn_table}
---

## Reddit

{reddit_tables}"""

    # ── 出力ファイルに追記 ──
    with open(output_path, "a", encoding="utf-8") as f:
        f.write(output_block)

    total = len(hatena_articles) + len(hn_articles) + len(reddit_articles)
    print(f"[DONE] {total}件を {output_path} に追記しました。")


if __name__ == "__main__":
    main()
