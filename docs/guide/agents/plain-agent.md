# プレインエージェント: ツールを持たず LLM と会話する

AI Hub の Native Agent(`%AI.Agent`)でツールを持たない最小のプレインエージェントを作り、
Wallet 構成要素で登録した API キーを **ConfigStore の名前参照だけ**で解決して LLM と対話できることを確認します。
ここが「Wallet に保護したキー → エージェントが利用」という構成要素の到達点です。
ここから権限で振る舞いが変わる先生エージェントへ発展します。

プロバイダは**固定しません**。Wallet 構成要素で **openai / anthropic / bedrock のどれを登録しても**、
エージェントが起動時に登録済みのものを自動採用します(「入れたものが採用される」)。

> **対応プロバイダについて**: このデモが扱うのは openai / anthropic / bedrock の 3 つです。AI Hub 自体(`%AI.Provider`)は
> ほかにも Google Gemini / Vertex AI、xAI、Meta Llama、NVIDIA NIM、DeepSeek、Kimi、OpenRouter、GLM / Z.ai などに対応し、
> **Ollama** などのローカル LLM も OpenAI 互換 API(プロバイダ `"openai"` + `base_url`)で利用できます。
> 対応状況は EAP のビルドで変わるため、最新は [ai-hub-eap の SDK ガイド](https://github.com/intersystems-community/ai-hub-eap/blob/main/ObjectScript_SDK_Guide.md) を参照してください。
> このデモで他のプロバイダを使うには、`register-key.sh` にそのプロバイダの登録を足し、`Base` の
> `PROVIDERPRIORITY` に名前を加えます(Ollama なら `model_provider="openai"` + `base_url` の設定を登録)。

## エージェントクラス(2クラス)

`src/Demo/Agent/` に、共通ベース1つと、それを継承したプレインエージェント1つを置いています。

**`Demo.Agent.Base`** — マルチプロバイダ対応の共通ベース(`%AI.Agent` 継承・abstract)。
`%OnInit()` で ConfigStore(`AI.LLM.*`)を優先順に探し、登録済みの最初の1つを採用します。

```objectscript
Class Demo.Agent.Base Extends %AI.Agent [ Abstract ]
{
/// 採用を試す優先順。ConfigStore の AI.LLM.<provider> を探す。
Parameter PROVIDERPRIORITY = "bedrock,anthropic,openai";

Method %OnInit() As %Status
{
  // ..Provider 未設定なら、優先順に ConfigStore を見て最初の登録済みを採用。
  // GetDetails(...,resolveSecrets=1) が secret:// を Wallet で解決し、
  // %AI.Provider.Create() で Provider を生成、model も設定する。
}
}
```

**`Demo.Agent.Plain`** — `Demo.Agent.Base` を継承。プロバイダ設定は持たず、
システムプロンプトと実行ヘルパだけを足します。

```objectscript
Class Demo.Agent.Plain Extends Demo.Agent.Base
{
/// システムプロンプト(text/markdown)。
XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
# 役割
あなたは「InterSystems AI Hub デモ」の案内役です。... (簡潔な日本語で答える)
}

ClassMethod RunOnce(input As %String = "自己紹介して") As %Status { ... }
}
```

- **プロバイダ選択は `Base.%OnInit()`** が担当。Wallet 構成要素との接続点はここ。ソースに平文キーもプロバイダ名も
  書かず、実行時に `ConfigStore(AI.LLM.*) → secret://AISecrets.*#key → Wallet` と解決されます。
- **`XData INSTRUCTIONS`** がシステムプロンプト(Markdown)。
- **`RunOnce()`** はデモ用のワンショット実行ヘルパ。

## 手順

コードは**起動時に自動でロード**されます(`docker/start.sh` が DEMO 名前空間へ
`$system.OBJ.LoadDir("/home/irisowner/dev/src","ck")`)。`src/` を編集したら再起動、または
下記の手動ロードで反映できます。

```bash
# (任意)src/ を編集した場合の手動リロード
docker compose exec -T iris iris session IRIS -U DEMO \
  <<< ' set sc=$system.OBJ.LoadDir("/home/irisowner/dev/src","ck",,1) halt'
```

Wallet 構成要素で **openai / anthropic / bedrock のいずれか1つ**を登録済みであることが前提です(未登録なら
[Wallet 構成要素](../building-blocks/wallet.md)の `register-key.sh <provider>` を先に実行)。複数登録した場合は
`Base` の `PROVIDERPRIORITY`(既定 `bedrock,anthropic,openai`)の順で最初の1つが採用されます。

## 動作確認

対話セッションでエージェントを動かします(日本語を正しく表示するため `-it` で入ります)。

```bash
docker compose exec -it iris iris session iris -U DEMO
```

```objectscript
; ワンショット(最短):
DEMO> do ##class(Demo.Agent.Plain).RunOnce("あなたは何ができますか?一言で。")

; 手動フロー(会話の組み立てを見せたいとき):
DEMO> set agent = ##class(Demo.Agent.Plain).%New()
DEMO> do agent.%Init()
DEMO> set session = agent.CreateSession()
DEMO> set response = agent.Chat(session, "自己紹介して")
DEMO> write response.Content
```

- `response.Content` に LLM の応答本文が入ります。`response.Usage` にトークン使用量。
- 同じ `session` に続けて `Chat` すれば**会話が継続**します。
- 応答は**Wallet 構成要素で保護したキー**で認証されています。ソース・設定・ログには
  平文キーは一切現れません(現れるのはプロバイダ生成時のメモリ上だけ)。

> **プロバイダを切り替えるには**: Wallet 構成要素で別のプロバイダを `register-key.sh <provider>` で
> 登録するだけです。クラスの変更は不要 — 起動時に `Base.%OnInit()` が登録済みのものを自動採用します。
> (複数登録時は `PROVIDERPRIORITY` の順。特定の1つに絞りたければ他を消すか優先順を上書き。)

## ここまでの全体像

```
構成要素: 軽量 IRIS(Docker) → IRISSECURITY 暗号化 → Wallet に API キー保護
  → プレインエージェントが ConfigStore を解決して LLM と対話
```

キーを一度も平文でソース・設定・環境変数に置かないまま、エージェントが安全に LLM を使えることを
確認できました。
