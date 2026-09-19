# 手順3: ウォレットで OpenAI / Claude のキーを受け渡す

## ゴール

OpenAI と Claude(Anthropic)の API キーを IRIS の **Wallet** に格納し、AI Hub の **ConfigStore** からは
`secret://` 参照だけで扱う。手順2で `IRISSECURITY` を暗号化済みのため、キーは暗号化されて保存される。

## 方針(確定済み)

両参照元にある **Wallet + ConfigStore** パターンを踏襲する
(`aihub-demo/src/MyApp.ConfigStoreWithWalletDemo.cls`、`ai-hub-dev-template/skills/ai-hub-config-store`)。

4層構造:

1. **RBAC リソース** — `Security.Resources.Create` で Use/Edit リソースを作成しアクセスを制御
2. **Wallet コレクション** — `%Wallet.Collection.Create("...", {"UseResource":.., "EditResource":..})`
3. **Wallet シークレット** — `%Wallet.KeyValue.Create("Collection.OpenAI", {"Usage":"CUSTOM","Secret":{"api_key":...}})`
   を OpenAI / Anthropic それぞれに作成(実際の秘密値。列挙不可)
4. **ConfigStore 設定** — `%ConfigStore.Configuration.Create(...)` は
   `"api_key":"secret://Collection.OpenAI#api_key"` のように**参照のみ**を保持(平文を持たない)

- **キーの出所**: `.env` の `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` を初回起動時に Wallet へ取り込む
- **解決**: アプリ側は平文に触れない。AI Hub がプロバイダ呼び出し時に内部で `secret://` を解決する

## 実装手順(実装後に追記)

_（実装時に記載）_

## 確認方法(実装後に追記)

_（実装時に記載。例: ConfigStore に平文が無いこと、エージェントがキーを解決して呼び出せること）_
