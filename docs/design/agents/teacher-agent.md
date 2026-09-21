# 設計: 先生(トレーナー)エージェント(発展形)

> 本ドキュメントは**シナリオ設計と実現方式の確定**が目的。実装コードは設計合意後に着手する。
> 聴衆向け手順は後日 `docs/guide/agents/teacher-agent.md`、実施記録は `local/worklog/agents/teacher-agent.md` に分ける(混ぜない)。

## テーマと一言メッセージ

**社会人向けの「先生(トレーナー)エージェント」**。題材は **情報セキュリティ・コンプライアンス社内研修**
(業種非依存で、IRIS のどのお客様にも刺さる)。

> **同じエージェント・同じ質問でも、呼び出す人の権限で「見えるツール」と「取れる行動」が変わる。**
> 安全性はプロンプトのお願いではなく、**ハーネス(土台)側の権限制御**で担保される — これがハーネス
> エンジニアリングの核心。加えて、その過程(trajectory)を**監査・再現**でき、教材は **IRIS のベクトル
> 検索**で意味的に引く。

## 舞台と役割(RBAC)

社内の情報セキュリティ研修。教材(社内ポリシー文書)・練習問題・模範解答/評価基準・受講者スコアを
IRIS に格納。エージェントは1つ(`Demo.Agent.Teacher`、プレインエージェントと共通の [Demo.Agent.Base](plain-agent.md) を継承)。

| ロール | 保有リソース | 想定ユーザ |
|---|---|---|
| `Demo_Learner` | `Demo_LearnRead`(教材・練習問題の読取) | 受講者(一般社員) |
| `Demo_Auditor` | `Demo_LearnRead` + `Demo_AnswerKey` + `Demo_Grade` | 研修管理者 / 監査担当 |

- **受講者**: 教材を検索し、練習問題のヒントを得る(自分の学習)。
- **監査担当**: 加えて模範解答・評価基準を参照し、受講者のスコアを閲覧・記録できる。

受講者スコアは**個人情報**、模範解答/評価基準は**受講者に見せてはいけない情報**。どちらも
暗号化構成要素で暗号化された IRISSECURITY / DEMO_DATA に載せることで at-rest 保護される(暗号化の価値が
「API キー」だけでなく「学習データ」にも及ぶ)。

## ツール構成(%AI.Tool → %AI.ToolSet)と権限ゲート

4層パターン(Tool → ToolSet → Agent)に沿う。**リソース要件をツールに紐付け**、可視性を権限で変える。

| ツール | 役割 | 必要リソース | 受講者 | 監査 |
|---|---|---|:--:|:--:|
| `SearchPolicy` | 社内ポリシーをベクトル検索して該当条項を返す | `Demo_LearnRead` | ✅ | ✅ |
| `GetHint` | 答えを言わずにヒントだけ生成 | `Demo_LearnRead` | ✅ | ✅ |
| `GetAnswerKey` | 模範解答+評価基準(ルーブリック)を取得 | `Demo_AnswerKey` | ❌ | ✅ |
| `ViewProgress` | 受講者の学習履歴・スコアを参照 | `Demo_Grade` | ❌ | ✅ |
| `RecordScore` | 採点結果を記録(書込) | `Demo_Grade` | ❌ | ✅ |

- 共通ツールセット `Demo.ToolSet.Learn`(SearchPolicy / GetHint)。
- 監査ツールセット `Demo.ToolSet.Audit`(GetAnswerKey / ViewProgress / RecordScore)。
- ToolSet XML でツールに**リソース要件メタデータ**を付ける:
  ```xml
  <Include Class="Demo.ToolSet.Audit">
    <Requirement Name="Resource" Value="Demo_AnswerKey"/>
  </Include>
  ```

## 中核機構の実現方式(build .136 で実機確認済み)

裏取り結果(`ai-hub-eap`〈master〉のガイド + 兄弟リポジトリ `aihub-demo/RoleBaseDemo` + 実機
イントロスペクション)に基づく。詳細は [[reference-ai-hub-eap]] / [[reference-aihub-demo]] 参照。

### ① 権限によるツールディスカバリの違い(見どころ)

`%AI.Policy.Authorization` は**可視性**と**実行**の2段ゲートを持つ:

| メソッド | 役割 | デモでの使い方 |
|---|---|---|
| `%CanList(tool, metadata) → %Boolean` | **LLM に見せるか**(ディスカバリ) | `0` を返すとカタログから消える。`metadata.%Get("Resource")` を読み `$SYSTEM.Security.Check(res,"USE")` で判定 |
| `%CanExecute(tool, call, metadata) → %Status` | 実行してよいか | 二重防御。未認可なら `$$$ERROR($$$AICoreToolAccessDenied,...)` |

- ツールカタログの生成経路: `agent.ToolManager.%Discover()` が返す `%DynamicArray` を `%CanList` が絞る。
  → **LLM は見えないツールを呼べない**。プロンプトインジェクションで解答を引き出そうとしても、
  そもそもツールが存在しない(=土台での封じ込め)。
- ポリシーの取り付け: `%AI.ToolMgr.SetAuthPolicy(policy)`、または ToolSet XML
  `<Policies><Authorization Class="Demo.Policy.RoleGuard"/></Policies>`。
  **注意: 1つの ToolSet が持つ Authorization スロットは1つだけ**(2つ書くと後勝ち)。
  → RBAC 判定は**1つのポリシークラス** `Demo.Policy.RoleGuard` に集約する。
- ポリシー実装スケッチ:
  ```objectscript
  Class Demo.Policy.RoleGuard Extends %AI.Policy.Authorization
  {
    Method %CanList(tool As %String, metadata As %DynamicObject) As %Boolean
    {
      Set res = metadata.%Get("Resource")
      Return:res="" 1                                   // 要件なし = 見せる
      Return $SYSTEM.Security.Check(res, "USE")         // 権限があれば見せる
    }
    Method %CanExecute(tool, call, metadata) As %Status
    {
      Set res = metadata.%Get("Resource")
      Return:res="" $$$OK
      Return:$SYSTEM.Security.Check(res,"USE") $$$OK
      Return $$$ERROR($$$AICoreToolAccessDenied, tool)
    }
  }
  ```

#### 呼び出し側 identity のつくり方(重要な設計上の制約)

`$SYSTEM.Security.Check` は**現在のプロセスのロール**を見る。受講者/監査を切り替えて見せるには、
それぞれの identity でエージェントを動かす必要がある。ところが `$SYSTEM.Security.Login` は
**プロセス内で取り消せず、一度落とした %All は戻せない**(`aihub-demo/RoleBaseDemo` で確認済みの idiom)。

→ **各ロールごとに `JOB` で子プロセスを起こし、その中で `$SYSTEM.Security.Login("<user>")`**
してからエージェントを実行する「RunAs」方式にする。デモ用ヘルパ `Demo.RunAs`(仮)を用意し、
`Demo.RunAs.Learner(prompt)` / `Demo.RunAs.Auditor(prompt)` で同一プロンプトを2つの identity で流す。
子プロセスの標準出力(trajectory + 応答)を親が受け取り、並べて表示する。

> 簡易的措置: デモでは Login 可能な最小ユーザ(受講者用 / 監査用)を起動時に作成しておく
> (Wallet 構成要素の Resources 作成と同じ流儀)。本番は既存の認証(LDAP/OAuth/Delegated 等)に接続する。

### ② trajectory(軌跡)の取得と可視化(見どころ)

`Run(session, goal, maxIterations=10, callbackOref)` の **callback** で各反復を捕捉する:

```objectscript
Class Demo.Trajectory.Monitor Extends %RegisteredObject
{
  Method OnIterationStart(iteration As %Integer, maxIter As %Integer, session As %AI.Agent.Session)
  { write "[step ",iteration,"] 開始",! }

  Method OnIterationComplete(iteration As %Integer, response As %AI.LLM.Response, session As %AI.Agent.Session)
  {
    if response.HasToolCalls() {
      set it = response.ToolCalls.%GetIterator()
      while it.%GetNext(.k, .call) { write "  → tool: ",call.name," ",call.arguments,! }
    }
  }
}
```

- `%AI.Agent.Session` が**軌跡の永続ストア**(LLM ターン + ツール呼び出し + 観測の履歴)。
  `session.GetStats()` → `total_prompt_tokens` / `total_completion_tokens` / `total_tool_calls` 等。
- デモの対比: **同じプロンプト**「パスワードの使い回しは規程違反か? 練習問題も出して答え合わせして」を
  受講者/監査で流し、軌跡を並べる:
  ```
  受講者:  [discover] SearchPolicy, GetHint            ← %CanList が2つに絞る
           [step1] SearchPolicy("パスワード 使い回し") → hits: 規程#3.2(cos=0.88), #3.5(0.79)
           [step2] GetHint(q=12) → "…規程3.2条を根拠に自分で判断してみましょう"
           [final] 条項の要約 + ヒント(模範解答は権限なしと明示)
  監査:    [discover] SearchPolicy, GetHint, GetAnswerKey, ViewProgress, RecordScore  ← 5つ見える
           [step1] SearchPolicy(...) → 同じ hits
           [step2] GetAnswerKey(q=12) → 模範解答 + ルーブリック
           [step3] RecordScore(learner="taro", q=12, score=100)
           [final] 模範解答つき解説 + 記録完了
  ```
- 永続監査(任意): `%AI.Policy.Audit`(`%LogExecution` → `%Save()`)で誰が・何を・どのツールで、を残す。
  → 「安全な運用の土台=再現・監査できる」で締める。**deterministic replay の専用 API は無い**ため、
  永続化した session / 監査ログから再構成する、と正直に位置づける(簡易的措置)。

### ③ IRIS ベクトル検索との連携(見どころ)

社内ポリシー文書を埋め込み、`VECTOR_COSINE` で意味検索する。`SearchPolicy` はこの検索の薄いラッパ。

- 実機確認済み: `TO_VECTOR('1,0,0',DOUBLE)` / `VECTOR_COSINE(...)` / `VECTOR_DOT_PRODUCT(...)`、
  列型 `VECTOR(DOUBLE, <dim>)`。
- 埋め込みは **FastEmbed に固定(ユーザ確定 2026-09-21)**。キー不要・プロバイダ非依存・軽量で、
  Wallet 構成要素の主旨(キーを出さない)と衝突せず、openai/anthropic/bedrock どれを登録していても動く。

  | 採用 | クラス | 次元 | キー | 備考 |
  |---|---|---|---|---|
  | **FastEmbed(固定)** | `%AI.RAG.Embedding.FastEmbed.Create()` | 384(`AllMiniLML6V2`) | 不要(ローカル ONNX) | HF モデルのキャッシュが要る(`FASTEMBED_CACHE_DIR`)。`EmbedBatch()` を ObjectScript から直呼びすると例外 → 検索は `ToolMgr.ExecuteTool(kb.Name,{"query":...})` 経由で行う |

  > 参考(不採用): `%AI.RAG.Embedding.OpenAI.Create(provider,"text-embedding-3-small",1536)` は Wallet 構成要素の
  > Wallet を再利用できるが openai 登録時のみ成立するため、プロバイダ非依存を優先して見送り。本番で
  > 高次元・別モデルが要る場合の選択肢として残す。

- 構築フロー(`ai-hub-dev-template/skills/ai-hub-rag`):
  `%AI.RAG.VectorStore.IRIS`(`.TableName` / `.Dimensions` / `.ModelName`、`Build()`)
  → `%AI.RAG.KnowledgeBase`(`.Name` が**ツール名**になる、`.TopK`、`Build(emb, vs)`、`AddDocument()`)
  → `kb.AddToAgent(agent)` でエージェントに検索ツールとして生える。
- **データ層の二重ガード**: 模範解答/評価基準は教材 KB とは**別テーブル/別 KB**にし、受講者ツールの
  検索スコープから外す。権限(①)× データ分離で、たとえツールが呼べても中身が出ない構造にする。

## データモデル(案)

| 物 | テーブル/格納先 | 可視性 | 保護 |
|---|---|---|---|
| 社内ポリシー本文(教材) | `Demo.Policy(id, section, title, body, embedding VECTOR(DOUBLE,384))` | 全員 | DEMO_DATA |
| 練習問題 | `Demo.Question(id, topic, prompt)` | 全員 | DEMO_DATA |
| 模範解答・評価基準 | `Demo.AnswerKey(qid, model_answer, rubric)` | 監査のみ | DEMO_DATA(+ ツール権限) |
| 受講者スコア(個人情報) | `Demo.Progress(learner, qid, score, ts)` | 監査のみ | DEMO_DATA(+ ツール権限) |

## 既存デモとの接続

```
構成要素: Docker → 暗号化 → Wallet
  → プレインエージェント(会話するだけの最小構成)
  → 先生エージェント(権限 × ツールディスカバリ × trajectory × ベクトル検索)
```

- **暗号化**: API キーだけでなく**受講者スコア(個人情報)・模範解答**も守る。
- **Wallet**: LLM キーは (B) 採用時は埋め込みでも再利用。(A) FastEmbed ならキー不要で
  「キーを出さない」思想を一段強調できる。
- **プレインエージェント**: `Demo.Agent.Base` をそのまま継承 → プロバイダ自動採用の恩恵を引き継ぐ。

## デモとしての簡易的措置 と 本番運用

| 簡易的措置 | 内容 | 本番向け |
|---|---|---|
| identity | 起動時に受講者/監査ユーザを作成し `JOB` 子で `Security.Login` | 既存 IdP(LDAP/OAuth/Delegated 認証)に接続、Web/REST の認証済みコンテキストで実行 |
| ポリシー | 1クラス `RoleGuard` に `%CanList`/`%CanExecute` を集約 | リソース/ロール設計を組織の RBAC に合わせ、`%AI.Policy.Discovery` で動的カタログ整形も検討 |
| 監査 | callback 表示 +(任意)`%AI.Policy.Audit` | 監査ログを永続化・SIEM 連携。session 履歴から再構成 |
| 埋め込み | FastEmbed(384次元、ローカル) | 用途に応じ高次元モデル / OpenAI 埋め込み(Wallet 再利用)、再インデックス運用 |
| 教材量 | ポリシー数条 + 練習問題数問 | 実ドキュメント群を `AddDocument`/`ReindexDocument` で継続投入 |

## build .136 固有の注意(実装時に効く)

- `%AI.Provider.CreateFromConfig("name")` と `%AI.Agent` の名前参照は **build 137 以降**。.136 では
  プレインエージェントの `Base.%OnInit`(`%ConfigStore.Configuration.GetDetails(...,resolveSecrets=1)` + `%AI.Provider.Create`)を踏襲する。
- Wallet の実クラスは `%SYS.Wallet.Collection` / `%SYS.Wallet.Secret`(`%Wallet.*` は公開エイリアス)。
  読取は `%Admin_Wallet` リソースで gate。
- ToolSet の Authorization スロットは1つ。`$SYSTEM.Security.Login` は不可逆(→ RunAs は必ず `JOB` 子で)。

## 確定事項(ユーザ確定 2026-09-21)

1. 埋め込み = **FastEmbed 固定**(384次元・キー不要・プロバイダ非依存)。
2. identity 切替 = **JOB 子 + `$SYSTEM.Security.Login` の RunAs 方式**。
3. 実装フェーズ(`guide/agents/teacher-agent.md` + エージェント/ツール/ポリシー/KB/RunAs/教材データ)へ進むかは**次のコメント待ち**。
