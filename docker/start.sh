#!/bin/bash
# コンテナのエントリーポイント。
# 参照リポジトリ(aihub-demo)と同じ idiom:
#   バックグラウンドで「IRIS の起動を待って初回初期化」を走らせ、
#   前景では tini 経由で本来の /iris-main を exec する(引数は "$@" で受け渡す)。
#
# ベースイメージの既定 ENTRYPOINT は ["/tini","--","/iris-main"]。
# tini による PID1 のシグナル処理・ゾンビ回収を維持するため、そのまま exec する。
set -e

(
  echo "[demo] IRIS の起動を待っています..."
  until iris session IRIS -U %SYS "write 1 halt" >/dev/null 2>&1; do
    sleep 2
  done
  echo "[demo] IRIS 準備完了。初回初期化(IRISSECURITY 暗号化)を実行します..."
  bash /home/irisowner/dev/docker/first-boot-encrypt.sh
  # 手順3(Wallet への API キー登録)は自動化しない。
  # キーは環境変数/.env に出さず、手動で docker/register-key.sh を実行して登録する。
) &

echo "[demo] Starting IRIS..."
exec /tini -- /iris-main "$@"
