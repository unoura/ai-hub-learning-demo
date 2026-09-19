# 手順1: Docker で動作する環境をつくる

## ゴール

軽量な IRIS(iris-community, AI Hub EAP)を Docker で起動し、以降の手順(暗号化・Wallet・エージェント)の
土台となる名前空間と AI Hub SDK が使える状態を作る。

## 方針(確定済み)

`../ai-hub-dev-template` の**軽量パターン**を踏襲する。

- **サービス構成**: 単一 `iris` サービス(FHIR / Web Gateway は使わない)
- **ベースイメージ**: `iris-community`(AI Hub EAP)。ライセンス不要
- **ソース配置**: リポジトリを `bind-mount`(`COPY` しない薄いイメージ)
- **公開ポート**: `1972`(スーパーサーバ / SQL / VS Code)、`52773`(管理ポータル / Web アプリ)
- **ビルド時プロビジョニング**:
  - `merge.cpf` — 名前空間・データベース・リソースの作成、`%Service_CallIn` 有効化(Embedded Python 用)
  - `iris.script` — ZPM/IPM 導入、開発用のパスワード無期限化など
  - `module.xml` — `zpm load` でサンプルクラスを取り込み
- **シークレット注入**: `docker-compose.yml` の `env_file: .env` から `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`

## 想定ファイル

```
Dockerfile              # iris-community ベース、requirements 導入、ビルド時プロビジョニング
docker-compose.yml      # iris サービス、env_file: .env、ポート 1972/52773、bind-mount
merge.cpf               # 名前空間 / DB / リソース(宣言的設定)
iris.script             # ZPM 導入・初期設定(命令的設定)
module.xml              # ZPM モジュール定義
requirements.txt        # fastmcp / mcp / pydantic など
.env.example            # OPENAI_API_KEY / ANTHROPIC_API_KEY のサンプル
```

## 実行手順(実装後に追記)

_（実装時に記載）_

## 確認方法(実装後に追記)

_（実装時に記載。例: `docker compose up -d --build` → 管理ポータル `http://localhost:52773` → `iris session`）_
