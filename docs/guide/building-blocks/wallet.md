# 手順3: ウォレットで OpenAI / Claude / Bedrock のキーを受け渡す

OpenAI・Claude(Anthropic)・Amazon Bedrock の API キー(Bedrock は bearer token)を
IRIS の **Secure Wallet** に格納し、アプリからは
**ConfigStore の参照だけ**で扱います。Wallet の実体は `IRISSECURITY`
データベース(`^WALLET`)なので、手順2で暗号化済みのため、キーは**保存時(at-rest)で暗号化**
されて保存されます。ソースコードや設定に平文の API キーは一切残りません。

> Secure Wallet は IRIS 2025.3 で導入、2026.1(EM)で一般提供された機能です。
> 設計・判断根拠(なぜこの構成か、本番運用との違い)は
> [../design/03-wallet-api-keys.md](../design/03-wallet-api-keys.md) を参照。

## 方針: キーは「手動登録」のみ(環境変数に出さない)

このデモでは、API キーを **`.env` にも環境変数にも書きません**。代わりに、対話ヘルパ
`docker/register-key.sh` を**手動で1回だけ実行**して Wallet に登録します。こうすると、
平文キーが `.env` / 環境変数 / `docker inspect` / シェル履歴のいずれにも残りません。

> キーを環境変数経由で渡すと、`docker inspect` やプロセス一覧(`/proc/<pid>/environ`)から
> 平文が読めてしまいます。手動登録はそれを避けるための選択です。

ヘルパの仕組み(平文をどこにも残さない):

1. キー入力は**非表示**(`read -s`)。→ シェル履歴・画面に残らない。
2. 入力値は **0600 の一時ファイル**に書き、ObjectScript がそこから読む。→ **argv・環境変数に出ない**
   (環境変数で渡すのはファイルパスと非機密パラメータだけ)。
3. 登録後、一時ファイルは**即削除**。→ 平文はコンテナの `/tmp` に一瞬だけ。

## 登録内容(正準パターン)

ヘルパは以下を作成します(「無ければ作る」/ 既存キーは上書き)。

1. RBAC リソース(`DemoWalletUse` / `DemoWalletEdit`)と Wallet コレクション `AISecrets`。
2. API キーを Wallet に**オブジェクトで格納**(`AISecrets.OpenAI` / `AISecrets.Anthropic` /
   `AISecrets.Bedrock`、`{"Secret":{"key":"..."}}`)。
3. ConfigStore に設定を作成(`AI.LLM.openai` / `AI.LLM.anthropic` / `AI.LLM.bedrock`)。ここには
   平文でなく `"api_key":"secret://AISecrets.OpenAI#key"` という**参照だけ**を保持。Bedrock は
   非機密の `"region"` も同梱します(リージョンは秘密ではないので Wallet には入れません)。

> **なぜ2層(Wallet + ConfigStore)か**: Wallet が機密の実体(暗号化 IRISSECURITY)、
> ConfigStore は「どのプロバイダ・モデルで、キーはどの Wallet 参照か」という**設定と参照**を持ちます。
> アプリ(手順4のエージェント)は `AI.LLM.*` と**名前で参照するだけ**で、平文キーには触れません。

## 手順

コンテナを起動しておき(手順1・2)、`docker compose exec -it` で**対話実行**します。

```bash
# OpenAI キーを登録(モデルは任意。既定 gpt-5.6)
docker compose exec -it iris bash /home/irisowner/dev/docker/register-key.sh openai

# Claude(Anthropic)キーを登録(モデルは任意。既定 claude-sonnet-5)
docker compose exec -it iris bash /home/irisowner/dev/docker/register-key.sh anthropic

# Amazon Bedrock(bearer token)を登録(リージョンも対話入力。既定 us-east-1)
docker compose exec -it iris bash /home/irisowner/dev/docker/register-key.sh bedrock
```

`Enter OpenAI API key (入力は表示されません):` と表示されたら、キーを貼り付けて Enter
(**入力は画面に出ません**)。成功すると次のように出ます:

```
[wallet] AISecrets.OpenAI / AI.LLM.openai 登録完了 (model=gpt-5.6, len=164)
```

- `-it`(TTY)必須です。非表示入力のために対話端末が要ります。
- **どれか1つ登録すれば OK**(手順4のエージェントは登録済みのものを自動採用します)。
- 貼り付け時に**先頭1文字が欠ける**端末があります。`len=` が想定より短い/`sk-` 以外で
  始まる場合は再実行してください(上書き登録なのでやり直し自由)。
- **Bedrock**: 認証は API キーでなく **bearer token**。モデルは**クロスリージョン推論プロファイル ID**
  (既定 `us.anthropic.claude-sonnet-5` のように `us.` 等の接頭辞付き)を使う点に注意。
  素のモデル ID だと `on-demand throughput isn't supported` になることがあります。
  リージョン(既定 `us-east-1`)は秘密でないため ConfigStore に平文で入ります。

> API キーは `.env` にも環境変数にも書きません。`.env.example` にキー欄はありません。

## 動作確認

Wallet に暗号化保存され、ConfigStore は参照だけを持ち、`@{config:...}` で平文に解決できること
(= 手順4のエージェントが使う経路)を確認します。**平文キーを画面に出さないよう**マスク表示します。

```bash
docker compose exec -T iris iris session IRIS -U %SYS <<'OBJSCRIPT'
 ; Wallet にオブジェクトで格納されているか:
 write "wallet exists: ",##class(%Wallet.KeyValue).%ExistsId("AISecrets.OpenAI"),!
 ; ConfigStore は参照だけ(平文なし):
 do ##class(%ConfigStore.Configuration).GetDetails("AI.LLM.openai",.d,0,0)
 write "config api_key: ",d.%Get("api_key"),!   ; → secret://AISecrets.OpenAI#key
 ; @{config:...} は平文キー入り config に解決される(先頭/末尾だけ表示):
 do ##class(%AI.Utils.SettingStore).RegisterDefaults()
 set v=##class(%AI.Utils.SettingStore).Expand("@{config:AI.LLM.openai}")
 set k={}.%FromJSON(v).%Get("api_key"),n=$length(k)
 write "resolved: mask=",$extract(k,1,3),"...",$extract(k,n-3,n)," len=",n,!
 halt
OBJSCRIPT
```

> **RBAC 注意**: Wallet の読み取りには `%Admin_Wallet` リソース(`%Manager` ロール等が保持)が必要です。
> 本デモの `%SYS` セッションは `%All` を持つため追加設定は不要ですが、権限の無いユーザで
> `GetSecretValue` を呼ぶと「アクセスが拒否されました」になります。

キーが暗号化 IRISSECURITY に保存されていること(手順2との接続)は `IRISSECURITY` の
`EncryptedDB=1` で担保されます([手順2の動作確認](02-irissecurity-encryption.md#動作確認))。

> **キーを差し替えたいとき**: ヘルパを同じプロバイダで再実行するだけです(削除→再作成を内部で行う上書き登録)。
