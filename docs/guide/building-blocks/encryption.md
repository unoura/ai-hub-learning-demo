# 手順2: IRISSECURITY を暗号化する

IRIS のセキュリティデータベース `IRISSECURITY` を暗号化し、そこに格納される認証情報・Wallet の
シークレットを**保存時(at-rest)で保護**します。手順3で Wallet に入れる API キーが暗号化されます。

> 設計・判断根拠(なぜこの機構か、本番運用との違い)は
> [../design/02-irissecurity-encryption.md](../design/02-irissecurity-encryption.md) を参照。

## 仕組み(概要)

初回起動時に、コンテナが自動で以下を実行します(`docker/first-boot-encrypt.sh`):

1. `%SYSTEM.Encryption` で **Auto キー**(無人起動時アクティベーション専用の暗号化キー)を生成。
   解錠資格情報は IRIS が自動生成・内部保存するため、パスワードを `.env` に置く必要はありません。
2. IRISSECURITY を暗号化対象として**起動時アクティベーション**に構成。
3. IRISSECURITY は稼働中マウント済みのためその場では暗号化できないので、**IRIS を1回だけ再起動**して
   起動シーケンス中に暗号化を適用。
4. `EncryptedDB=1` を確認し、センチネル(`/durable/.demo-irissecurity-encrypted`)を作成。

センチネルにより、2回目以降の起動では再暗号化されません。暗号化キーとこの構成は Durable %SYS
(`/durable`)に永続化されるので、`down`/`up` をまたいでも IRISSECURITY は暗号化されたままです。

## 手順

手順1の環境で `docker compose up -d --build` を実行すれば、初回起動時に自動で暗号化まで完了します。
特別な操作は不要です。進行はログで確認できます。

```bash
docker compose up -d --build
docker compose logs -f iris | grep "\[demo\]"
```

期待するログ:

```
[demo] IRIS 準備完了。初回初期化(IRISSECURITY 暗号化)を実行します...
[demo] 暗号化キーを生成し、起動時アクティベーションを構成します...
[demo] 設定完了。IRISSECURITY を暗号化するため IRIS を1回再起動します...
[demo] IRISSECURITY の暗号化を確認しました(EncryptedDB=1)。センチネルを作成しました。
```

## 動作確認

`iris-agentic-dev` で IRISSECURITY の暗号化状態を確認します(`EncryptedDB=1` なら暗号化済み)。

```bash
IRIS_USERNAME=_SYSTEM IRIS_PASSWORD=SYS iris-agentic-dev exec -n %SYS \
  'set db=##class(SYS.Database).%OpenId("/durable/iscdata/mgr/irissecurity/") write "enc=",db.EncryptedDB'
# → enc=1
```

`down`/`up` をまたいでも暗号化が維持されること:

```bash
docker compose down          # ボリュームは残す(-v を付けない)
docker compose up -d
# 起動ログに「Using encryption key file ... / Activating encryption key ...」が出て、
# first-boot は「IRISSECURITY は暗号化済み(センチネルあり)。スキップします。」となる。
```

> **やり直したいとき**: `docker compose down -v` で永続ボリュームを削除してから
> `docker compose up -d --build` すると、まっさらな状態から暗号化を再実行します。
