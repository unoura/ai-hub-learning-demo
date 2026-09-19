# AI Hub Learning Demo

「**ハーネスエンジニアリング(Harness Engineering)**」と「**InterSystems AI Hub**」を紹介する記事のためのデモリポジトリです。
軽量な IRIS を Docker で立ち上げ、セキュリティを段階的に強化してから AI エージェントを動かす、という流れを扱います。

## 全体像

```
軽量 IRIS(Docker) → IRISSECURITY を暗号化 → Wallet に API キーを保護 → エージェントで Hello World
```

手順2で IRISSECURITY データベースを暗号化することにより、手順3で Wallet に格納する API キーが
**保存時(at-rest)で保護**される、という一貫したストーリーになっています。

## ドキュメント構成

ドキュメントは目的別に分けています。

- **[docs/guide/](docs/guide/)** — 聴衆向け。完成した手順と説明。まずはここから。
- **[docs/design/](docs/design/)** — 設計・判断根拠。なぜその構成にしたか。

| # | 手順 | ガイド | 設計 |
|---|---|---|---|
| 1 | Docker で動作する IRIS 環境 | [guide](docs/guide/01-docker-environment.md) | [design](docs/design/01-docker-environment.md) |
| 2 | IRISSECURITY の暗号化 | [guide](docs/guide/02-irissecurity-encryption.md) | [design](docs/design/02-irissecurity-encryption.md) |
| 3 | Wallet で OpenAI / Claude のキー受け渡し | [guide](docs/guide/03-wallet-api-keys.md) | [design](docs/design/03-wallet-api-keys.md) |
| 4 | エージェントで Hello World | [guide](docs/guide/04-agent-hello-world.md) | [design](docs/design/04-agent-hello-world.md) |

## 技術スタックの前提

- ベースイメージ: **iris-community**(AI Hub EAP、ライセンス不要・FHIR なしの軽量構成)
- AI Hub SDK: `%AI.*`(`%AI.Tool` → `%AI.ToolSet` → `%AI.Agent` / `%AI.MCP.Service`)
- LLM プロバイダ: OpenAI / Anthropic(Claude)の両対応

## クイックスタート

```bash
cp .env.example .env          # 任意(API キーを使う場合)
docker compose up -d --build  # ビルド & 起動
docker compose exec -it iris iris session iris -U DEMO
```

詳細は [docs/guide/01-docker-environment.md](docs/guide/01-docker-environment.md) を参照。
