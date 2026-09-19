#!/bin/bash
# LLM API キーを IRIS Secure Wallet + ConfigStore に「手動で」登録する。
# キーは .env にも環境変数にも置かない。入力は非表示(read -s)で、値は 0600 の一時ファイル
# 経由で ObjectScript に渡し、直後に削除する。argv・シェル履歴・プロセス環境・docker inspect の
# いずれにも平文が残らない(一時ファイルはコンテナの /tmp に一瞬だけ存在)。
#
# 使い方(コンテナ内で対話実行):
#   docker compose exec -it iris bash /home/irisowner/dev/docker/register-key.sh openai
#   docker compose exec -it iris bash /home/irisowner/dev/docker/register-key.sh anthropic claude-3-5-sonnet-latest
#
# 登録内容(正準パターン):
#   - RBAC リソース DemoWalletUse / DemoWalletEdit と コレクション AISecrets(無ければ作成)
#   - Wallet シークレット AISecrets.<Name> = {"Secret":{"key":"<入力キー>"}}
#   - ConfigStore 設定 AI.LLM.<provider> = {... "api_key":"secret://AISecrets.<Name>#key"}(参照だけ)
# 既存は上書き登録(再実行で差し替え可能)。読み取りには %Admin_Wallet が必要(%SYS は %All 保有)。
set -u

prov="${1:-}"
case "$prov" in
  openai)    Name="OpenAI";    defmodel="gpt-4o" ;;
  anthropic) Name="Anthropic"; defmodel="claude-3-5-sonnet-latest" ;;
  *) echo "usage: $0 <openai|anthropic> [model]"; exit 1 ;;
esac
model="${2:-$defmodel}"

# API キーを非表示で入力(argv・履歴に残らない)。
printf 'Enter %s API key (入力は表示されません): ' "$Name" >&2
read -r -s KEY
echo >&2
if [ -z "$KEY" ]; then echo "空のキーです。中止しました。" >&2; exit 1; fi

# 0600 の一時ファイルへ書き出し(printf は組み込みなので argv に出ない)。値は改行なしで格納。
tmp="$(mktemp /tmp/demo-key.XXXXXX)"
chmod 600 "$tmp"
printf '%s' "$KEY" > "$tmp"
unset KEY

# 非シークレットのパラメータとファイルパスのみ環境変数で ObjectScript へ渡す(キー値は渡さない)。
export DEMO_SID="AISecrets.${Name}" DEMO_CFG="${prov}" DEMO_PROV="${prov}" DEMO_MODEL="${model}" DEMO_KEYFILE="$tmp"

iris session IRIS -U %SYS <<'OBJSCRIPT'
 set sid=$system.Util.GetEnviron("DEMO_SID"),cfg=$system.Util.GetEnviron("DEMO_CFG")
 set prov=$system.Util.GetEnviron("DEMO_PROV"),model=$system.Util.GetEnviron("DEMO_MODEL"),kf=$system.Util.GetEnviron("DEMO_KEYFILE")
 set s=##class(%Stream.FileCharacter).%New()  do s.LinkToFile(kf)  set k=s.Read(100000)
 do:'##class(Security.Resources).Exists("DemoWalletUse") ##class(Security.Resources).Create("DemoWalletUse","Demo wallet use resource","")
 do:'##class(Security.Resources).Exists("DemoWalletEdit") ##class(Security.Resources).Create("DemoWalletEdit","Demo wallet edit resource","")
 do:'##class(%Wallet.Collection).Exists("AISecrets") ##class(%Wallet.Collection).Create("AISecrets",{"UseResource":"DemoWalletUse","EditResource":"DemoWalletEdit"})
 do:##class(%Wallet.KeyValue).%ExistsId(sid) ##class(%Wallet.KeyValue).%DeleteId(sid)
 set sc=##class(%Wallet.KeyValue).Create(sid,{"Usage":"CUSTOM","Secret":{"key":(k)}})
 if 'sc { write "[wallet] Wallet 格納失敗: ",$system.Status.GetErrorText(sc),! halt }
 do:##class(%ConfigStore.Configuration).Exists("AI.LLM."_cfg) ##class(%ConfigStore.Configuration).Delete("AI.LLM."_cfg)
 set sc=##class(%ConfigStore.Configuration).Create("AI","LLM","",cfg,{"model_provider":(prov),"model":(model),"api_key":("secret://"_sid_"#key")},"","","","",1,0)
 if 'sc { write "[wallet] ConfigStore 作成失敗: ",$system.Status.GetErrorText(sc),! halt }
 write "[wallet] ",sid," / AI.LLM.",cfg," 登録完了 (model=",model,", len=",$length(k),")",!
 halt
OBJSCRIPT
rc=$?

# 一時ファイルを確実に削除。
rm -f "$tmp"
exit $rc
