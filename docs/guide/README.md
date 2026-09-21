# ガイド(聴衆向け)

記事の読者・利用者向けの、完成した手順と説明です。
まず **構成要素(building-blocks)** で土台を作り、その上で **エージェント(agents)** を動かします。

## 構成要素(building-blocks)

依存順に進めます(Docker → 暗号化 → Wallet)。

1. [building-blocks/docker.md](building-blocks/docker.md) — Docker で動作する IRIS 環境を作る
2. [building-blocks/encryption.md](building-blocks/encryption.md) — IRISSECURITY を暗号化する
3. [building-blocks/wallet.md](building-blocks/wallet.md) — Wallet で OpenAI / Claude のキーを受け渡す

## エージェント(agents)

- [agents/plain-agent.md](agents/plain-agent.md) — プレインエージェント(ツールを持たない最小構成)

「なぜその構成にしたか」は [../design/](../design/) を参照してください。
