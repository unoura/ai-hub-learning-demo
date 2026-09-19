# 手順4: エージェントで Hello World を作成する

## ゴール

AI Hub の Native Agent(`%AI.Agent`)で最小の「Hello World」を作り、手順3の Wallet/ConfigStore 経由で
解決した API キーを使って OpenAI / Claude と対話できることを確認する。

## 方針(確定済み)

`aihub-demo/src/MyApp.*` の最小構成をお手本にする。AI Hub の 4層パターン。

- **Tool** — 最小の `%AI.Tool`(例: `Calculator` の `Add` / `Multiply`)。メソッドが自動的にツールとして公開される
- **ToolSet** — `%AI.ToolSet` でツールを束ねる(hello world では省略可)
- **Agent** — `%AI.Agent` を継承。`XData INSTRUCTIONS` にシステムプロンプト、`%OnInit()` で
  プロバイダを設定・ツールを登録
- **プロバイダ選択** — `aihub-demo` の `Utils.CreateProvider` 相当で、OpenAI / Anthropic を切り替え可能に
  (キーは手順3の ConfigStore/Wallet から解決)
- **実行** — 対話 REPL(`CreateSession()` → `Chat(session, input)`)で挨拶を返す

## 想定クラス

```
最小 %AI.Tool           # Hello World 用のツール(任意)
%AI.Agent 継承クラス     # INSTRUCTIONS + %OnInit()(プロバイダ/ツール登録)
（任意）%AI.MCP.Service  # 同じツールを MCP サーバとして公開する発展形
```

## 実装手順(実装後に追記)

_（実装時に記載）_

## 確認方法(実装後に追記)

_（実装時に記載。例: `iris session` からエージェントを起動し、Hello World の応答を得る）_
