#!/bin/bash
# 初回起動時のみ実行する IRISSECURITY 暗号化(センチネルで冪等化)。
# docker/start.sh が「IRIS 起動完了」を確認した後に呼ぶ(この時点で IRIS は起動済み)。
#
# 【機構】(実機で確認済み)
#   - %SYSTEM.Encryption.CreateAutoEncryptionKeyOnly で「無人起動時アクティベーション」専用の
#     Auto キーを生成する。username/password は IRIS が自動生成し内部保存するため、
#     暗号化パスワードを .env 等に置かずに無人起動できる。
#   - ActivateAutoEncryptionKey(...,irissecurity=1) で起動時アクティベーションを構成する。
#   - IRISSECURITY は起動中マウント済みのため即時暗号化されない。1回の再起動で、
#     起動シーケンス中(mount 前)にキーがアクティベートされ IRISSECURITY が暗号化される。
#     → ここで制御された iris stop/start を1回だけ行い、単一の `up` で暗号化を完了させる。
#
# 【デモとしての簡易的措置】鍵ファイルをデータと同じ永続ボリューム(/durable)に置き、解錠資格情報を
#   インスタンス内部に保存する(無人起動のため)。本番では鍵をデータと分離し、KMIP サーバ
#   (Security.KMIPServer)やクラウド KMS(KMSCreateEncryptionKey)で管理すること。
#   → docs/design/02 参照。
#
# 失敗時はセンチネルを作らず、次回起動で再試行する。
set -u

SENTINEL=/durable/.demo-irissecurity-encrypted
CFGLOG=/tmp/demo-encrypt.log
CHKLOG=/tmp/demo-enccheck.log

if [ -f "$SENTINEL" ]; then
  echo "[demo] IRISSECURITY は暗号化済み(センチネルあり)。スキップします。"
  exit 0
fi

# 安全ガード: センチネルが無くても IRISSECURITY が既に暗号化されている場合がある
# (前回 create+activate+restart は成功したが検証/センチネル作成の前に止まった等)。
# その状態で鍵ファイルを作り直すと既存の暗号化 IRISSECURITY を復号できず起動不能になるため、
# 既に暗号化済みなら鍵に一切触れず、センチネルだけ作成して終了する。
iris session IRIS -U %SYS <<'OBJSCRIPT' > "$CHKLOG" 2>&1
 set db=##class(SYS.Database).%OpenId("/durable/iscdata/mgr/irissecurity/")
 write "ENCSTATUS:",$select($isobject(db):db.EncryptedDB,1:"?"),!
 halt
OBJSCRIPT
if grep -q "ENCSTATUS:1" "$CHKLOG"; then
  echo "[demo] IRISSECURITY は既に暗号化済み(センチネル欠落を自己修復)。鍵には触れずセンチネルを作成します。"
  touch "$SENTINEL"
  exit 0
fi

echo "[demo] 暗号化キーを生成し、起動時アクティベーションを構成します..."
# create + activate は同一セッションで完結させる(自動生成された username/password を
# ObjectScript 変数のまま Activate に渡し、ログには出さない)。
# ここに来る時点で IRISSECURITY は未暗号化なので、残骸の鍵ファイルは安全に作り直せる。
iris session IRIS -U %SYS <<'OBJSCRIPT' | tee "$CFGLOG"
 set keyfile="/durable/iscdata/mgr/DEMO.key"
 if ##class(%File).Exists(keyfile) { do ##class(%File).Delete(keyfile) }
 set sc=##class(%SYSTEM.Encryption).CreateAutoEncryptionKeyOnly(keyfile,256,"DEMO IRISSECURITY key",.user,.pwd)
 if '$system.Status.IsOK(sc) { write !,"ENCRYPT-FAILED(create): ",$system.Status.GetErrorText(sc),! halt }
 set sc=##class(%SYSTEM.Encryption).ActivateAutoEncryptionKey(keyfile,user,pwd,0,0,0,1)
 if '$system.Status.IsOK(sc) { write !,"ENCRYPT-FAILED(activate): ",$system.Status.GetErrorText(sc),! halt }
 write !,"ENCRYPT-CONFIGURED",!
 halt
OBJSCRIPT

if ! grep -q "ENCRYPT-CONFIGURED" "$CFGLOG"; then
  echo "[demo] 暗号化設定に失敗しました。センチネル未作成(次回起動で再試行)。"
  echo "[demo] コンテナは稼働継続します。'docker exec -it ai-hub-learning-demo iris session IRIS -U %SYS' で調査してください。"
  exit 0
fi

# IRISSECURITY を暗号化するため、制御された再起動を1回だけ行う。
# (実機確認済み: iris-main を PID1 とするコンテナは内部 iris stop/start で終了しない)
echo "[demo] 設定完了。IRISSECURITY を暗号化するため IRIS を1回再起動します..."
iris stop IRIS quietly 2>&1 | tail -1 || true
iris start IRIS quietly 2>&1 | tail -1 || true
echo "[demo] 再起動後の IRIS 起動を待っています..."
until iris session IRIS -U %SYS "write 1 halt" >/dev/null 2>&1; do sleep 2; done

# 暗号化状態を検証(EncryptedDB=1 を確認)。
# 冒頭ガードと同じ heredoc 形式で、ネストした引用符のエスケープ不具合を避ける。
iris session IRIS -U %SYS <<'OBJSCRIPT' > "$CHKLOG" 2>&1
 set db=##class(SYS.Database).%OpenId("/durable/iscdata/mgr/irissecurity/")
 write "ENCSTATUS:",$select($isobject(db):db.EncryptedDB,1:"?"),!
 halt
OBJSCRIPT
if grep -q "ENCSTATUS:1" "$CHKLOG"; then
  touch "$SENTINEL"
  echo "[demo] IRISSECURITY の暗号化を確認しました(EncryptedDB=1)。センチネルを作成しました。"
else
  echo "[demo] 警告: 再起動後も EncryptedDB=1 を確認できませんでした。センチネル未作成(次回起動で再適用)。"
fi
exit 0
