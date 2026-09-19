# AI Hub Learning Demo

「**ハーネスエンジニアリング(Harness Engineering)**」と「**InterSystems AI Hub**」を紹介する記事のためのデモリポジトリです。
軽量な IRIS を Docker で立ち上げ、セキュリティを段階的に強化してから AI エージェントを動かす、という流れを扱います。

## 全体像

```
軽量 IRIS(Docker) → IRISSECURITY を暗号化 → Wallet に API キーを保護 → エージェントで Hello World
```

手順2で IRISSECURITY データベースを暗号化することにより、手順3で Wallet に格納する API キーが
**保存時(at-rest)で保護**される、という一貫したストーリーになっています。

## ドキュメント一覧

| # | ドキュメント | 内容 |
|---|---|---|
| 1 | [docs/01-docker-environment.md](docs/01-docker-environment.md) | Docker で動作する IRIS 環境を作る |
| 2 | [docs/02-irissecurity-encryption.md](docs/02-irissecurity-encryption.md) | IRISSECURITY データベースを暗号化する |
| 3 | [docs/03-wallet-api-keys.md](docs/03-wallet-api-keys.md) | Wallet で OpenAI / Claude のキーを受け渡す |
| 4 | [docs/04-agent-hello-world.md](docs/04-agent-hello-world.md) | エージェントで Hello World を作成する |

## 技術スタックの前提

- ベースイメージ: **iris-community**(AI Hub EAP、ライセンス不要・FHIR なしの軽量構成)
- AI Hub SDK: `%AI.*`(`%AI.Tool` → `%AI.ToolSet` → `%AI.Agent` / `%AI.MCP.Service`)
- LLM プロバイダ: OpenAI / Anthropic(Claude)の両対応

> **ステータス:** 各ドキュメントには現在「方針(確定済み)」を記載しています。実装の進行に合わせて、
> 具体的な手順・コマンド・確認結果を追記していきます。
