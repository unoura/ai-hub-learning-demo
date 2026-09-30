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
  通しで実践する手順は **[docs/guide/demo-runbook.md](docs/guide/demo-runbook.md)(実践ガイド)** を参照。
- **[docs/design/](docs/design/)** — 設計・判断根拠。なぜその構成にしたか。

**構成要素(building-blocks)** — エージェントが安全に動く土台:

| 構成要素 | ガイド | 設計 |
|---|---|---|
| Docker で動作する IRIS 環境 | [guide](docs/guide/building-blocks/docker.md) | [design](docs/design/building-blocks/docker.md) |
| IRISSECURITY の暗号化 | [guide](docs/guide/building-blocks/encryption.md) | [design](docs/design/building-blocks/encryption.md) |
| Wallet で OpenAI / Claude / Bedrock のキー受け渡し | [guide](docs/guide/building-blocks/wallet.md) | [design](docs/design/building-blocks/wallet.md) |

**エージェント(agents)** — 上記の土台の上で動かす:

| エージェント | ガイド | 設計 |
|---|---|---|
| プレインエージェント(会話するだけの最小構成) | [guide](docs/guide/agents/plain-agent.md) | [design](docs/design/agents/plain-agent.md) |
| 先生エージェント(権限で振る舞いが変わる発展形) | [guide](docs/guide/agents/teacher-agent.md) | [design](docs/design/agents/teacher-agent.md) |

## リポジトリ構成

```
.
├── README.md                     この文書(入口)
├── Dockerfile                    IRIS(AI Hub EAP)イメージのビルド。ビルド時に merge.cpf と iris.script を適用
├── docker-compose.yml            コンテナ定義(ポート・ソースのマウント・Durable %SYS ボリューム)
├── merge.cpf                     CPF マージ: DEMO 名前空間(DEMO_DATA / DEMO_CODE)の作成
├── iris.script                   ビルド時の初期設定(パスワード無期限化・ZPM 導入など)
├── requirements.txt              Embedded Python 用パッケージ(MCP 関連)
├── .env.example                  .env のサンプル(ホスト側ポート。API キーは書かない)
├── .iris-agentic-dev.toml.example  iris-agentic-dev(IRIS 操作用 CLI / MCP)の接続設定サンプル
├── .vscode/settings.json         VS Code の ObjectScript 拡張をコンテナへ接続する設定
├── docker/
│   ├── start.sh                  エントリーポイント: IRIS 起動を待って初回初期化・ソースのロード
│   ├── first-boot-encrypt.sh     初回起動時だけ IRISSECURITY を暗号化(構成要素: 暗号化)
│   └── register-key.sh           LLM の API キーを Wallet + ConfigStore に手動登録(構成要素: Wallet)
├── src/Demo/
│   ├── Agent/
│   │   ├── Base.cls              共通ベースエージェント(ConfigStore から LLM プロバイダを自動採用)
│   │   └── Plain.cls             プレインエージェント(ツールなし・会話だけ)
│   └── Teacher/                  先生エージェント(クラスの役割は agents/teacher-agent.md の表を参照)
│       ├── Teacher.cls           エージェント本体(対話モード・trajectory 表示)
│       ├── ToolSet.cls           ツールセット(RoleGuard と監査ポリシーを付与)
│       ├── Tools/                ツール: Catalog(設問一覧)/ Study(採点・成績表)/ Authoring(作問)
│       ├── RoleGuard.cls         権限ゲート(RBAC)+ 人手承認ゲート
│       ├── Security.cls          デモ用のリソース・ロール・ユーザを作成
│       ├── RunAs.cls             別ユーザの権限での実行・比較、監査ログの表示
│       ├── Monitor.cls           trajectory の観測(反復数・トークン)
│       ├── Setup.cls             教材データの投入とベクトル索引の構築
│       ├── Policy.cls / Question.cls / AnswerKey.cls / Progress.cls
│       │                         データ: 社内規程 / 設問 / 模範解答・採点基準 / 学習履歴
│       └── Audit/                永続監査: PersistentAudit(監査ポリシー)/ ToolCallLog(事象)/ RunLog(ラン)
├── docs/
│   ├── guide/                    聴衆向けの手順と説明(demo-runbook.md = 通しの実践ガイド)
│   │   ├── building-blocks/      docker.md / encryption.md / wallet.md
│   │   └── agents/               plain-agent.md / teacher-agent.md
│   └── design/                   設計・判断根拠(guide と同じ2層構成)
└── local/                        ローカル専用(Git 管理外。README.md のみコミット)
```

`src/` 配下はコンテナ起動時に DEMO 名前空間へロード・コンパイルされます(`docker/start.sh`)。

## 技術スタックの前提

- ベースイメージ: **iris-community**(AI Hub EAP、ライセンス不要・FHIR なしの軽量構成)
- AI Hub SDK: `%AI.*`(`%AI.Tool` → `%AI.ToolSet` → `%AI.Agent` / `%AI.MCP.Service`)
- LLM プロバイダ: このデモは OpenAI / Anthropic(Claude)/ Amazon Bedrock に対応。
  AI Hub 自体はほかにも Gemini / Vertex AI・xAI・DeepSeek などに対応し、Ollama などのローカル LLM も
  OpenAI 互換 API で利用できます([ai-hub-eap の SDK ガイド](https://github.com/intersystems-community/ai-hub-eap/blob/main/ObjectScript_SDK_Guide.md))

## クイックスタート

```bash
cp .env.example .env          # 任意(API キーを使う場合)
docker compose up -d --build  # ビルド & 起動
docker compose exec -it iris iris session iris -U DEMO
```

詳細は [docs/guide/building-blocks/docker.md](docs/guide/building-blocks/docker.md) を参照。
