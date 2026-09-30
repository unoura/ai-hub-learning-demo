# 設計: プレインエージェント(ツールを持たない最小構成)

## ねらい

AI Hub の Native Agent(`%AI.Agent`)でツールを持たない最小のプレインエージェントを作り、Wallet 構成要素で登録した
API キーを **ConfigStore の名前参照だけ**で解決して、実際に LLM と対話できることを確認する。
これで「構成要素(Docker → 暗号化 → Wallet)→ プレインエージェント」の一連が閉じ、
ここから権限で振る舞いが変わる先生エージェントへ発展させる土台になる。

プロバイダは固定せず、**Wallet 構成要素で登録したもの(openai / anthropic / bedrock のどれでも)を
起動時に自動採用**する(AI Hub 自体はほかにも Gemini / Vertex AI・xAI・DeepSeek 等や、
OpenAI 互換 API 経由の Ollama などに対応する。このデモは 3 つに絞った)。

## 採用した構成(実機で疎通確認済み)

**共通ベース + プレインエージェント**の2クラスにした。プロバイダ選択の共通ロジックをベースに集約する。

- `src/Demo/Agent/Base.cls`(`%AI.Agent` 継承・abstract)— マルチプロバイダ選択を `%OnInit()` に実装。
- `src/Demo/Agent/Plain.cls`(`Demo.Agent.Base` 継承)— システムプロンプトと実行ヘルパだけ。

| 要素 | 採用 | 理由 |
|---|---|---|
| プロバイダ選択 | `Base.%OnInit()` が `PROVIDERPRIORITY`(既定 `bedrock,anthropic,openai`)の順で ConfigStore を探す | **ConfigStore を選択の情報源にする**(ユーザ要望)。キーを env に出さない本デモの主旨と両立 |
| キー解決 | `%ConfigStore.Configuration.GetDetails(fqn,.d,0,1)` → `%AI.Provider.Create(d.%Get("model_provider"),d)` | `resolveSecrets=1` が `secret://` を Wallet で解決。**ソースに平文キーもプロバイダ名も書かない** |
| システムプロンプト | `XData INSTRUCTIONS [ MimeType = "text/markdown" ]` | `%AI.Agent` の `%LoadInstructions()` が Markdown として読む(既存 `%AI.Shell.ConsoleAgent` と同形) |
| 会話フロー | `%New()` → `%Init()` → `CreateSession()` → `Chat(session,input)` | この build で実在するメソッド。応答は `%AI.LLM.Response.Content` |
| 実行ヘルパ | `ClassMethod RunOnce(input)` | デモを1行で回せるように。例外は捕捉して読みやすく表示 |

### なぜ %OnInit で選ぶか(PROVIDERCONFIG を固定しない)

`%AI.Agent` の `Parameter PROVIDERCONFIG = "@{config:AI.LLM.openai}"` はプロバイダを1つに固定する。
複数プロバイダ対応にはこれをやめ、`%Init()` の最後に呼ばれる `%OnInit()` で `..Provider` を動的に
セットする(このとき `PROVIDER`/`PROVIDERCONFIG` が空だと `%CreateProvider` はスキップされ、
`%OnInit` で上書きできる)。判定を**環境変数ではなく ConfigStore で行う**点だけが ai-hub-eap の
`%OnInit` パターンとの差。`%AI.Provider.CreateFromConfig` はこの build(AI.136)には無いため、
`GetDetails` + `%AI.Provider.Create` を使う。

### なぜ Tool / ToolSet を作らないか

当初案は AI Hub の4層(Tool → ToolSet → Agent → MCP)を一通り見せる構成だったが、
**「Wallet のキーで LLM に到達できる」ことの確認**がプレインエージェントの目的なので、
ツール呼び出しは含めない最小構成にした。ツール・MCP 公開は先生エージェントなど発展形として後段に回す。

## Wallet → エージェントの解決チェーン(Wallet 構成要素と接続)

```
%New() → %Init()  (…RegisterDefaults / LoadInstructions … の後、最後に %OnInit)
  → Base.%OnInit() : PROVIDERPRIORITY を順に ConfigStore.Exists("AI.LLM.<p>") で探索
  → ConfigStore    : api_key = "secret://AISecrets.<Name>#key"(参照だけ)
  → GetDetails(...,resolveSecrets=1) : Wallet(暗号化 IRISSECURITY)から実値を取得
  → %AI.Provider.Create(model_provider, details) : ここで初めて平文キーがメモリ上に現れる
  → ..Model = details.model
  → Chat(session,input) → LLM → %AI.LLM.Response.Content
```

平文が現れるのは Provider 生成の直前・メモリ上だけ。ソース・設定・環境変数・ログには残らない。

## コードロード方式 = src/ 起動時ロード(暫定措置)

`docker/start.sh` の初回初期化で、暗号化の**後**に
`$system.OBJ.LoadDir("/home/irisowner/dev/src","ck",,1)` を DEMO 名前空間で実行する。
リポジトリは `/home/irisowner/dev` に bind-mount 済みなので、`src/` を編集 → 再起動(または
手動リロード)で反映できる。毎起動でコンパイルする冪等な処理。

| 論点 | 採用 | 本番向け(正準) |
|---|---|---|
| パッケージング | `src/` を `LoadDir` で読む | **ZPM(`module.xml`)** でパッケージ化・依存/バージョン管理・配布 |

デモの主題は Wallet→エージェントの流れであり、パッケージング手法の紹介ではないため、
説明の焦点をぼかさない軽量ロードを採った。配布・複数クラス・依存が絡む本番では ZPM が正準。

## デモとしての暫定措置 と 本番運用

| 暫定措置 | 内容 | 本番向け |
|---|---|---|
| プロバイダ選択 | 登録済みを優先順に自動採用(単純な first-match) | 用途別に複数設定を持ち名前で選ぶ / ルーティング。ConfigStore の descriptor を正式定義 |
| コードロード | `src/` 起動時 `LoadDir` | ZPM(`module.xml`)でパッケージ配布 |
| ツール | なし(ツールを持たない最小構成) | `%AI.Tool` / `%AI.ToolSet` / `%AI.MCP.Service` で機能拡張 |

## Wallet 構成要素との接続

エージェントは平文キーもプロバイダ名もソースに持たず、`AI.LLM.*` という ConfigStore の**名前**でしか
API キーを参照しない。実体は Wallet 構成要素で Wallet(暗号化 IRISSECURITY)に保護されている。
したがってプレインエージェントは暗号化・Wallet の構成要素の上にしか成立しない。
