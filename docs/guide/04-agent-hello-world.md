# 手順4: エージェントで Hello World を作成する

AI Hub の Native Agent(`%AI.Agent`)で最小の「Hello World」を作り、手順3で Wallet に登録した
API キーを **ConfigStore の名前参照(`@{config:...}`)だけ**で解決して、OpenAI と対話できることを
確認します。ここが「Wallet に保護したキー → エージェントが利用」という本デモの到達点です。

> 設計・判断根拠は [../design/04-agent-hello-world.md](../design/04-agent-hello-world.md) を参照。

## エージェントクラス

`src/Demo/Agent/Hello.cls` に `%AI.Agent` を継承した1クラスを置いています。要点は3つだけです。

```objectscript
Class Demo.Agent.Hello Extends %AI.Agent
{

/// キーは名前参照のみ(平文を書かない)。ConfigStore → Wallet と解決される。
Parameter PROVIDERCONFIG = "@{config:AI.LLM.openai}";

/// システムプロンプト(text/markdown)。
XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
# 役割
あなたは「InterSystems AI Hub デモ」の案内役です。... (簡潔な日本語で答える)
}

ClassMethod RunOnce(input As %String = "自己紹介して") As %Status { ... }

}
```

- **`PROVIDERCONFIG = "@{config:AI.LLM.openai}"`** が手順3との接続点。ソースに平文キーは書かず、
  実行時に `ConfigStore(AI.LLM.openai) → secret://AISecrets.OpenAI#key → Wallet` と解決されます。
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

手順3で OpenAI キーを登録済みであることが前提です(未登録なら
[手順3](03-wallet-api-keys.md)の `register-key.sh openai` を先に実行)。

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

> **プロバイダを切り替えるには**: `PROVIDERCONFIG` を `@{config:AI.LLM.anthropic}` にして、
> 手順3で `register-key.sh anthropic` を実行しておくだけです(クラス側の他の変更は不要)。

## ここまでの全体像

```
軽量 IRIS(手順1) → IRISSECURITY 暗号化(手順2) → Wallet に API キー保護(手順3)
  → エージェントが @{config:...} で解決して LLM と対話(手順4)
```

キーを一度も平文でソース・設定・環境変数に置かないまま、エージェントが安全に LLM を使えることを
確認できました。
