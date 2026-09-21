# 手順4: エージェントで Hello World を作成する

AI Hub の Native Agent(`%AI.Agent`)で最小の「Hello World」を作り、手順3で Wallet に登録した
API キーを **ConfigStore の名前参照だけ**で解決して LLM と対話できることを確認します。
ここが「Wallet に保護したキー → エージェントが利用」という本デモの到達点です。

プロバイダは**固定しません**。手順3で **openai / anthropic / bedrock のどれを登録しても**、
エージェントが起動時に登録済みのものを自動採用します(「入れたものが採用される」)。

> 設計・判断根拠は [../design/04-agent-hello-world.md](../design/04-agent-hello-world.md) を参照。

## エージェントクラス(2クラス)

`src/Demo/Agent/` に、共通ベース1つと、それを継承した最小エージェント1つを置いています。

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

**`Demo.Agent.Hello`** — `Demo.Agent.Base` を継承。プロバイダ設定は持たず、
システムプロンプトと実行ヘルパだけを足します。

```objectscript
Class Demo.Agent.Hello Extends Demo.Agent.Base
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

- **プロバイダ選択は `Base.%OnInit()`** が担当。手順3との接続点はここ。ソースに平文キーもプロバイダ名も
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

手順3で **openai / anthropic / bedrock のいずれか1つ**を登録済みであることが前提です(未登録なら
[手順3](03-wallet-api-keys.md)の `register-key.sh <provider>` を先に実行)。複数登録した場合は
`Base` の `PROVIDERPRIORITY`(既定 `bedrock,anthropic,openai`)の順で最初の1つが採用されます。

## 動作確認

対話セッションでエージェントを動かします(日本語を正しく表示するため `-it` で入ります)。

```bash
docker compose exec -it iris iris session iris -U DEMO
```

```objectscript
; ワンショット(最短):
DEMO> do ##class(Demo.Agent.Hello).RunOnce("あなたは何ができますか?一言で。")

; 手動フロー(会話の組み立てを見せたいとき):
DEMO> set agent = ##class(Demo.Agent.Hello).%New()
DEMO> do agent.%Init()
DEMO> set session = agent.CreateSession()
DEMO> set response = agent.Chat(session, "自己紹介して")
DEMO> write response.Content
```

- `response.Content` に LLM の応答本文が入ります。`response.Usage` にトークン使用量。
- 同じ `session` に続けて `Chat` すれば**会話が継続**します。
- 応答は**手順3で Wallet に保護したキー**で認証されています。ソース・設定・ログには
  平文キーは一切現れません(現れるのはプロバイダ生成時のメモリ上だけ)。

> **プロバイダを切り替えるには**: 手順3で別のプロバイダを `register-key.sh <provider>` で
> 登録するだけです。クラスの変更は不要 — 起動時に `Base.%OnInit()` が登録済みのものを自動採用します。
> (複数登録時は `PROVIDERPRIORITY` の順。特定の1つに絞りたければ他を消すか優先順を上書き。)

## ここまでの全体像

```
軽量 IRIS(手順1) → IRISSECURITY 暗号化(手順2) → Wallet に API キー保護(手順3)
  → エージェントが ConfigStore を解決して LLM と対話(手順4)
```

キーを一度も平文でソース・設定・環境変数に置かないまま、エージェントが安全に LLM を使えることを
確認できました。
