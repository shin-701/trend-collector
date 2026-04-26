---
name: Trend Collector
description: はてなブックマーク・Hacker News・Redditからトレンド記事を収集し、興味領域に基づいてフィルタリング・評価して保存する。「トレンド収集して」「今日のトレンドを教えて」「ネタ収集」「trend-collector」などのリクエストで必ず使用する。また「この記事面白い」「この記事興味ある」等で記事URLが渡された場合、興味シグナルの学習も行う。
---

# Trend Collector スキル

このスキルは、はてなブックマーク・Hacker News・Redditから最新のトレンド情報を収集し、`config.jsonc` の興味プロファイルに基づいて関連度を評価します。主要トレンドの選出と要約、結果の出力、および興味シグナルの学習を行います。

## When This Skill Activates

- 「トレンド収集して」「今日のトレンドを教えて」「ネタ収集」などトレンド関連のリクエスト
- 「trend-collector」と直接指定された場合
- 「この記事面白い」「この記事興味ある」等で記事URLが渡された場合（→ 興味学習モードへ）

---

## 実行手順

### ステップ 0. 設定とルールの読み込み
- `config.jsonc` の内容を確認し、興味プロファイルや出力先を把握してください。
- `rules/` ディレクトリ配下にあるルールファイル（`evaluation.md`, `summary.md`, `output.md`）を必ず読み込んで指示に従ってください。

### ステップ 1. トレンド情報の並列収集
以下の統合スクリプトを実行し、3つのソースからデータを並列で収集します。

```bash
SKILL_DIR="$(find . \( -path '*/skills/trend-collector' \) -type d | head -1)"
bash "${SKILL_DIR}/scripts/collect_all.sh"
```
（実行が完了すると、`config.jsonc` で指定したログディレクトリに3つのログファイルが出力されます）

### ステップ 2. 関連度評価・ログへの興味度追記・主要トレンド選出

`rules/evaluation.md` の手順と基準に従い実行してください。
（興味度の判定基準 → ログへの追記手順 → 主要トレンドの選出まで同ファイルに記載）


### ステップ 3. 主要トレンド記事のfetchと要約
選出した主要トレンド記事のURLを `scripts/fetch_article.sh` を用いて並列にfetchし、`rules/summary.md` に従って「日本語5行要約」を生成してください。
```bash
bash "${SKILL_DIR}/scripts/fetch_article.sh" "<記事URL>" 8000
```

### ステップ 4. 結果の出力

**4-a. AIによる主要トレンドセクションの出力**
「ネタ収集完了。」とメッセージを返してから、`rules/output.md` および `templates/output_format.md` のフォーマットに従い、Markdownファイルを作成してください。
このとき **「📌 今日の主要トレンド」セクション（5〜7件の要約）のみ** を書き込んで保存します。
全記事一覧テーブルは次の 4-b で自動生成するため、AIは出力しません。

**4-b. スクリプトによる全記事テーブルの追記**
以下のスクリプトを実行すると、95件以上の全記事を1件も漏らさず日本語翻訳・テーブル化してファイルに追記します。
```bash
python3 "${SKILL_DIR}/scripts/generate_table.py" "<4-a で作成したファイルの絶対パス>"
```
スクリプトが `[DONE] N件を...` と出力したら完了です。

---

## 興味学習（Interest Learning）
ユーザーが「この記事面白い」等でURLを渡してきた場合は、**トレンド収集は行わず**、`rules/learning.md` に従って興味シグナルの学習のみを実行してください。

---

## エラーハンドリング
スキル実行中にエラーが発生した場合、`templates/error_format.md` を読み込み、そのフォーマットに従って `.agents/skills/trend-collector/logs/YYYY-MM-DD_error.md` にエラーレポートを出力してください。