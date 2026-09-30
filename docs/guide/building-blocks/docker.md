# 構成要素: Docker で動作する環境をつくる

軽量な IRIS(iris-community, AI Hub EAP)を Docker で起動し、以降の構成要素の土台となる
名前空間 `DEMO` と AI Hub SDK が使える状態を作ります。データは Durable %SYS で永続化します。

## 前提

- Docker が動作していること(Windows は WSL2 前提。Docker Desktop の WSL2 バックエンドを使い、WSL2 のシェルでリポジトリを clone・実行する)。
- ベースイメージ(iris-community AI Hub EAP)がローカルに `docker load` 済みであること
  (入手とロードの手順は [README の事前準備](../../../README.md#事前準備iris-イメージのロード))。
  イメージ名が異なる場合は `Dockerfile` の `ARG IMAGE` を書き換えます。

## 起動

```bash
# (任意)API キーを使う場合のみ。この構成要素では未設定でも起動できます
cp .env.example .env   # 値を編集

# ビルド & 起動
docker compose up -d --build
```

ホスト側ポートは衝突しやすいため `.env` で変更できます(コンテナ側は固定)。

| 用途 | コンテナ側 | ホスト側(既定) | `.env` 変数 |
|---|---|---|---|
| スーパーサーバ(SQL / xDBC / VS Code) | 1972 | 51972 | `HOST_SUPERSERVER_PORT` |
| 管理ポータル / Web | 52773 | 51773 | `HOST_WEB_PORT` |

## 動作確認

```bash
# コンテナ状態
docker compose ps

# 管理ポータル(SuperUser / SYS)。既定ホストポート 51773
open http://localhost:51773/csp/sys/UtilHome.csp

# IRIS セッション。DEMO 名前空間が作成されていることを確認
docker compose exec -it iris iris session iris -U DEMO
# > write $namespace   //  → "DEMO"
```

## データの永続化(Durable %SYS)

システムデータ(`IRISSECURITY` を含む)は名前付きボリューム `iris-durable` に保存され、
`docker compose down` / `up` をまたいで保持されます。

> ビルド時設定(`iris.script`)をやり直したい場合は、`docker compose down -v` で
> ボリュームごと削除してから `up --build` してください。
