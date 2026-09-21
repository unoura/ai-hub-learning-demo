# AI Hub Learning Demo

「**ハーネスエンジニアリング(Harness Engineering)**」と「**InterSystems AI Hub**」を紹介する記事のためのデモリポジトリです。
軽量な IRIS を Docker で立ち上げ、セキュリティを段階的に強化してから AI エージェントを動かす、という流れを扱います。

## 全体像

```
構成要素(Docker → 暗号化 → Wallet)を土台に、プレインエージェント、そして先生エージェント
```

暗号化された IRISSECURITY の上に Wallet を載せることで、Wallet に格納する API キーが
**保存時(at-rest)で保護**される、という一貫したストーリーになっています。
この3つの構成要素を土台に、まずツールを持たないプレインエージェント、
そこから権限で振る舞いが変わる先生エージェントへ発展させます。

## ドキュメント構成

ドキュメントは目的別に分けています。

- **[docs/guide/](docs/guide/)** — 聴衆向け。完成した手順と説明。まずはここから。
- **[docs/design/](docs/design/)** — 設計・判断根拠。なぜその構成にしたか。

**構成要素(building-blocks)** — エージェントが安全に動く土台:

| 構成要素 | ガイド | 設計 |
|---|---|---|
| Docker で動作する IRIS 環境 | [guide](docs/guide/building-blocks/docker.md) | [design](docs/design/building-blocks/docker.md) |
| IRISSECURITY の暗号化 | [guide](docs/guide/building-blocks/encryption.md) | [design](docs/design/building-blocks/encryption.md) |
| Wallet で OpenAI / Claude のキー受け渡し | [guide](docs/guide/building-blocks/wallet.md) | [design](docs/design/building-blocks/wallet.md) |

**エージェント(agents)** — 上記の土台の上で動かす:

| エージェント | ガイド | 設計 |
|---|---|---|
| プレインエージェント(会話するだけの最小構成) | [guide](docs/guide/agents/plain-agent.md) | [design](docs/design/agents/plain-agent.md) |
| 先生エージェント(権限で振る舞いが変わる発展形) | [guide](docs/guide/agents/teacher-agent.md) | [design](docs/design/agents/teacher-agent.md) |

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

詳細は [docs/guide/building-blocks/docker.md](docs/guide/building-blocks/docker.md) を参照。
