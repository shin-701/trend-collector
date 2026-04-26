# 関連度評価と主要トレンド選出ルール

このファイルは `trend-collector` スキルが収集した記事を評価し、主要トレンドを選出するための手順書です。
興味度の判定基準は **`config.jsonc` の `interest_profile.rating_criteria`** で一元管理しています。

---

## 1. 興味度の判定

`config.jsonc` の `interest_profile.rating_criteria` を読み込み、全記事を ★★★ / ★★ / ★ の3段階で評価します。
キーワード完全一致ではなく、タイトルの**文脈・意図**を読み取って判定してください。

### 判定の優先順位（複数に当てはまる場合）
1. **`rating_criteria` との合致度**を最優先
2. **スコアの高さ**（ブクマ数・ポイント・ups）でタイを破る
3. **`learned_signals` に近いトピック**は +1ランク評価（★→★★、★★→★★★）

---

## 2. ログファイルへの興味度追記

評価が完了したら、各ログファイルの**全行末尾に興味度カラムを追記**します。
これにより `generate_table.py` がログを読む際に興味度列を取得できます。

### 追記フォーマット（ソース別）

**はてな** （元: `カテゴリ|ブクマ数|タイトル|URL`）
```
IT総合|194|タイトル|https://...|★★★
```

**Hacker News** （元: `ポイント|タイトル|HN_URL|元記事URL`）
```
199|タイトル|https://news.ycombinator.com/...|https://...|★★
```

**Reddit** （元: `カテゴリ|サブレッド|タイトル|ups|コメント数|URL`）
```
AI|r/ClaudeCode|タイトル|1749|27|https://...|★★★
```

### 追記の実行方法

評価が完了したら、AIは以下のフォーマットで全URLの興味度を **JSONファイル** として書き出します。
保存先は **`<log_dir>/YYYY-MM-DD_ratings.json`** に固定します（例: `11_ideas/logs/2026-04-26_ratings.json`）。

```json
{
    "https://example.com/article": "★★★",
    "https://news.ycombinator.com/item?id=12345": "★★",
    "https://www.reddit.com/r/ClaudeCode/...": "★"
}
```

その後、`scripts/annotate_ratings.py` を3ソース分それぞれ実行します。
ratings JSON のパスはスクリプトがログファイル名から自動解決するため、引数はログファイルのみでOKです。

```bash
python3 "${SKILL_DIR}/scripts/annotate_ratings.py" "<log_dir>/YYYY-MM-DD_hatena.txt"
python3 "${SKILL_DIR}/scripts/annotate_ratings.py" "<log_dir>/YYYY-MM-DD_hn.txt"
python3 "${SKILL_DIR}/scripts/annotate_ratings.py" "<log_dir>/YYYY-MM-DD_reddit.txt"
```

各コマンドが `[DONE] N行に興味度を追記しました` と出力したら完了です。


### 完了条件

ステップ2は以下がすべて満たされたときに完了とします：
- 3つのログファイル（`_hatena.txt`, `_hn.txt`, `_reddit.txt`）の全行末尾に `|★★★` / `|★★` / `|★` が追記されている
- 5〜7件の主要トレンド候補リストが確定している（次のステップ3でfetchに使用する）


---

## 3. 主要トレンドの選出

評価結果をもとに、全ソース横断で **5〜7件の主要トレンド** を選出します。

### 選出ルール
- 3ソースすべてから最低1件は含める（特定ソースに偏らない）
- Redditは**カテゴリ偏りを防ぐため1カテゴリ最大2件**に制限
- 興味プロファイルとの関連度が高い記事（★★★）を優先
- 同じテーマの記事が複数ソースにある場合は1件に統合
