#!/bin/bash
# LLM API キーを IRIS Secure Wallet + ConfigStore に「手動で」登録する。
# キーは .env にも環境変数にも置かない。入力は非表示(read -s)で、値は 0600 の一時ファイル
# 経由で ObjectScript に渡し、直後に削除する。argv・シェル履歴・プロセス環境・docker inspect の
# いずれにも平文が残らない(一時ファイルはコンテナの /tmp に一瞬だけ存在)。
#
# 使い方(コンテナ内で対話実行):
#   docker compose exec -it iris bash /home/irisowner/dev/docker/register-key.sh openai
#   docker compose exec -it iris bash /home/irisowner/dev/docker/register-key.sh anthropic claude-sonnet-5
#   docker compose exec -it iris bash /home/irisowner/dev/docker/register-key.sh bedrock
#
# どれか1つ登録すればよい(エージェントは登録済みのものを自動採用する: Demo.Agent.Base)。
#
# 登録内容(正準パターン):
#   - RBAC リソース DemoWalletUse / DemoWalletEdit と コレクション AISecrets(無ければ作成)
#   - Wallet シークレット AISecrets.<Name> = {"Secret":{"key":"<入力キー / bearer token>"}}
#   - ConfigStore 設定 AI.LLM.<provider> = {... "api_key":"secret://AISecrets.<Name>#key"}(参照だけ)
#     bedrock は非機密の "region" も ConfigStore に同梱(リージョンは秘密ではないので Wallet には入れない)。
# 既存は上書き登録(再実行で差し替え可能)。読み取りには %Admin_Wallet が必要(%SYS は %All 保有)。
set -u

prov="${1:-}"
KeyLabel="API key"
case "$prov" in
  openai)    Name="OpenAI";    defmodel="gpt-5.6" ;;
  anthropic) Name="Anthropic"; defmodel="claude-sonnet-5" ;;
  # Bedrock は bearer token 認証。model はクロスリージョン推論プロファイル ID を既定にする。
  bedrock)   Name="Bedrock";   defmodel="us.anthropic.claude-sonnet-5"; KeyLabel="bearer token" ;;
  *) echo "usage: $0 <openai|anthropic|bedrock> [model]"; exit 1 ;;
esac
model="${2:-$defmodel}"

# Bedrock はリージョン(非機密)も対話で入力(表示あり)。既定は us-east-1。
region=""
if [ "$prov" = "bedrock" ]; then
  printf 'Enter AWS region [us-east-1]: ' >&2
  read -r region
  region="${region:-us-east-1}"
fi

# キー/トークンを非表示で入力(argv・履歴に残らない)。
printf 'Enter %s %s (入力は表示されません): ' "$Name" "$KeyLabel" >&2
read -r -s KEY
echo >&2
if [ -z "$KEY" ]; then echo "空の値です。中止しました。" >&2; exit 1; fi

# 0600 の一時ファイルへ書き出し(printf は組み込みなので argv に出ない)。値は改行なしで格納。
tmp="$(mktemp /tmp/demo-key.XXXXXX)"
chmod 600 "$tmp"
printf '%s' "$KEY" > "$tmp"
unset KEY

# 非シークレットのパラメータとファイルパスのみ環境変数で ObjectScript へ渡す(キー値は渡さない)。
# OpenAI の gpt-5.x(推論モデル)は、Chat Completions でツールを使うとき reasoning_effort=none が必要
# (付けないと "Function tools with reasoning_effort are not supported" で失敗する)。リクエストへの追加パラメータ
# (extra_params)として ConfigStore に保存し、エージェントがセッション作成時に渡す。
reasoning=""
if [ "$prov" = "openai" ]; then
  case "$model" in gpt-5.[1-9]*) reasoning="none" ;; esac
fi

export DEMO_SID="AISecrets.${Name}" DEMO_CFG="${prov}" DEMO_PROV="${prov}" DEMO_MODEL="${model}" DEMO_KEYFILE="$tmp" DEMO_REGION="$region" DEMO_REASONING="$reasoning"

iris session IRIS -U %SYS <<'OBJSCRIPT'
 set sid=$system.Util.GetEnviron("DEMO_SID"),cfg=$system.Util.GetEnviron("DEMO_CFG")
 set prov=$system.Util.GetEnviron("DEMO_PROV"),model=$system.Util.GetEnviron("DEMO_MODEL"),kf=$system.Util.GetEnviron("DEMO_KEYFILE"),region=$system.Util.GetEnviron("DEMO_REGION")
 set s=##class(%Stream.FileCharacter).%New()  do s.LinkToFile(kf)  set k=s.Read(100000)
 do:'##class(Security.Resources).Exists("DemoWalletUse") ##class(Security.Resources).Create("DemoWalletUse","Demo wallet use resource","")
 do:'##class(Security.Resources).Exists("DemoWalletEdit") ##class(Security.Resources).Create("DemoWalletEdit","Demo wallet edit resource","")
 do:'##class(%Wallet.Collection).Exists("AISecrets") ##class(%Wallet.Collection).Create("AISecrets",{"UseResource":"DemoWalletUse","EditResource":"DemoWalletEdit"})
 do:##class(%Wallet.KeyValue).%ExistsId(sid) ##class(%Wallet.KeyValue).%DeleteId(sid)
 set sc=##class(%Wallet.KeyValue).Create(sid,{"Usage":"CUSTOM","Secret":{"key":(k)}})
 if 'sc { write "[wallet] Wallet 格納失敗: ",$system.Status.GetErrorText(sc),! halt }
 set cfgObj={"model_provider":(prov),"model":(model),"api_key":("secret://"_sid_"#key")}
 do:region'="" cfgObj.%Set("region",region)  // 非機密。bedrock のみ設定。
 set reasoning=$system.Util.GetEnviron("DEMO_REASONING")
 do:reasoning'="" cfgObj.%Set("extra_params",{"reasoning_effort":(reasoning)})  // 非機密。openai gpt-5.x のみ。
 do:##class(%ConfigStore.Configuration).Exists("AI.LLM."_cfg) ##class(%ConfigStore.Configuration).Delete("AI.LLM."_cfg)
 set sc=##class(%ConfigStore.Configuration).Create("AI","LLM","",cfg,cfgObj,"","","","",1,0)
 if 'sc { write "[wallet] ConfigStore 作成失敗: ",$system.Status.GetErrorText(sc),! halt }
 write "[wallet] ",sid," / AI.LLM.",cfg," 登録完了 (model=",model,$select(region'="":", region="_region,1:""),$select(reasoning'="":", reasoning_effort="_reasoning,1:""),", len=",$length(k),")",!
 halt
OBJSCRIPT
rc=$?

# 一時ファイルを確実に削除。
rm -f "$tmp"
exit $rc
