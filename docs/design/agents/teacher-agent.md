# 設計: 先生(トレーナー)エージェント(発展形)

> 本ドキュメントは**シナリオ設計と実現方式の確定**が目的。
> 聴衆向け手順は後日 `docs/guide/agents/teacher-agent.md`、実施記録は `local/worklog/agents/teacher-agent.md` に分ける(混ぜない)。
>
> **実装状況(2026-09-21 / 監査・承認追加 2026-09-23)**: 第1段(教材データ + ベクトル検索)・第2段(権限制御 + ツール群 + trajectory + RunAs)・
> 第3段(ペルソナ再設計)・第6段(永続監査 `%AI.Policy.Audit`)・第7段(人手承認・フィードバック human-in-the-loop)・
> 第8段(設問一覧を共有ツール化)とも **実機で end-to-end 検証済み**。以下の実現方式は設計と実装が一致している。実際のクラス名は
> `Demo.Teacher.*` パッケージに収めた(当初スケッチの `Demo.Policy.*` / `Demo.ToolSet.*` / `Demo.RunAs` は下記の実クラス名で置き換わる)。

> ---
> ## 第3段: ペルソナ再設計(受講者/監査者 → 生徒/設問管理者)(ユーザ確定・実装済み 2026-09-21)
>
> **動機**: エージェンティック AI の見どころは「自律的な情報取得」だけでない。**要約・生成・情報登録**という
> LLM ならではの働きを、権限で封じ込めつつ見せたい。そこでペルソナを実務に即した2役に組み替えた。
>
> **本文の①②③(権限ディスカバリ / trajectory / ベクトル検索)の機構は変更なし**。変わったのは
> ペルソナ・リソース・ロール・ツール構成・データモデルと、多層防御の当て方(下記)。以降の旧記述
> (受講者/監査者、`Demo_LearnRead`/`Demo_AnswerKey`/`Demo_Grade`、`GetHint`/`GetAnswerKey`/`ViewProgress`/`RecordScore`)
> は**この節が優先**する。
>
> ### ペルソナ / リソース / ロール / ユーザ
>
> | ペルソナ | ユーザ | アプリロール | リソース | できること |
> |---|---|---|---|---|
> | 生徒 | `student01` | `Demo_Student` | `Demo_Study` | 自分の解答の採点、自分の成績表閲覧 |
> | 設問管理者 | `qadmin01` | `Demo_QuestionAdmin` | `Demo_Authoring` | 規程を基にした設問の作成・登録 |
>
> 実行基盤ロール `Demo_Runtime`(DB 権限)は第2段と同じく共有。採点・成績と作問は**ほぼ排他**の権限。
>
> ### ツール構成(2クラス + 共通の SearchPolicy)
>
> | クラス | ツール | 要件リソース | 働き |
> |---|---|---|---|
> | `Demo.Teacher.Tools.Catalog` | `ListPracticeQuestions` | なし(全員) | 既存設問(questionId/category/prompt/difficulty)を返す。模範解答・採点基準は返さない。生徒への**出題**にも設問管理者の**作問前カタログ確認**にも使う共有ツール(第8段で `Tools.Study` から分離。下記) |
> | `Demo.Teacher.Tools.Study` | `GradeMyAnswer` | `Demo_Study`(生徒) | 解答を採点し点数+講評を Progress に登録。**採点はサーバ側で** AnswerKey の採点キーポイントと語句照合して算出(自己申告不可)。返り値は点数・到達/未達観点・出典のみ(模範解答/採点基準は返さない) |
> | `Demo.Teacher.Tools.Study` | `ShowReportCard` | `Demo_Study`(生徒) | 本人の直近10件(`Ts` 降順)を取得。エージェントが平均・傾向・弱点を**要約** |
> | `Demo.Teacher.Tools.Authoring` | `RegisterQuestion` | `Demo_Authoring`(設問管理者) | エージェントが SearchPolicy を基に**生成**した設問・模範解答・採点基準・採点キーポイントを Question/AnswerKey に**登録** |
> | `SearchPolicy`(KnowledgeBase) | — | なし(全員) | 規程のベクトル検索(第1段のまま) |
>
> 旧 `Tools.Learn`/`Tools.AnswerKey`/`Tools.Grade` は削除。ToolSet は Include を Catalog(要件なし)/ Study /
> Authoring の3クラスにし、Study/Authoring の Include に `resource` 要件(`Demo_Study` / `Demo_Authoring`)を付ける
> (Catalog は要件なし=誰でも)。※当初は `ListPracticeQuestions` も `Tools.Study` に同居していたが、第8段で共有化した(下記)。
>
> ### データモデルの変更
>
> - `Demo.Teacher.AnswerKey` に **`KeyPoints`(採点キーポイント)** を追加。書式 `"観点名=語1|語2;観点名=..."`
>   (観点は `;`、同義語は `|` 区切り)。各観点にいずれかの語が解答に含まれれば「到達」とみなす。
>   さらに **`Question` に一意インデックス `QIdx`** を付け、`QIdxOpen(questionId)` で採点基準を
>   **オブジェクトアクセス**で開けるようにした(→ 下記の多層防御)。
> - `Demo.Teacher.Progress` は `Ts`(既存)を「直近10件」の並び順に使う。`Learner` にはログインユーザ名が入る
>   (採点は生徒本人の行動)。`Demo.Teacher.Setup.SeedProgress()` が成績表デモ用に student01 の履歴を数件投入。
>
> ### 多層防御の当て方(第2段から更新)
>
> - **採点基準(AnswerKey)は生徒に SQL SELECT を与えない**。`GradeMyAnswer` は `QIdxOpen`(オブジェクト
>   アクセス=`%DB_DEMO_DATA` で動く)で採点基準を読むため採点は成立するが、**生徒は SQL からは採点基準を
>   読めない**。採点はサーバ側で算出するので**点数の自己申告もできない**。
> - 作問(Question/AnswerKey への書き込み)は**オブジェクトアクセス(`%Save`)**で行い、実行可否は
>   **ツール層(RoleGuard = `Demo_Authoring` の USE)**で設問管理者に限定する。
> - SQL GRANT(`Security.GrantSql`): 生徒 = Policy/Question/Progress の SELECT(AnswerKey は**与えない**)、
>   設問管理者 = Policy/Question/AnswerKey の SELECT、共有 Demo_Runtime = PolicyVec の SELECT。
>
> ### 対話開始時の自己開示(第4段で追加)
>
> 対話モード(`Teacher.TalkWith` / `RunAs.TalkAs`)は、READ ループの**前に開始挨拶ターンを1回**実行し、
> エージェントに「いまできること」を利用者へ開示させる(`Teacher.Greet`)。session はログイン後に作るので
> **見えるツールは呼び出し元のロールで絞られており**、開示内容も生徒(出題・採点・成績表)/ 設問管理者(作問)で
> 自動的に変わる。利用者が最初に何を頼めるか分かる=UX 改善であると同時に、「できることの開示」自体が
> ハーネスの権限に沿う(見えないツールは案内もされない)。
>
> ### 軌跡はオンデマンド表示(`/trace`)(第4段で追加)
>
> 対話モードは当初、毎ターン trajectory を垂れ流していたが会話が読みにくかった。→ **通常は応答だけ**を返し、
> 利用者が **`/trace`** と入力したときだけ直前の応答の軌跡(`ShowTrajectory(session, lastFrom)`。ターン開始位置
> `from` を覚えておき当該ターン分だけ描く)と集計(`session.GetStats()` の累計トークン・ツール呼び出し数)を
> 表示する(`/help` でコマンド一覧、`quit`/空行で終了)。**この案内は開始時と各応答のあとに毎回画面に出す**ので、
> 利用者は「いつでも過程を追える」と認識できる(観測点を隠さない=監査可能性の担保)。単発の `RunLesson` /
> `RunLessonWith`(デモの見せ場)は従来どおり毎回インラインで軌跡+集計を表示する(`Monitor` の反復表示も残す)。
> 兄弟リポジトリ `aihub-demo` の `/trace` 慣習に合わせた。
>
> ### 生徒の学習ループ(教わる → 練習 → 採点 → 復習)(第5段で追加)
>
> 生徒ペルソナは当初、練習問題を出してもらい採点してもらうだけで、**学ぶ機会が薄かった**
> (問題を解くだけで、分からない分野を教わる導線が無い)。→ Teacher.INSTRUCTIONS の生徒節を
> 「**教わる → 練習 → 採点 → 復習**」の一周に書き換えた(**ツールは追加せず**、既存の
> `SearchPolicy` / `ListPracticeQuestions` / `GradeMyAnswer` / `ShowReportCard` の使い方=手順だけを更新):
>
> - **教わる**: 「〜について教えて」「〜がわからない」→ `SearchPolicy` で該当規程を検索し**出典付きで解説**、
>   最後に「この分野の練習問題を1問やってみますか?」と**練習を提案**する。
> - **練習**: 「問題を出して」→ `ListPracticeQuestions` で既存問題を提示(新規作問はしない=設問管理者権限)。
> - **採点**: 解答が来たら `GradeMyAnswer`。採点後は**未達の観点を `SearchPolicy` で再解説して復習につなげ**、
>   最後に「**成績表を表示しますか?**」と学習のふり返り(`ShowReportCard`)を提案する。
> - **復習(成績表)**: `ShowReportCard` で本人履歴を要約し、弱点分野の解説・練習を提案する。
>
> 設問の指定が曖昧なとき(「設問1」等)は questionId を確認してから採点する(取り違え防止)。
> **狙い**: 「教わる」という LLM ならではの働き(規程の検索+やさしい解説)を学習体験に組み込みつつ、
> ①②③の機構(権限ゲート / trajectory / ベクトル検索)は不変に保つ。RunLessonAs / TalkAs のどちらでも
> 同じ挙動(実機確認: student01 で「情報持ち出しについて教えて」→ SearchPolicy 発火・第7条を出典に解説・
> 練習提案 / 採点 → 100点・出典付き・締めに「成績表を表示しますか?」の声かけ)。
>
> ### 永続監査(`%AI.Policy.Audit`)を採用(第6段で追加)
>
> それまで「過程を追う」手段は trajectory(`%AI.Agent.Session` 履歴からの再構成)だけで、**会話が
> 終われば揮発**していた。→ AI Hub 標準の**監査ポリシー**を配線し、ツール実行の証跡を DB に永続化した
> (参考: `aihub-demo/AdmissionDemo` の `PersistentAudit` / `ToolCallLog` パターン。実機で完動確認済み)。
>
> - **`Demo.Teacher.Audit.PersistentAudit`**(`%AI.Policy.Audit` 継承): `%LogExecution(call, metadata,
>   result, duration, status)` を override し、`$USERNAME` / ツール名 / 引数 / 成否 / 所要 ms を1行 `%Save()`。
>   監査失敗はツール実行に波及させない(Catch → プロセス外グローバル `^Demo.Teacher.AuditError`)。
> - **`Demo.Teacher.Audit.ToolCallLog`**(`%Persistent`): SQL 表 `Demo_Teacher_Audit.ToolCallLog`。
> - **取り付け**: ToolSet の `<Policies>` に `<Audit Class="Demo.Teacher.Audit.PersistentAudit"/>` を1行追加
>   (`RegisterToolSet` / `UseToolSet` どちらの経路でも適用され、直接 `ExecuteTool` でも LLM 会話でも記録される)。
> - **記録される `$USERNAME` は切替後のデモユーザ**(監査は Login 後のプロセスで走るため)。RBAC で
>   ツールが割れることと、その実行が別ユーザ名で監査に残ることを 1 セットで見せられる(実機確認:
>   CompareActions で student01=GradeMyAnswer / qadmin01=RegisterQuestion、RunLessonAs でも同様に記録)。
> - **正直な位置づけ**: 記録されるのは**実際に実行されたツールだけ**。`%CanList` で除外された呼び出しは
>   実行に入らない(`ToolNotFound`)ので監査には残らない(拒否そのものを残したいなら認可ポリシー側で記録)。
>   `%AI.Policy.ConsoleAudit`(stdout・揮発)ではなく永続版を選択。IRIS の「システム監査 DB」
>   (`$SYSTEM.Security.Audit`)とは別枠。deterministic replay の専用 API は無いので「厳密な再実行」ではなく
>   「起きたツール実行の証跡」と位置づけ、trajectory(過程)と補完関係にある。
> - 見せ方: `Demo.Teacher.RunAs.ShowAudit(n)`(直近 n 件を「誰が・成否・ツール・所要 ms・引数」で表示)/
>   `ClearAudit()`(証跡なので `Setup.Rebuild()` では消さず、独立メソッドで消去)。
>
> ### 人手承認・フィードバック(human-in-the-loop)を採用(第7段で追加)
>
> **動機**: 設問管理者は規程から設問を**生成**して教材 DB に**書き込む**。生成物をそのまま登録するのではなく、
> 「AI は生成、最終決定は人間」を土台側で担保したい。書き込みが起きる直前=`RegisterQuestion` の実行前を
> 承認点にするのが自然(参考: `aihub-demo/AdmissionDemo` の `ConsoleApproval`。書き込み系ツールを承認で門番)。
>
> - **どこに入れるか**: 承認ゲートは **`RoleGuard`(既存の Authorization ポリシー)に集約**した。
>   `%AI.ToolSet` は **Authorization スロットを1つしか持てない**ため、承認専用クラスを別立てにできない
>   (RBAC 判定と同じクラスに1段足すのが素直)。`Parameter APPROVALTOOLS = "RegisterQuestion"`(部分一致・
>   カンマ区切り)で承認対象を指定。採点(GradeMyAnswer)は毎回・低リスクなので対象外。
> - **RBAC × 承認は別軸**: `%CanExecute` はまず (1) `resource` の USE 権限を確認し(RBAC = 誰が呼べるか)、
>   通過した**あと**で (2) 承認対象なら人間に諮る(承認 = この一件を実行してよいか)。生徒には作問ツールが
>   `%CanList` で見えないので、承認の出番もない。
> - **フィードバック機構が肝(実機で検証)**: `%CanExecute` は `%Status` しか返せない。そこで人間の選択肢を
>   3つにし、`Decide()` が `"APPROVE"` / `"REJECT"` / `"REVISE:<指示>"` を返す:
>   - APPROVE → `$$$OK`(そのまま実行=登録)。
>   - REJECT → `$$$ERROR($$$AICoreToolAccessDenied, "…却下されました…")`(登録しない)。
>   - REVISE → **人間の指示を AccessDenied のエラーテキストに埋め込んで**拒否する。エージェントループは
>     これを「ツール失敗の理由」として LLM に返し、**LLM は指示を読んで設問を作り直し、改めて
>     `RegisterQuestion` を呼ぶ**(承認されるまで往復)。Teacher.INSTRUCTIONS の設問管理者節に
>     「差し戻し文言=拒否ではなく修正指示。作り直して再登録せよ」を明記して LLM の解釈を固定した。
>   - **実機検証**: `TalkAs(qadmin01)` で「もっと難しい応用レベルにして、NG 例に Password123 を入れて」と
>     差し戻し → LLM が指示を反映して作り直し → 再度承認要求 → y で登録。ツール呼び出し3回、監査に残るのは
>     **承認・実行された1件だけ**(差し戻された試行は実行に入らないため監査に出ない)。
> - **承認には端末が要る**: プロンプトは `%Library.Prompt.GetString` で1行受ける(`Include %syPrompt`、
>   成功は `$$$SuccessResponse`)。y/yes/はい=承認、空行/n/no/いいえ=却下、それ以外=差し戻し指示。
>   端末を持つのは対話 `TalkAs`(在プロセス)だけ。単発 `RunLessonAs`(JOB 子=端末なし、`$Principal="/dev/null"`)は
>   **非対話のため自動承認**し注記を出す(承認の実演は `TalkAs` に役割分担)。
> - **テスト/決定的動作**: プロセス内グローバル `^||Demo.Teacher.Approval` を最優先で参照する
>   (連番添字でキュー化でき revise→approve の往復も再現。1=承認 / 0=却下 / 他文字列=差し戻し指示)。
>   `^||`(プロセス私有)は JOB 子に伝播しないため、フィードバックループの自動テストは **RunLesson を特権
>   プロセス内で回す**(RunLessonAs の JOB 子では不可)ことで実施した。
> - **正直な位置づけ**: 承認ゲートは `%CanExecute` が唯一の実行門で、差し戻しは「実行拒否+指示の伝達」を
>   1つのエラーで兼ねる簡素な方式。より厳密には承認待ちキュー/非同期承認(別 UI で承認)も設計できるが、
>   デモは「土台側で書き込みを人間が承認し、指示で AI に作り直させる」1周を最短で見せることを優先した。
>
> ### 設問一覧を共有ツールに(第8段で追加)
>
> **動機(ユーザ指摘)**: 設問管理者は作問するのに**既存の設問一覧が見えず**、重複回避や手薄な分野の
> 把握ができず不便だった(既知 TODO「作問カテゴリのズレ」とも地続き)。→ `ListPracticeQuestions` を
> **生徒・設問管理者どちらからも使える共有ツール**にした(ユーザ確定=「既存ツールを共有に変更」)。
>
> - **実装上の要点**: ToolSet の `<Requirement>` は Include 内の**全ツール**にメタデータを stamp するため、
>   `Tools.Study`(`Demo_Study` 要件)に同居したままでは `ListPracticeQuestions` だけを開放できない。
>   → **`ListPracticeQuestions` を新クラス `Demo.Teacher.Tools.Catalog` に切り出し、要件なしの Include**
>   (`<Include Class="Demo.Teacher.Tools.Catalog"/>`)として ToolSet に足した。採点・成績(`GradeMyAnswer` /
>   `ShowReportCard`)は `Tools.Study` に残し `Demo_Study` 専用のまま。`RoleGuard` は resource 要件が空なら
>   `%CanList`=1 / `%CanExecute`=素通しなので**変更不要**。
> - **SQL 面**: `ListPracticeQuestions` は `Demo_Teacher.Question` を SELECT。設問文(模範解答は含まない)は
>   規程(Policy)と同じく**共有情報**なので、GrantSql で **Question の SELECT を共有ロール `Demo_Runtime`**
>   に寄せた(PolicyVec と同じ扱い)。従来の生徒/設問管理者ロール個別の Question GRANT は不要になり削除。
> - **デモの物語への影響(承知の上)**: `Compare()` で設問管理者にも `ListPracticeQuestions` が見えるように
>   なり「ほぼ排他」が一部崩れるが、**排他なのは採点・成績(生徒)と作問(設問管理者)**で、閲覧系の共有
>   ツール(`SearchPolicy` / `ListPracticeQuestions`)は両者に開く、という整理にした(SearchPolicy が既に
>   共有なので不自然ではない)。実機 end-to-end 検証(Bedrock, RunLessonAs qadmin01「既存の問題一覧を
>   見せて」): `ListPracticeQuestions {}` を実呼び→5件を一覧提示→重複しない作問を提案、まで確認。
> - **ツール名は据置**: 「既存ツールを共有に」の趣旨に沿い名前は `ListPracticeQuestions` のまま
>   (設問管理者向けには「作問前のカタログ確認」と位置づけを言い換え)。
>
> ### ビルド時の注意(第4段で判明・恒久対策済み)
>
> `$system.OBJ.Compile` は DB 上の既ロードクラスを再コンパイルするだけで `.cls` をディスク再読込しない
> (編集反映には先に `LoadDir`/`Load` が要る)。さらに **`LoadDir` の一括処理では ToolSet の
> ジェネレータ(`%Discover`/`%Invoke`)が Include ツールクラスより先に routine 生成され、古いツール一覧を
> 拾って新ツールを静かに取りこぼす**ことがある(例: `ListPracticeQuestions` 追加が反映されない)。
> → `docker/start.sh` は `LoadDir` の**直後に `Demo.Teacher.ToolSet` を単独で強制再コンパイル**
> (`$system.OBJ.Compile("Demo.Teacher.ToolSet","ck")`、`u` 修飾子なし=up-to-date でもやり直す)して確定させる。
> 手作業で src を再ロードするときも同じ順序を踏むこと。詳細は [[reference-ai-sdk-capabilities]]。
>
> ### 簡易的措置(第3段)
>
> - 採点は**語句照合**(サーバ側で完結し自己申告を防ぐのが主目的)。本番は意味照合/LLM 採点へ。
> - 成績表の本人限定は各ツール内の `WHERE Learner=$Username`。本番は行レベルセキュリティで担保。
> ---

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

#### 「取れる行動」の差(ディスカバリだけでなく実行で示す)

`Demo.Teacher.RunAs.CompareActions()` は、各ユーザ identity で `GetAnswerKey` / `RecordScore` を
**実際に実行**する(`%AI.ToolMgr.ExecuteTool(name, args)`)。

- **受講者(learner01)**: `%CanList` がカタログから除外済みのため、実行しても `ToolNotFound`(=そもそも
  呼べない)。**ディスカバリゲートが一次防御**として機能し、実行ゲート `%CanExecute` はその後段の二重防御。
- **監査者(auditor01)**: `GetAnswerKey` が模範解答を返し、`RecordScore` が Progress 行を実際に書き込む。
  → **同じエージェント・同じツールセットでも identity で取れる行動が変わる**ことを実行結果で示せる。

> **多層防御(実機で判明した設計上の要点)**: ツールの可視性/実行ゲート(RoleGuard)に加え、**SQL レベルの
> 権限も揃える必要がある**。ツールの中身は `%SQL.Statement.%ExecDirect` で DB を読み書きするが、
> `%DB_DEMO_DATA` 等の DB 権限は**オブジェクトアクセス**(`%OpenId`/`%Save`)にしか効かず、**SQL には
> テーブル単位の GRANT が別途要る**。そこで `Demo.Teacher.Security.GrantSql()` が受講者ロールへ教材
> (規程・設問)の `SELECT` のみ、監査者ロールへ模範解答・進捗の `SELECT`/`INSERT` を付与する。これにより
> **受講者はツール経由でも SQL からも模範解答を読めない**(ツール層 × SQL 層の多層防御)。
> ベクトル索引 `Demo_Teacher.PolicyVec` は `Setup.BuildIndex` で後から作られるため、GrantSql の対象外
> (エージェントを受講者 identity で走らせて SearchPolicy まで実行する場合は別途 SELECT が要る)。

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
- 永続監査(**採用済み。第6段で追加**): `%AI.Policy.Audit`(`%LogExecution` → `%Save()`)で
  誰が・いつ・どのツールを・成否・所要 ms を残す。→ 「安全な運用の土台=trajectory で過程を追え、
  永続監査で証跡が残る」で締める。**deterministic replay の専用 API は無い**ため、厳密な再実行では
  なく「起きたツール実行の証跡」を残す位置づけ(session 履歴からの trajectory 再構成と補完関係)。
  詳細は下記「### 永続監査(`%AI.Policy.Audit`)を採用(第6段で追加)」。

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
| ポリシー | 1クラス `RoleGuard` に `%CanList`/`%CanExecute`(+ 書き込み系の人手承認)を集約 | リソース/ロール設計を組織の RBAC に合わせ、`%AI.Policy.Discovery` で動的カタログ整形も検討 |
| 人手承認 | `%CanExecute` で書き込み系を止め、承認/却下/フィードバックを端末で1行入力(`RunLessonAs` は自動承認) | 承認待ちキュー/非同期承認(別 UI・別担当者)、承認記録の監査、差し戻し理由の構造化 |
| 監査 | trajectory(session 再構成)+ **永続監査 `%AI.Policy.Audit`(採用済み)** = `Demo.Teacher.Audit.ToolCallLog` に DB 永続化 | 監査ログを SIEM 連携。保持期間/改ざん防止、拒否イベントの記録も認可ポリシー側で拡張 |
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
   (`RoleGuard`、`ToolSet`、`Security`(RBAC)、`RunAs`、`Monitor`、`Teacher`、`Progress`。
   RunAs で権限別ディスカバリ差、RunLesson で出典付き回答と trajectory を実機確認)。
5. **第3段(ペルソナ再設計)完了(2026-09-21)**: ペルソナを **生徒(student01)/ 設問管理者(qadmin01)** に組み替え、
   ツールを `Tools.Study`(GradeMyAnswer/ShowReportCard)/ `Tools.Authoring`(RegisterQuestion)に整理(旧 Learn/AnswerKey/Grade 削除)。
   採点はサーバ側の語句照合、成績表は要約、作問は SearchPolicy→生成→登録。AnswerKey に KeyPoints 追加。
   採点・成績・作問の3機能を両ペルソナで実機 end-to-end 検証(詳細は上記「第3段」節)。guide / demo-runbook を更新済み。
