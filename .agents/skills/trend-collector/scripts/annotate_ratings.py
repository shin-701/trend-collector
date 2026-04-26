#!/usr/bin/env python3
"""
annotate_ratings.py
===================
ログファイルの各行末尾に興味度カラム（★★★/★★/★）を追記して上書き保存する。

Usage:
    python3 annotate_ratings.py <log_file> [<ratings_json_file>]

Arguments:
    log_file            対象ログファイルのパス（例: 11_ideas/logs/2026-04-26_hatena.txt）
    ratings_json_file   URL→興味度のマッピングJSON（省略時: ログと同ディレクトリの YYYY-MM-DD_ratings.json）

ratings_json の形式:
    {
        "https://example.com/article1": "★★★",
        "https://news.ycombinator.com/item?id=12345": "★★",
        "https://www.reddit.com/r/...": "★"
    }

Notes:
    - ratings_json を省略した場合、ログファイルのディレクトリと日付から自動解決する
      例: 11_ideas/logs/2026-04-26_hatena.txt → 11_ideas/logs/2026-04-26_ratings.json
    - 既に興味度が追記済みの行はスキップ（べき等）
    - ratings_json に存在しないURLは ★（最低評価）をフォールバックとして使用
"""

import sys
import os
import re
import json

RATINGS = {"★★★", "★★", "★"}


def resolve_ratings_path(log_path: str) -> str:
    """
    ログファイルパスから ratings JSON パスを自動解決する。
    例: /path/to/logs/2026-04-26_hatena.txt → /path/to/logs/2026-04-26_ratings.json
    """
    log_dir      = os.path.dirname(os.path.abspath(log_path))
    log_filename = os.path.basename(log_path)
    # ファイル名の先頭 YYYY-MM-DD を抽出
    m = re.match(r"(\d{4}-\d{2}-\d{2})", log_filename)
    if not m:
        raise ValueError(f"ログファイル名から日付を取得できません: {log_filename}")
    date = m.group(1)
    return os.path.join(log_dir, f"{date}_ratings.json")


def load_ratings(json_path: str) -> dict:
    """ratings JSON ファイルを読み込む"""
    with open(json_path, encoding="utf-8") as f:
        return json.load(f)


def annotate_log(log_path: str, ratings: dict) -> int:
    """
    ログファイルの各行末尾に興味度を追記して上書き保存する。
    Returns: 追記した行数
    """
    with open(log_path, encoding="utf-8") as f:
        lines = f.readlines()

    new_lines = []
    annotated = 0

    for line in lines:
        stripped = line.rstrip("\n")
        if not stripped:
            new_lines.append(line)
            continue

        parts = stripped.split("|")

        # 既に興味度が追記済みの場合はスキップ（べき等）
        if parts[-1].strip() in RATINGS:
            new_lines.append(line)
            continue

        # URLは各行の末尾フィールド
        url    = parts[-1].strip()
        rating = ratings.get(url, "★")
        new_lines.append(stripped + "|" + rating + "\n")
        annotated += 1

    with open(log_path, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    return annotated


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 annotate_ratings.py <log_file> [<ratings_json_file>]")
        print()
        print("Example (ratings.json を自動解決):")
        print("  python3 annotate_ratings.py 11_ideas/logs/2026-04-26_hatena.txt")
        print()
        print("Example (ratings.json を明示):")
        print("  python3 annotate_ratings.py 11_ideas/logs/2026-04-26_hatena.txt /tmp/ratings.json")
        sys.exit(1)

    log_path = sys.argv[1]

    # ratings JSON パスの解決（引数があれば優先、なければ自動解決）
    if len(sys.argv) >= 3:
        ratings_json = sys.argv[2]
    else:
        ratings_json = resolve_ratings_path(log_path)
        print(f"[INFO] ratings JSON: {ratings_json} (自動解決)")

    if not os.path.exists(log_path):
        print(f"[ERROR] ログファイルが見つかりません: {log_path}", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(ratings_json):
        print(f"[ERROR] ratings JSON が見つかりません: {ratings_json}", file=sys.stderr)
        sys.exit(1)

    ratings   = load_ratings(ratings_json)
    annotated = annotate_log(log_path, ratings)

    print(f"[DONE] {annotated}行に興味度を追記しました: {log_path}")


if __name__ == "__main__":
    main()

