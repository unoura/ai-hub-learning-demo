# 手順1: Docker で動作する環境をつくる

## ゴール

軽量な IRIS(iris-community, AI Hub EAP)を Docker で起動し、以降の手順(暗号化・Wallet・エージェント)の
土台となる名前空間と AI Hub SDK が使える状態を作る。

## 方針(確定済み)

`../ai-hub-dev-template` の**軽量パターン**を踏襲する。

- **サービス構成**: 単一 `iris` サービス(FHIR / Web Gateway は使わない)
- **ベースイメージ**: `iris-community`(AI Hub EAP)。ライセンス不要
- **ソース配置**: リポジトリを `bind-mount`(`COPY` しない薄いイメージ)
- **公開ポート**: ホスト側は衝突しやすいため `.env` で上書き可能。既定は下表(コンテナ側は固定)。

  | 用途 | コンテナ側 | ホスト側(既定) | `.env` 変数 |
  |---|---|---|---|
  | スーパーサーバ(SQL / xDBC / VS Code) | 1972 | 51972 | `HOST_SUPERSERVER_PORT` |
  | 管理ポータル / Web | 52773 | 51773 | `HOST_WEB_PORT` |
- **ビルド時プロビジョニング**:
  - `merge.cpf` — 名前空間・データベース・リソースの作成、`%Service_CallIn` 有効化(Embedded Python 用)
  - `iris.script` — ZPM/IPM 導入、開発用のパスワード無期限化など
  - `module.xml` — `zpm load` でサンプルクラスを取り込み
- **シークレット注入**: `docker-compose.yml` の `env_file: .env` から `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`
- **Durable %SYS**: システムデータ(`IRISSECURITY` 含む)を名前付きボリューム `iris-durable` に永続化。
  - `ISC_DATA_DIRECTORY=/durable/iscdata` を指定し、`iris-durable:/durable` をマウント。
  - マウントポイント `/durable` は Dockerfile で **IRIS 実行ユーザ所有**として作成する(空の名前付きボリュームがこの所有権を引き継ぎ、`iscdata` を作成できる)。所有権を設定しないと `ERROR #5001: Cannot create target: /durable/iscdata/` で起動失敗する。
  - ユーザ/グループはハードコードせず `${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP}` 変数で参照する(参照リポジトリと同じ idiom。移植性が高い):
    ```dockerfile
    USER root
    RUN mkdir -p /durable && chown -R ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} /durable
    USER ${ISC_PACKAGE_MGRUSER}
    ```
  - 手順2の暗号化設定が `down`/`up` 後も残るため重要。

## 作成したファイル

```
Dockerfile          # iris-community(AI Hub EAP)ベース。requirements 導入 + ビルド時プロビジョニング
docker-compose.yml  # iris サービス、env_file(.env, 任意)、ホストポート上書き可、リポジトリを bind-mount
merge.cpf           # 名前空間 DEMO / DB(DEMO_DATA・DEMO_CODE)/ リソース(宣言的設定)
iris.script         # パスワード無期限化・ZPM 導入・Call-In 有効化(命令的設定)
requirements.txt    # fastmcp / mcp / pydantic など(Embedded Python 用)
.env.example        # OPENAI_API_KEY / ANTHROPIC_API_KEY のサンプル(.env はコミットしない)
.dockerignore       # .git / local / .env などをビルドコンテキストから除外
```

- 名前空間は **`DEMO`**、Embedded Python 用に `%Service_CallIn` を有効化。
- 手順1では最小構成とし、MCP 用ポート `8080` やサンプルクラスの `zpm load` は後の手順で追加する。

## 実行手順

```bash
# (任意)API キーを使う場合のみ。手順1では未設定でも起動できる
cp .env.example .env   # 値を編集

# ビルド & 起動
docker compose up -d --build
```

> **前提**: ベースイメージ(iris-community AI Hub EAP)がローカルに `docker load` 済みであること。
> イメージ名が異なる場合は `Dockerfile` の `ARG IMAGE` を書き換える。

> **注意(Durable %SYS の再プロビジョニング)**: durable ボリュームが既に存在すると、初回起動時のコピーが
> 走らないため、イメージを再ビルドしても `iris.script` の**ビルド時設定は反映されない**(`merge.cpf` の
> 名前空間/DB 作成は起動毎の再マージで冪等に適用される)。ビルド時設定をやり直したい場合は
> `docker compose down -v` でボリュームごと削除してから `up --build` する。

## 確認方法

```bash
# コンテナ状態
docker compose ps

# 管理ポータル(SuperUser / SYS)。ホスト側ポート既定 51773
open http://localhost:51773/csp/sys/UtilHome.csp

# IRIS セッション。DEMO 名前空間が作成されていることを確認
docker compose exec -it iris iris session iris -U DEMO
# > write $namespace   // → "DEMO"
```

### 検証結果(実施済み)

| 項目 | 期待 | 結果 |
|---|---|---|
| 名前空間 | `DEMO` | ✓ |
| SystemMode | `AI Hub EAP` | ✓ |
| `%AI.Agent`(手順4用) | 存在 | ✓ |
| `%Wallet.Collection`(手順3用) | 存在 | ✓ |
| ポートマッピング | `51972→1972` / `51773→52773` | ✓ |
| Durable %SYS | mgr が `/durable/iscdata/mgr/` | ✓ |
| 永続性 | `down`/`up` 後もグローバル/データ保持 | ✓ |

> 使用イメージ: `docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2026.3.0AI.136.0`
> (arm64 版を `docker load` 済み。`Dockerfile` の `ARG IMAGE` と一致)

**ステータス: 手順1 完了 ✅**
