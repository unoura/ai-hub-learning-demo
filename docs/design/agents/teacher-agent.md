# 設計: 先生(トレーナー)エージェント(発展形)

> 本ドキュメントは**シナリオ設計と実現方式の確定**が目的。
> 聴衆向け手順は後日 `docs/guide/agents/teacher-agent.md`、実施記録は `local/worklog/agents/teacher-agent.md` に分ける(混ぜない)。
>
> **実装状況(2026-09-21)**: 第1段(教材データ + ベクトル検索)・第2段(権限制御 + ツール群 + trajectory + RunAs)とも
> **実機で end-to-end 検証済み**。以下の実現方式は設計と実装が一致している。実際のクラス名は `Demo.Teacher.*`
> パッケージに収めた(当初スケッチの `Demo.Policy.*` / `Demo.ToolSet.*` / `Demo.RunAs` は下記の実クラス名で置き換わる)。

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

**実装(第2段で確定)**: ツールは役割ごとに分けて `Demo.Teacher.Tools.*` に置き、1つのツールセット
`Demo.Teacher.ToolSet` にまとめた(SearchPolicy だけは KnowledgeBase なのでエージェントへ別途登録)。

| クラス | ツール | 要件リソース |
|---|---|---|
| `Demo.Teacher.Tools.Learn` | `GetHint` | `Demo_LearnRead`(全員) |
| `Demo.Teacher.Tools.AnswerKey` | `GetAnswerKey` | `Demo_AnswerKey`(監査のみ) |
| `Demo.Teacher.Tools.Grade` | `ViewProgress` / `RecordScore` | `Demo_Grade`(監査のみ) |

- ToolSet XML で各 Include に**リソース要件メタデータ**を付ける(要件名は小文字 `resource`。`metadata.%Get("resource")` で読む):
  ```xml
  <ToolSet Name="Teacher">
    <Policies><Authorization Class="Demo.Teacher.RoleGuard"/></Policies>
    <Include Class="Demo.Teacher.Tools.Learn"><Requirement Name="resource" Value="Demo_LearnRead"/></Include>
    <Include Class="Demo.Teacher.Tools.AnswerKey"><Requirement Name="resource" Value="Demo_AnswerKey"/></Include>
    <Include Class="Demo.Teacher.Tools.Grade"><Requirement Name="resource" Value="Demo_Grade"/></Include>
  </ToolSet>
  ```
- `<Requirement>` はその Include に含まれる全ツールにメタデータを stamp する。エージェントへの取り付けは
  `agent.UseToolSet("Demo.Teacher.ToolSet")`。ツールは **`CreateSession()` の前に取り付ける**(session が
  取り付け済みツールをスナップショットするため)。

## 中核機構の実現方式(build .136 で実機確認済み)

裏取り結果(`ai-hub-eap`〈master〉のガイド + 兄弟リポジトリ `aihub-demo/RoleBaseDemo` + 実機
イントロスペクション)に基づく。詳細は [[reference-ai-hub-eap]] / [[reference-aihub-demo]] 参照。

### ① 権限によるツールディスカバリの違い(見どころ)

`%AI.Policy.Authorization` は**可視性**と**実行**の2段ゲートを持つ:

| メソッド | 役割 | デモでの使い方 |
|---|---|---|
| `%CanList(tool As %String, metadata) → %Boolean` | **LLM に見せるか**(ディスカバリ) | `0` を返すとカタログから消える。`metadata.%Get("resource")` を読み `$SYSTEM.Security.Check(res,"USE")` で判定 |
| `%CanExecute(tool As %String, call, metadata) → %Status` | 実行してよいか | 二重防御。未認可なら `$$$ERROR($$$AICoreToolAccessDenied,...)` |

> **署名の実機注意**: どちらも**第1引数はツール名(`%String`)**であって `%AI.Tool` ではない(間違えると
> コンパイル #5478 署名エラー)。クラスは `Include (%AI, %occStatus)` が必要。実装は `Demo.Teacher.RoleGuard`。

- ツールカタログの生成経路: `agent.ToolManager.%Discover()` が返す `%DynamicArray` を `%CanList` が絞る。
  → **LLM は見えないツールを呼べない**。プロンプトインジェクションで解答を引き出そうとしても、
  そもそもツールが存在しない(=土台での封じ込め)。
- ポリシーの取り付け: ToolSet XML `<Policies><Authorization Class="Demo.Teacher.RoleGuard"/></Policies>`
  (または `%AI.ToolMgr.SetAuthPolicy(policy)`)。
  **注意: 1つの ToolSet が持つ Authorization スロットは1つだけ**(2つ書くと後勝ち)。
  → RBAC 判定は**1つのポリシークラス** `Demo.Teacher.RoleGuard` に集約する。
- ポリシー実装(実クラス。要件名は小文字 `resource`):
  ```objectscript
  Include (%AI, %occStatus)
  Class Demo.Teacher.RoleGuard Extends %AI.Policy.Authorization
  {
    Method %CanList(tool As %String, metadata As %DynamicObject) As %Boolean
    {
      Set res = ..RequiredResource(metadata)
      If res = "" Return 1                              // 要件なし = 見せる
      Return $SYSTEM.Security.Check(res, "USE")         // 権限があれば見せる
    }
    Method %CanExecute(tool As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
    {
      Set res = ..RequiredResource(metadata)
      If res = "" Return $$$OK
      If $SYSTEM.Security.Check(res, "USE") Return $$$OK
      Return $$$ERROR($$$AICoreToolAccessDenied, "権限がありません(必要リソース: " _ res _ ")")
    }
  }
  ```

#### 呼び出し側 identity のつくり方(重要な設計上の制約)

`$SYSTEM.Security.Check` は**現在のプロセスのロール**を見る。受講者/監査を切り替えて見せるには、
それぞれの identity でエージェントを動かす必要がある。ところが `$SYSTEM.Security.Login` は
**プロセス内で取り消せず、一度落とした %All は戻せない**(`aihub-demo/RoleBaseDemo` で確認済みの idiom)。

→ **各ロールごとに `JOB` で子プロセスを起こし、その中で `$SYSTEM.Security.Login("<user>", pwd)`**
してからディスカバリ/実行する「RunAs」方式にする(実装 `Demo.Teacher.RunAs`)。
`do ##class(Demo.Teacher.RunAs).Compare()` が learner01 / auditor01 の両方を JOB し、それぞれが見える
ツール名を並べて表示する。**子は親の名前空間(DEMO)を継承**し、Login でデモユーザの identity・ロールに切り替わる。
子プロセスの標準出力は親に届かないため、**結果(user / roles / 見えたツール名)を `/tmp/runas_<user>.json` に
書き出し、親がファイルの出現をポーリングして回収**する(`%Stream.FileCharacter`)。

- 実機検証: learner01(`Demo_Learner,Demo_Runtime`)→ `GetHint` のみ。auditor01(`Demo_Auditor,Demo_Runtime`)
  → `GetAnswerKey` / `GetHint` / `RecordScore` / `ViewProgress` の4つ。**同じ `%Discover()` 呼び出しでも
  ロールで結果が変わる**ことを実演できた。
- ディスカバリは `set mgr=##class(%AI.ToolMgr).%New()` → `do mgr.RegisterToolSet("Demo.Teacher.ToolSet")`
  → `set arr=mgr.%Discover()`(`%CanList` が権限で絞った配列が返る)。

> 簡易的措置: デモでは Login 可能な最小ユーザ(受講者用 learner01 / 監査用 auditor01)を
> `Demo.Teacher.Security.SetupRBAC()` で作成する(Wallet 構成要素の Resources 作成と同じ流儀)。
> **ユーザ名はロール名と重複できない**(大文字小文字を無視して衝突すると #942)ため接尾辞 `01` を付けた。
> 本番は既存の認証(LDAP/OAuth/Delegated 等)に接続する。

> **土台とアプリ権限の分離(実機で必要だった)**: アプリリソース(`Demo_LearnRead` 等)のロールだけを
> 持つユーザは、そもそも DEMO 名前空間でコードを動かせない。そこで DB 権限(`%DB_DEMO_CODE` 等)を持つ
> **実行基盤ロール `Demo_Runtime`** を別に作り、各デモユーザへ「アプリロール + Demo_Runtime」の2本立てで付与した。
> 「動かせる土台」と「何を見せるか(アプリ権限)」を層で分けるのは、そのままハーネスの設計思想でもある。

### ② trajectory(軌跡)の取得と可視化(見どころ)

**実機で判明した粒度(重要)**: `Run(session, goal, maxIterations, callbackOref)` は**外側ループ**で、
その内側で `Chat` が**ツール呼び出しループ**(推論→ツール実行→再推論)を回す。callback の
`OnIterationStart` / `OnIterationComplete` は**外側1反復ごと**に発火し、`OnIterationComplete` が受け取る
`response` は**その反復のツール実行後の最終応答**なので `HasToolCalls()=0`。
→ **ツール呼び出しの明細は callback からは取れない**。callback は「反復回数」と「トークン使用量」という
ハーネス側の観測点に徹し(実装 `Demo.Teacher.Monitor`)、**ツール明細はセッション履歴から描く**(下記)。

```objectscript
Class Demo.Teacher.Monitor Extends %RegisteredObject   // 基底クラス不要のただの %RegisteredObject
{
  Property Iterations As %Integer [ InitialExpression = 0 ];
  Method OnIterationStart(iteration As %Integer, maxIter As %Integer, session As %AI.Agent.Session)
  { set ..Iterations = iteration  write "  [反復 ",iteration,"/",maxIter,"] 推論中…",! }
  Method OnIterationComplete(iteration As %Integer, response As %AI.LLM.Response, session As %AI.Agent.Session)
  { if $isobject(response.Usage) write "      トークン(累計): ",response.Usage."total_tokens",! }
}
```

- **ツール明細はセッション履歴から再構成する**(`Demo.Teacher.Teacher.ShowTrajectory`)。
  `session.MessageCount()` + `session.GetMessage(i)`(`%DynamicObject`)。各メッセージの `role` は
  user / assistant / tool。assistant は `.%Get("tool_calls")`(配列、各要素 `.name` / `.arguments`)を持つ場合があり、
  tool メッセージは `.content`(ツール結果 JSON)を持つ。これで
  👤質問 → 🤖→🔧ツール呼び出し → 🔧→🤖ツール結果 → 🤖回答 の連鎖を描ける。
- `%AI.Agent.Session` が**軌跡の永続ストア**。`session.GetStats()` →
  `total_prompt_tokens` / `total_completion_tokens` / `total_tool_calls`(実呼び出し数はここに出る)/ `total_interactions` 等。
- **実機検証**: `do ##class(Demo.Teacher.Teacher).RunLesson()` が SearchPolicy を実呼びし、
  情報管理規程 第7条・第25条を**出典付き**で回答。trajectory(質問→SearchPolicy 呼び出し→結果→回答生成)と
  集計(反復1 / ツール呼び出し1 / 累計トークン ~4200)を表示できた。
- **プロンプト依存の注意**: 配線が正しくてもプロンプトが弱いとモデルがツールを呼ばず一般論で答えることがある。
  ゴールは「〜を調べて出典付きで教えて」のように**ツールを使う必然**がある形にする。
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
  | **FastEmbed(固定)** | `%AI.RAG.Embedding.FastEmbed.Create()` | 384(`AllMiniLML6V2`) | 不要(ローカル ONNX) | `AddDocument()` は ObjectScript から動く(検索は `ToolMgr.ExecuteTool(kb.Name,{"query":...})` 経由)。実機ではモデルは既にキャッシュ済みで `FASTEMBED_CACHE_DIR` 未設定でも動作 |

  > **日本語品質の限界(実機で確認 2026-09-21)**: この build の FastEmbed は英語モデル `AllMiniLML6V2` に
  > **ハードコード**(`%OnInit` の `$ZF(-6,...,CREATEFASTEMBED)` はモデル引数を取らず、`ModelName`/`Dimensions` は
  > パラメータ固定・Setter なし=多言語モデルへ差し替える口がない)。そのため日本語の意味検索は不正確で、
  > 語彙一致が強い質問(「パスワードは何文字」「不審メール」)は正答するが、意味理解が要る質問
  > (「端末を紛失→インシデント報告」「贈答→コンプライアンス」)では誤った規程を返す(実測 4問中2問ミス)。
  > **分類名+同義キーワードでの本文補強では改善しない**(トークナイザ由来の限界。むしろ汎用語が
  > アトラクタ化して悪化した)。ユーザ確定(2026-09-21)により **FastEmbed のまま**とし、デモは検索が
  > 確実に効く質問に寄せ、この弱点は正直に説明する。本番で日本語品質が要るなら下記 OpenAI 埋め込み等に切替。

  > 参考(不採用): `%AI.RAG.Embedding.OpenAI.Create(provider,"text-embedding-3-small",1536)` は Wallet 構成要素の
  > キーを埋め込みでも再利用でき日本語に強い。ただし (1) openai 登録時のみ成立(プロバイダ非依存でない)、
  > (2) このデモのアカウントは**リージョン制限**があり provider に `sg.api.openai.com` の base URL 設定が別途必要
  > (未設定だと `incorrect_hostname` エラー)。本番で高次元・別モデル・日本語品質が要る場合の選択肢として残す。

- 構築フロー(実装 `Demo.Teacher.Setup`。`ai-hub-dev-template/skills/ai-hub-rag` を踏襲):
  `%AI.RAG.VectorStore.IRIS`(`.TableName` は **`Schema.Table` 形式=ドット1つ**。`Demo_Teacher.PolicyVec`。
  `.Dimensions` / `.ModelName`、`Build()`)
  → `%AI.RAG.KnowledgeBase`(`.Name` が**ツール名**=`SearchPolicy`、`.Description` **必須**、`.TopK`、`Build(emb, vs)`、`AddDocument(text, meta)`)
  → 検索/ツール登録は `kb.AddToManager(mgr)` または `kb.AddToAgent(agent)`。
  ベクトルは Policy 表とは別の `Demo_Teacher.PolicyVec` に永続化され、**別プロセスから再埋め込みなしで検索できる**(実証済み)。
- **データ層の二重ガード**: 模範解答/評価基準は教材 KB とは**別テーブル/別 KB**にし、受講者ツールの
  検索スコープから外す。権限(①)× データ分離で、たとえツールが呼べても中身が出ない構造にする。

## データモデル(実装済み: Policy / Question / AnswerKey)

> **命名の是正**: 当初案の `Demo.Policy` はデータ表と権限クラス `Demo.Policy.RoleGuard` で同名衝突する
> (同名のクラスとパッケージは共存不可)。教材データもポリシー/監視クラスも **`Demo.Teacher.*` パッケージ**に
> 収める。SQL スキーマはパッケージ由来で `Demo_Teacher`(例: `Demo_Teacher.Policy`)。

| 物 | クラス/格納先 | 可視性 | 保護 | 状態 |
|---|---|---|---|---|
| 社内ポリシー本文(教材) | `Demo.Teacher.Policy(Category, Title, Body, Source)` | 全員 | DEMO_DATA | ✅ 実装・投入(10件) |
| 練習問題 | `Demo.Teacher.Question(Category, Prompt, Difficulty)` | 全員 | DEMO_DATA | ✅ 実装・投入(4件) |
| 模範解答・評価基準 | `Demo.Teacher.AnswerKey(Question→, ModelAnswer, Rubric)` | 監査のみ | DEMO_DATA(+ ツール権限) | ✅ 実装・投入(4件) |
| ベクトルインデックス | `Demo_Teacher.PolicyVec`(VectorStore.IRIS が生成、384次元) | — | DEMO_DATA | ✅ `Demo.Teacher.Setup` が構築 |
| 受講者スコア(個人情報) | `Demo.Teacher.Progress(Learner, Question→, Score, Ts)` | 監査のみ | DEMO_DATA(+ ツール権限) | ✅ 実装(`RecordScore` が書き `ViewProgress` が読む実行時状態) |

- 埋め込みは Policy 列には持たせず、KB の VectorStore テーブル `Demo_Teacher.PolicyVec` に分離
  (原本=`Demo.Teacher.Policy` / 検索索引=`PolicyVec` を分けることで再インデックスや原本編集がしやすい)。
- セットアップは手動: `do ##class(Demo.Teacher.Setup).Rebuild()`(冪等な全再構築)。
  起動時に FastEmbed を毎回走らせないため、ボット起動時ロード(`$system.OBJ.LoadDir`)はクラスの読込のみ。

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

1. 題材 = **情報セキュリティ・コンプライアンス研修**のまま(社内ポリシー全般へ広げず)。
2. 埋め込み = **FastEmbed 固定**(384次元・キー不要・プロバイダ非依存)。日本語品質の限界は上記のとおり
   把握済みで、承知の上で FastEmbed のまま採用(デモは検索が効く質問に寄せ、弱点は正直に説明)。
3. identity 切替 = **JOB 子 + `$SYSTEM.Security.Login` の RunAs 方式**。
4. 実装は段階的に進める。**第1段(教材データ + ベクトル検索)完了**(`Demo.Teacher.Policy/Question/AnswerKey/Setup`、
   `Demo_Teacher.PolicyVec`、SearchPolicy 検索の実機確認)。**第2段(権限制御 + ツール群 + trajectory + RunAs)完了**
   (`Tools.Learn/AnswerKey/Grade`、`RoleGuard`、`ToolSet`、`Security`(RBAC)、`RunAs`、`Monitor`、`Teacher`、`Progress`。
   RunAs で権限別ディスカバリ差、RunLesson で出典付き回答と trajectory を実機確認)。
   聴衆向け `guide/agents/teacher-agent.md` 執筆済み(2026-09-21)。
