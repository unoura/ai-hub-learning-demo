# 先生エージェント: 権限で振る舞いが変わる

プレインエージェントは「ツールを持たず LLM と会話するだけ」でした。ここではその発展形として、
**ツールを持ち、呼び出す人の権限で振る舞いが変わる**先生エージェントを動かします。題材は
**情報セキュリティ・コンプライアンス研修**です。登場人物は 2 人:

- **生徒(student01)** — **練習問題を出してもらい**、自分の解答を**採点**してもらい(点数+講評が学習履歴に登録される)、**成績表**を見られる。
- **設問管理者(qadmin01)** — 規程を基に**設問を作成**して教材に登録できる。

見どころは、エージェンティック AI の働きが「自律的な情報取得」だけでないことです:

1. **自律的な情報取得** — 社内規程を IRIS の**ベクトル検索**で意味検索し、**出典付き**で答える。
2. **要約** — 生徒の直近の採点履歴から**成績表**(平均・傾向・弱点)をまとめる。
3. **生成** — 規程を基に**設問・模範解答・採点基準を作る**。
4. **情報登録** — 採点結果や作成した設問を **DB に書き込む**。

そしてこれらの**実行可否は、プロンプトのお願いではなく IRIS プラットフォームの RBAC(土台)**で
決まります。生徒には作問が、設問管理者には採点・成績が**そもそも見えません**。これがハーネス
エンジニアリングの核心です。

> 設計・判断根拠は [../../design/agents/teacher-agent.md](../../design/agents/teacher-agent.md) を参照。

## 登場するクラス(`src/Demo/Teacher/`)

| クラス | 役割 |
|---|---|
| `Demo.Teacher.Teacher` | 先生エージェント本体([Demo.Agent.Base](plain-agent.md) 継承。プロバイダは自動採用) |
| `Demo.Teacher.ToolSet` | ツールセット。各ツールクラスに**必要リソース**を紐付ける |
| `Demo.Teacher.RoleGuard` | 権限ゲート。`%CanList`(見せるか)/ `%CanExecute`(実行してよいか) |
| `Demo.Teacher.Tools.Study` | `ListPracticeQuestions` / `GradeMyAnswer` / `ShowReportCard` — 出題・採点・成績表(**生徒のみ**) |
| `Demo.Teacher.Tools.Authoring` | `RegisterQuestion` — 設問の作成・登録(**設問管理者のみ**) |
| `Demo.Teacher.Security` | デモ用の RBAC(リソース / ロール / ユーザ)を作成 |
| `Demo.Teacher.RunAs` | 別ユーザの権限で「見えるツール・取れる行動」の違いを実演 |
| `Demo.Teacher.Monitor` | trajectory の観測(反復数・トークン) |
| `Demo.Teacher.Audit.PersistentAudit` | 監査ポリシー(`%AI.Policy.Audit`)。ツール実行を DB に永続監査 |
| `Demo.Teacher.Audit.ToolCallLog` | 永続監査ログ(誰が・いつ・どのツールを・成否・所要 ms) |
| `Demo.Teacher.Setup` | 教材データ投入 + ベクトル索引の構築 + 成績表デモ用の履歴 |

ツールと必要リソースの対応(採点・成績と作問はほぼ排他):

| ツール | 必要リソース | 生徒 | 設問管理者 |
|---|---|:--:|:--:|
| `SearchPolicy`(規程のベクトル検索) | なし | ✅ | ✅ |
| `ListPracticeQuestions`(出題) | `Demo_Study` | ✅ | ❌ |
| `GradeMyAnswer`(採点) | `Demo_Study` | ✅ | ❌ |
| `ShowReportCard`(成績表) | `Demo_Study` | ✅ | ❌ |
| `RegisterQuestion`(作問) | `Demo_Authoring` | ❌ | ✅ |

## 前提

- Wallet 構成要素で **openai / anthropic / bedrock のいずれか1つ**を登録済み([Wallet 構成要素](../building-blocks/wallet.md))。
  先生エージェントは [プレインエージェント](plain-agent.md)と同じ `Demo.Agent.Base` を継承し、登録済みプロバイダを自動採用します。
- コードは起動時に自動ロードされます(`docker/start.sh` の `$system.OBJ.LoadDir`)。`src/` を編集したら再起動、
  または手動リロード:

  ```bash
  docker compose exec -T iris iris session IRIS -U DEMO <<'OBJ'
   set sc=$system.OBJ.LoadDir("/home/irisowner/dev/src","ck",,1)
   set sc=$system.OBJ.Compile("Demo.Teacher.ToolSet","ck")
   halt
  OBJ
  ```

  > 2行目で `ToolSet` を単独再コンパイルしているのは、`LoadDir` の一括処理では ToolSet の
  > ツール一覧生成が Include ツールクラスより先に走り、新しいツールを取りこぼすことがあるためです
  > (起動時の `docker/start.sh` も同じ処理を自動で行います)。

## 手順 1: RBAC(リソース / ロール / ユーザ)を作る

「誰が何を使えるか」の土台を IRIS 側に作ります。冪等なので何度実行しても構いません。

```bash
docker compose exec -it iris iris session iris -U DEMO
```

```objectscript
DEMO> do ##class(Demo.Teacher.Security).SetupRBAC()
[security] リソース2 / ロール3(基盤1+アプリ2) / ユーザ2 を用意しました。
```

作られるもの:

- **リソース**: `Demo_Study`(採点・成績表)/ `Demo_Authoring`(作問)
- **アプリロール**: `Demo_Student`(Study のみ)/ `Demo_QuestionAdmin`(Authoring のみ)
- **実行基盤ロール**: `Demo_Runtime`(DEMO 名前空間でコードを動かすための DB 権限)
- **ユーザ**: `student01`(生徒)/ `qadmin01`(設問管理者)。各アプリロール + `Demo_Runtime` を付与

> 「動かせる土台(`Demo_Runtime`)」と「何を見せるか(アプリロール)」を**層で分ける**のがポイントです。
> アプリ権限だけのユーザはそもそも名前空間で動けません。この分離自体がハーネスの設計思想です。
>
> 簡易的措置: デモ用にユーザを直接作成しています。本番は既存の認証基盤(LDAP / OAuth / Delegated 等)に接続します。
> 2ユーザの**共通パスワードは `demo`**(ローカルデモ専用。`TalkAs` のログインで入力します)。既に作成済みでも
> `SetupRBAC()` を再実行すればパスワードは `demo` に揃います。引数で上書きも可(`SetupRBAC("別のpwd")`)。
> 後始末は `do ##class(Demo.Teacher.Security).Teardown()`。

## 手順 2: 教材と検索索引を作る

社内規程・練習問題・模範解答(採点基準)を投入し、規程をベクトル索引化します(FastEmbed / 384次元、キー不要)。
成績表デモ用に、生徒 `student01` の採点履歴も数件投入されます。

```objectscript
DEMO> do ##class(Demo.Teacher.Setup).Rebuild()
```

これで `SearchPolicy`(規程のベクトル検索ツール)が使えるようになります。ベクトルは
`Demo_Teacher.PolicyVec` に永続化され、以後は再埋め込みなしで検索できます。

## 見どころ 1: 権限でツールディスカバリが変わる

**同じエージェント・同じ探索処理**でも、実行するユーザのロールで「見えるツール」が変わることを実演します。

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).Compare()
=== RunAs: ロール別のツールディスカバリ ===
student01(Demo_Runtime,Demo_Student)が見えるツール: GradeMyAnswer, ListPracticeQuestions, ShowReportCard
qadmin01(Demo_Runtime,Demo_QuestionAdmin)が見えるツール: RegisterQuestion
----
生徒には作問ツールが、設問管理者には採点・成績ツールが、そもそも見えない(%CanList で除外)。
```

- **生徒(student01)には採点・成績ツールだけ**、設問管理者(qadmin01)には作問ツールだけが見えます。
- 判定は `RoleGuard.%CanList()` が `$SYSTEM.Security.Check(リソース, "USE")` で行います。
  **LLM は見えないツールを呼べない** — プロンプトインジェクションで作問させようとしても、
  生徒からはそのツールは存在しないのと同じです(=土台での封じ込め)。
- 万一呼ばれても `%CanExecute()` が実行段階で再度拒否します(二重ガード)。

> なぜ別ユーザで実行するのに一手間かけるのか: `$SYSTEM.Security.Login` はプロセスの識別情報を
> **不可逆に**切り替えるため、`RunAs` は各ロールごとに `JOB` で子プロセスを起こし、その中でログイン→
> ディスカバリしています。

### 「取れる行動」も変わる(ツールを実際に実行)

見えるだけでなく、**実際にツールを実行**すると何が起きるかを対比します。各ユーザの identity で
`GradeMyAnswer`(採点)と `RegisterQuestion`(作問)を実行します。

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).CompareActions()
=== RunAs: ロール別の「取れる行動」 ===
student01(Demo_Runtime,Demo_Student)が取れる行動:
  GradeMyAnswer(採点)    → ✓ 実行OK: {"value":{"score":100,"citation":"情報セキュリティ規程 第12条", …}}
  RegisterQuestion(作問) → ✗ 権限なし: ツールがカタログに存在しません(%CanList で除外)
qadmin01(Demo_Runtime,Demo_QuestionAdmin)が取れる行動:
  GradeMyAnswer(採点)    → ✗ 権限なし: ツールがカタログに存在しません(%CanList で除外)
  RegisterQuestion(作問) → ✓ 実行OK: {"value":{"ok":1,"questionId":"…"}}
----
採点(GradeMyAnswer)は生徒だけ、作問(RegisterQuestion)は設問管理者だけが実行できる。
```

- **生徒は作問ツールを呼んでも「カタログに存在しない」**。設問管理者は採点ツールが同様に見えません。
  `%CanList` が実行前のカタログから除外しているため、たとえツール名を知っていても呼べません(一次防御)。
- 生徒の採点は実際に **Progress 行を書き込み**、設問管理者の作問は実際に **Question / AnswerKey を作成**します。
  同じエージェント・同じツールセットでも、**identity で取れる行動が変わる**ことを実行結果で確認できます。

> **多層防御(実装の勘どころ)**: ツールの可視性(`%CanList`/`%CanExecute`)に加えて、**SQL レベルでも**
> ロールを揃えています。**採点基準(AnswerKey)は生徒に SELECT を与えていません**。採点(`GradeMyAnswer`)は
> **サーバ側で**採点基準と突き合わせて点数を出すので採点は成立しますが、**生徒は SQL からも採点基準を
> 読めず、点数を自己申告することもできません**。
> (DB 権限 `%DB_*` はオブジェクトアクセス用で、SQL には別途テーブル GRANT が要る、という IRIS の
> 二層構造をそのまま活かしています。)

## 見どころ 2: 生徒として — 教わる → 練習 → 採点 → 復習

生徒の identity で、学習を**一周**させます。生徒の学びは「**教わる → 練習 → 採点 → 復習**」の
サイクルで進みます。同じエージェントでも、LLM は**見えるツール**を手がかりに役割を判断して振る舞いを変えます。

```objectscript
; 教わる: 分からない分野を質問すると、規程を検索して出典付きで解説してくれる
DEMO> do ##class(Demo.Teacher.RunAs).RunLessonAs("student01", "情報持ち出しについて教えてください。")

; 練習: 練習問題を出してもらう(既存の設問から提示。作問はできない)
DEMO> do ##class(Demo.Teacher.RunAs).RunLessonAs("student01", "何か練習問題を1問出してください。")

; 採点: 解答を採点してもらう(点数+講評が学習履歴に登録される)
DEMO> do ##class(Demo.Teacher.RunAs).RunLessonAs("student01", "questionId=1 に『12文字以上にして、記号を混ぜて、使い回さない』と答えます。採点してください。")

; 復習: 成績表を見る(直近の履歴から平均・弱点を要約)
DEMO> do ##class(Demo.Teacher.RunAs).RunLessonAs("student01", "これまでの私の成績表を見せてください。弱点も教えて。")
```

- **教わる**: 「〜について教えて」「〜がわからない」と言うと、`SearchPolicy` で該当規程を検索して
  **出典(条番号)付きでやさしく解説**し、最後に「この分野の練習問題を1問やってみますか?」と**練習を提案**します。
  生徒は問題を出してもらうだけでなく、**まず学べます**。
- **練習**: `ListPracticeQuestions` が走り、**既存の練習問題**(questionId 付き)を提示します。生徒は
  新しい設問を**作れない**(作問は設問管理者の権限)ので、既存問題から出題します。
- **採点**: `GradeMyAnswer` が走り、**点数・到達/未達の観点・出典**が返り、講評が学習履歴に登録されます。
  模範解答の全文は生徒には返しません(点数と観点フィードバックのみ)。採点のあとは**未達の観点を
  `SearchPolicy` でもう一度解説して復習につなげ**、最後に「**成績表を表示しますか?**」と学習のふり返りを提案します。
- **復習(成績表)**: `ShowReportCard` が本人の直近履歴を取得し、エージェントが**平均点・弱点分野を要約**して見せます
  = LLM の「要約」の働き。他人の成績は取得しません(本人限定)。

> **設問の指定**: 採点は questionId で対象を特定します。「設問1」のように曖昧なときは、エージェントが
> **questionId を聞き返して**から採点します(取り違え防止)。上の例のように `questionId=1` と伝えると一発で採点できます。

## 見どころ 3: 設問管理者として — 規程から設問を生成・登録

設問管理者の identity で、規程を根拠に設問を作り、教材に登録します。

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).RunLessonAs("qadmin01", "『情報持ち出し』の規程を根拠に、応用レベルの設問を1問つくって登録してください。")
```

- エージェントはまず **`SearchPolicy`** で根拠となる規程を調べ(自律的な情報取得)、その内容から
  **設問文・模範解答・採点基準・採点キーポイントを生成**し(生成)、**`RegisterQuestion`** で
  Question / AnswerKey に**書き込みます**(情報登録)。1 つの会話に、取得・生成・登録が揃います。
- 生徒側では `RegisterQuestion` が**カタログに無い**ので、どう促しても作問できません。

## 見どころ 4: trajectory とベクトル検索(誰でも使える規程検索)

規程に関わるゴールを 1 つ与えて、エージェントの**思考と行動の連鎖**を可視化します
(`SearchPolicy` は要件なし=誰でも使えます)。

```objectscript
DEMO> do ##class(Demo.Teacher.Teacher).RunLesson("『情報持ち出し』の社内規程を調べて、出典付きで要点を教えて")
```

出力の流れ:

```
=== ゴール ===
『情報持ち出し』の社内規程を調べて、出典付きで要点を教えて
=== 反復(ハーネスの観測点)===
  [反復 1/6] 推論中…
      トークン(累計): ....
=== trajectory(思考と行動の連鎖)===
  👤 質問: 『情報持ち出し』の社内規程を調べて、出典付きで要点を教えて
  🤖→🔧 ツール呼び出し: SearchPolicy {"query":"情報持ち出し ..."}
  🔧→🤖 ツール結果: [{"title":"情報管理規程 ...
  🤖 回答を生成(... 文字)
=== 最終応答 ===
(情報管理規程 第7条・第25条を出典に、要点を日本語で説明)
=== 集計 ===
反復 1 回 / ツール呼び出し 1 回 / 累計トークン ....
```

- エージェントは自分で **`SearchPolicy`(ベクトル検索)を呼ぶ**判断をし、DB の規程本文を根拠に**出典(条番号)付き**で回答します。
- **trajectory はセッション履歴から再構成**しています(質問 → ツール呼び出し → ツール結果 → 回答生成)。
  誰が何をどのツールで行ったかを、その会話の中で追えます。**会話が終わっても残る永続監査**は
  次の見どころ 5(`%AI.Policy.Audit`)で扱います。

> **プロンプトのコツ**: 「〜を調べて出典付きで教えて」のように**ツールを使う必然**があるゴールにすると、
> 確実にベクトル検索が走ります。
>
> **検索品質の正直な注意**: FastEmbed は英語モデルのため、語彙が一致する日本語質問には強い一方、
> 意味理解が要る質問(例: 「端末を紛失」→インシデント報告)では外すことがあります。デモは検索が
> 効く質問に寄せています。本番で日本語品質が要る場合は OpenAI 埋め込み等に切り替えます(設計ドキュメント参照)。

## 見どころ 5: 永続監査(誰が・どのツールを実行したかが DB に残る)

trajectory は「その会話の中で過程を追う」もので、会話が終われば揮発します。ここでは
**プラットフォーム側にツール実行の証跡を永続化**します。ToolSet に**監査ポリシー**
(`%AI.Policy.Audit` を継承した `Demo.Teacher.Audit.PersistentAudit`)を1つ付けるだけで、
ツールが実行されるたびに「**誰が・いつ・どのツールを・成否・所要 ms・引数**」が
`Demo.Teacher.Audit.ToolCallLog`(SQL 表 `Demo_Teacher_Audit.ToolCallLog`)に1行残ります。

上の見どころ 2〜4 を実行したあとで、直近の監査ログを見てみます:

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).ShowAudit()
=== 永続監査ログ(直近 10 件)===
  2026-09-23 04:57:05    qadmin01  ✓ RegisterQuestion  (0ms)
      args: {"category":"…","modelAnswer":"…","prompt":"…"}
  2026-09-23 04:57:05   student01  ✓ GradeMyAnswer  (1ms)
      args: {"answer":"…","questionId":1}
```

- **記録されるユーザ名は切替後のデモユーザ**(`student01` / `qadmin01`)です。監査は Login 後の
  プロセスで走るので `$USERNAME` がそのまま残り、「見えるツールが割れる(RBAC)」ことと
  「その実行が**別ユーザ名で監査に残る**」ことを 1 セットで見せられます。
- **記録されるのは実際に実行されたツールだけ**です。生徒が作問を頼んでも `%CanList` で
  カタログに無い(=`ToolNotFound`)ため実行に入らず、監査にも残りません。監査は
  「起きたこと」を正直に残します(拒否そのものを残したい場合は認可ポリシー側で記録します)。
- 取り付けは ToolSet の `<Policies>` に `<Audit Class="Demo.Teacher.Audit.PersistentAudit"/>` を
  1 行足すだけ。`%AI.Policy.ConsoleAudit`(stdout に出すだけ・揮発)と違い、DB に残るので後から
  SQL で集計・照会できます(IRIS の「システム監査 DB」= `$SYSTEM.Security.Audit` とは別枠)。
- やり直したいときは `do ##class(Demo.Teacher.RunAs).ClearAudit()`(監査ログは `Setup.Rebuild()`
  では消えません。証跡なので独立して扱います)。

> **trajectory と永続監査の使い分け**: trajectory は「1 回の会話の思考と行動の連鎖」を**その場で**
> 見せるもの、永続監査は「誰が何を実行したか」を**後から追える形で残す**もの。両者を合わせて
> 「過程は追え、証跡は残る」がプラットフォーム側で成立します。

## 対話モードで役割差を見る(TalkAs)

単発の `RunLessonAs` に対し、**対話しながら**役割差を確かめたいときは `TalkAs` を使います。
`Security.Login` は取消不可なので、**1 セッション = 1 ロール**(別ロールはセッションを開き直す):

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).TalkAs("student01")   ; 生徒(出題・採点・成績)
DEMO> do ##class(Demo.Teacher.RunAs).TalkAs("qadmin01")    ; 設問管理者(作問)
```

- **入口でパスワードを尋ねます**(IRIS 標準の `%Library.Prompt.GetPassword` を使用。入力は**伏せ字=非表示**)。
  デモの共通パスワードは **`demo`**(`SetupRBAC` が設定)。ここで **`$SYSTEM.Security.Login` が実際に走る**ので、
  お客様は「別ユーザとしてプラットフォームにログインし直している」ことを目で確認できます。
- 対話の**冒頭で、エージェントが「いまできること」を自己紹介**します。この案内は**見えるツールに
  基づく**ので、生徒なら出題・採点・成績表、設問管理者なら作問、と**ロールで内容が自動的に変わり**、
  利用者は最初に何を頼めるか分かります(できることの開示自体がハーネスの権限に沿っている)。
- 通常は**応答だけ**を返してクリーンに会話できます。**軌跡(思考と行動の連鎖)を見たいときは
  `/trace` と入力**すると、直前の応答の trajectory と集計(ツール呼び出し数・トークン)を表示します。
  この案内は開始時と各応答のあとに毎回画面に出るので、利用者はいつでも過程を追えると分かります
  (`/help` でコマンド一覧、`quit`/空行で終了)。

```
=== 先生エージェント 対話モード ===
先生>
（いまできることの自己紹介。ロールで内容が変わる）

質問を入力してください。/trace=直前の応答の軌跡と集計を表示 / /help=ヘルプ / quit(空行)=終了

あなた> 設問1に「12文字以上、記号を混ぜる、使い回さない」と答えます。採点して。
  (考え中…)
=== 応答 ===
（点数+講評。模範解答の全文は出さない）
  (/trace で直前の応答の軌跡と集計を表示)

あなた> /trace
=== trajectory(思考と行動の連鎖)===
  👤 質問: 設問1に「…」と答えます。採点して。
  🤖→🔧 ツール呼び出し: GradeMyAnswer {"questionId":1,"answer":"…"}
  🔧→🤖 ツール結果: {"value":{"score":100, …}}…
  🤖 回答を生成(… 文字)
=== 集計(累計)===
ツール呼び出し … 回 / トークン …
```

## 暗号化構成要素とのつながり

先生エージェントが扱う**生徒スコア(個人情報)**と**模範解答・採点基準**は、[暗号化構成要素](../building-blocks/encryption.md)で
暗号化された `DEMO_DATA` に載っています。暗号化の価値が「API キー」だけでなく「学習データ」にも及ぶことを、
この題材で示せます。権限(RBAC)× データ暗号化 × ツール分離の多層で守ります。

## ここまでの全体像

```
構成要素: Docker → 暗号化 → Wallet
  → プレインエージェント(会話するだけ)
  → 先生エージェント(生徒=採点・成績 / 設問管理者=作問)
      ・自律的な情報取得(ベクトル検索)× 要約(成績表)× 生成(作問)× 情報登録(採点/設問)
      ・権限で見えるツール・取れる行動が変わる × trajectory で過程を追える × 永続監査で証跡が残る
```

同じエージェント・同じ質問でも、**呼び出す人の権限で見えるツールと取れる行動が変わる**。しかもその過程を
追える。安全なエージェント運用の土台が、プラットフォーム側で成立していることを確認できました。

## 簡易的措置(デモ範囲)

デモとして割り切っている点(本番では強化する):

- **採点はキーポイントの語句照合**で行っています(サーバ側で完結し自己申告を防ぐ、が目的)。本番は
  意味照合や LLM 採点に置き換えます。
- **成績表は本人限定を各ツール内で `WHERE Learner=$Username` により担保**しています。本番は行レベル
  セキュリティで担保します。
- ユーザ/ロールを直接作成しています。本番は既存の認証基盤に接続します。
