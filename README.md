# bundler_plugin_cooldown

公開から一定期間（cooldown）が経過していない gem version の install を抑止する Bundler プラグイン。maintainer アカウントの乗っ取り等で悪意あるコードが publish された場合に、推移依存経由で即時に取り込まれる事故を緩和することを目的とする。

> ⚠️ **本プラグインは PoC (Proof of Concept) 実装である。動作保証は無く、仕様および挙動は予告なく変更され得る。本番環境や CI への組み込みは自己責任で行うこと。**

## 動作

- `before-install-all` フックで `Bundler.definition.resolve` を走査する
- rubygems.org 由来の各 gem について `https://rubygems.org/api/v1/versions/<gem>.json` を呼び出し、対象 `version` および `platform` の `created_at` を取得する
- 公開日に `COOLDOWN_DAYS` を加算した日付が今日より未来であれば違反として記録する
- 1 件以上の違反があれば `Bundler::InstallError` を発行して install を中断する
- path / git ソースの gem、および bundler 自身は対象外とする

## インストール

CLI から install する場合:

```sh
bundle plugin install bundler_plugin_cooldown \
  --git https://github.com/kysd/bundler_plugin_cooldown
```

Gemfile で宣言する場合:

```ruby
plugin "bundler_plugin_cooldown",
       git: "https://github.com/kysd/bundler_plugin_cooldown"
```

Gemfile 経由の場合、**初回の `bundle install` ではフックが発火しない**（Bundler のプラグイン読み込み機構の制約）。確実に保護を効かせるには事前に `bundle plugin install` を実行する必要がある。

## 設定

`lib/bundler_plugin_cooldown.rb` の定数を直接編集する。

| 定数 | 既定 | 意味 |
|---|---|---|
| `COOLDOWN_DAYS` | `7` | 公開からこの日数以内の gem の install を拒否する |
| `REQUEST_DELAY` | `0.15` | API リクエスト間のスリープ秒数（rubygems.org の上限 10 req/s に対する余裕分）|

## 制限事項

- API 結果のキャッシュは持たない。`bundle install` のたびに API を呼ぶ
- ネットワーク不通や API エラー時は当該 gem を警告のみで素通りさせる（fail-open）
- path / git ソースの gem はチェック対象外
- rubygems.org から版が `yank` された直後は判定が不安定になり得る
