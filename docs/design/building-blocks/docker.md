# 設計: 手順1 Docker 環境

## ねらい

軽量な IRIS を Docker で起動し、以降の手順(暗号化・Wallet・エージェント)の土台となる
名前空間と AI Hub SDK が使える状態を作る。

## 方針と判断根拠

`ai-hub-dev-template` の**軽量パターン**を踏襲する。

| 決定 | 内容 | 根拠 |
|---|---|---|
| ベースイメージ | `iris-community`(AI Hub EAP) | ライセンス不要・FHIR なしで軽量。暗号化/Wallet/エージェントの学習に十分 |
| サービス構成 | 単一 `iris`(Web Gateway なし) | 学習用途では PWS(52773)で足りる |
| ソース配置 | リポジトリを bind-mount(`COPY` しない) | イメージが薄くなり、再ビルド無しでソースを直せる |
| 名前空間 | `DEMO`(DB は `DEMO_DATA` / `DEMO_CODE`) | 記事で分かりやすい命名 |
| ポート | ホスト側を `.env` で上書き可(既定 51972 / 51773) | 他コンテナと衝突しやすいため。コンテナ側 1972/52773 は固定 |
| シークレット注入 | `env_file: .env`(`required: false`) | `.env` 未作成でも起動できるようにする |
| 最小構成 | MCP 用 8080・`module.xml` の `zpm load` は後回し | 手順1は環境の土台に集中。ツール/エージェントは手順4で追加 |

## ビルド時プロビジョニング

- `merge.cpf` — 名前空間・DB・リソース作成、`%Service_CallIn` 有効化(Embedded Python 用)。
- `iris.script` — ZPM/IPM 導入、開発用のパスワード無期限化。
- (将来)`module.xml` — `zpm load` でサンプルクラスを取り込み(手順4)。

## Durable %SYS

- **なぜ**: 手順2で行う `IRISSECURITY` 暗号化などのシステム設定を、`down`/`up` 後も保持するため。
- **どう**: `ISC_DATA_DIRECTORY=/durable/iscdata` + 名前付きボリューム `iris-durable:/durable`。
- **所有権**: マウントポイント `/durable` を Dockerfile で IRIS 実行ユーザ所有として作成する。
  空の名前付きボリュームはこのディレクトリの所有権を引き継ぐため `iscdata` を作成できる。
  ユーザ/グループはハードコードせず、参照リポジトリと同じ idiom で `ISC_PACKAGE_*` を使う:
  ```dockerfile
  USER root
  RUN mkdir -p /durable && chown -R ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} /durable
  USER ${ISC_PACKAGE_MGRUSER}
  ```
- **注意**: durable ボリュームが既にあると初回コピーが走らず、再ビルドしても `iris.script` の
  ビルド時設定は反映されない(`merge.cpf` の名前空間/DB 作成は起動毎の再マージで冪等に適用)。
  やり直すには `docker compose down -v`。
