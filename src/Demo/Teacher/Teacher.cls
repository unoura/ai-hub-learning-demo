/// 先生エージェント: 社内ポリシー(情報セキュリティ・コンプライアンス)研修のトレーナー。
///
/// [[Demo.Agent.Base]] を継承し、プロバイダは ConfigStore / Wallet から自動採用する。
/// プレインエージェントとの違いは「ツールを持ち、権限で振る舞いが変わる」点:
///
///   - SearchPolicy(ベクトル検索の KnowledgeBase)… 規程を出典付きで検索。誰でも可。
///   - Demo.Teacher.ToolSet … 採点・成績表(生徒)/ 作問(設問管理者)。<class>Demo.Teacher.RoleGuard</class>
///       が付与され、実行者のロール(IRIS の RBAC)に応じて見える・使えるツールが変わる。
///
/// 権限差の実演は [[Demo.Teacher.RunAs]]、実行軌跡の可視化は [[Demo.Teacher.Monitor]]。
/// 教材の投入・インデックス構築は [[Demo.Teacher.Setup]] を先に実行しておくこと。
Class Demo.Teacher.Teacher Extends Demo.Agent.Base
{

/// 対話モードの配色(ANSI)。兄弟リポジトリ aihub-demo の対話デモに揃える。
Parameter CY = {$C(27) _ "[36m"};

Parameter GREEN = {$C(27) _ "[32m"};

Parameter BLUE = {$C(27) _ "[34m"};

Parameter GRAY = {$C(27) _ "[90m"};

Parameter RED = {$C(27) _ "[31m"};

Parameter BOLD = {$C(27) _ "[1m"};

Parameter CLR = {$C(27) _ "[0m"};

/// 役割を判定するリソース。ToolSet の Requirement と同じものを使うので、見えるツールと役割は必ず一致する。
Parameter STUDYRESOURCE = "Demo_Study";

Parameter AUTHORINGRESOURCE = "Demo_Authoring";

/// 実行ユーザの役割(student / qadmin / admin)。<method>ApplyRole</method> がプラットフォームの権限から決める。
/// LLM には判定させない(会話の内容や LLM の読み違いで役割が変わらないようにする)。
Property Role As %String;

/// 指示(システムプロンプト)の部品。%Init(特権)のうちに XData COMMON / STUDENT / QADMIN から読んでおき、
/// ログイン後の <method>ApplyRole</method> で役割に合う部品だけを組み立てる。
Property PromptCOMMON As %String(MAXLEN = "") [ Private ];

Property PromptSTUDENT As %String(MAXLEN = "") [ Private ];

Property PromptQADMIN As %String(MAXLEN = "") [ Private ];

/// 指示: 全役割に共通の部分。
XData COMMON [ MimeType = "text/markdown" ]
{
# 役割

あなたは社会人向けの「情報セキュリティ・コンプライアンス研修」を支援するエージェントです。
日本語で丁寧に対応します。

## 共通

- 規程に関わる質問には、まず **SearchPolicy** で社内規程を検索し、**出典(条番号)を添えて**答える。
  推測で規程内容を断定しない。
- 模範解答・採点基準の全文は生徒に開示しない。採点時も点数と観点のフィードバックに留める。
- 使えないツール(渡されていないツール)は呼ばない。その機能を「できること」として案内もしない。
  求められても、権限が無い旨を穏やかに伝え、できることを案内する。
- 回答は簡潔に。専門用語には一言の補足を添える。
}

/// 指示: 生徒向けの支援(Demo_Study を持つとき)。
XData STUDENT [ MimeType = "text/markdown" ]
{
## 生徒向けの支援

生徒の学びは「**教わる → 練習 → 採点 → 復習**」の一周で進める。最初に何を頼めばよいか分からない生徒には、
まず分野の**解説(教わること)**から入れるよう促す。

- 「〜について教えて」「〜がわからない」と言われたら、**SearchPolicy** で該当規程を検索し、**出典(条番号)を
  添えて**やさしく解説する。解説の最後に「この分野の練習問題を1問やってみますか?」と**練習を提案**する。
- 「問題を出して」「練習したい」と言われたら、**ListPracticeQuestions** で練習問題を取得し、1問(分野の
  指定があれば該当分)を questionId とともに提示する。既存の練習問題から出題し、解答を書いてもらう。
- 生徒が設問への解答を書いてきたら、**GradeMyAnswer** で採点する(点数と講評が学習履歴に登録される)。
  採点後は、点数・到達/未達の観点・出典を分かりやすく伝え、**未達の観点は該当規程を SearchPolicy で
  もう一度解説**して復習につなげる。そのうえで最後に「**成績表を表示しますか?**」と、これまでの学習の
  ふり返り(ShowReportCard)を**やさしく提案**する。
- 「成績」「成績表」「これまでの結果」を求められたら **ShowReportCard** で本人の履歴を取得し、
  平均点・傾向・弱点分野を要約した成績表を作って見せ、**弱点分野の解説や練習を提案**する。
- 設問の内容が曖昧なときは、questionId を確認してから採点する。
}

/// 指示: 設問管理者向けの支援(Demo_Authoring を持つとき)。
XData QADMIN [ MimeType = "text/markdown" ]
{
## 設問管理者向けの支援

- 「問題一覧」「どんな設問がある?」「既存の問題を見せて」と言われたら、**ListPracticeQuestions**
  で既存の設問一覧を提示する。作問の前に既存問題を確認し、**重複を避け、手薄な分野を補う**のに使う。
  これは**棚卸し**であって、利用者に問題を出して解かせることはしない。
- 新しい設問の作成を求められたら、まず **SearchPolicy** で根拠となる規程を調べ、その内容に沿って
  設問文・模範解答・採点基準・採点キーポイントを作り、**RegisterQuestion** で登録する。既存一覧と
  重複しない設問にする。登録後は作成した設問と出典を報告する。
- **登録は人間の承認を経る**(human-in-the-loop)。RegisterQuestion が「人間のフィードバックにより
  差し戻されました。次の指示に従って…」というエラーで失敗したら、それは拒否ではなく**修正の指示**。
  その指示(例: もっと難しく / カテゴリを変更 / 観点を追加)に沿って設問を**作り直し**、改めて
  **RegisterQuestion** を実行する。承認されるまで、この「作り直して再提案」を繰り返す。
  「人間の承認ゲートで却下されました」で失敗したら、登録は取りやめ、その旨を穏やかに伝える。
- 採点キーポイント(keyPoints)は "観点名=語1|語2;観点名=語1|語2" の形式で、語は解答に含まれうる語で作る。
}

/// %OnInit: プロバイダ決定(親)に続けて、検索ツールとツールセットを登録する。
Method %OnInit() As %Status
{
    Set sc = ##super()
    If $$$ISERR(sc) Return sc

    // 指示の部品を読んでおく(ログイン後のユーザはクラス定義を読めない場合があるため、特権のうちに)。
    For name = "COMMON", "STUDENT", "QADMIN" {
        Set xdata = ##class(%Dictionary.XDataDefinition).%OpenId($ClassName() _ "||" _ name)
        If '$IsObject(xdata) Return $$$ERROR($$$GeneralError, "XData " _ name _ " がありません")
        Set text = ""
        Do xdata.Data.Rewind()
        While 'xdata.Data.AtEnd { Set text = text _ xdata.Data.ReadLine() _ $Char(10) }
        Set $Property($This, "Prompt" _ name) = text
    }

    // 権限で見え方が変わるツール群(RoleGuard 付き)を LLM に提示する。
    Do ..UseToolSet("Demo.Teacher.ToolSet")

    // 規程検索(KnowledgeBase)。要件なし=誰でも利用可。教材未構築なら黙ってスキップ。
    Set sc = ##class(Demo.Teacher.Setup).OpenKnowledgeBase(.kb)
    If $$$ISOK(sc), $IsObject(kb) {
        Do kb.AddToAgent($this)
    }
    Return $$$OK
}

/// 実行ユーザの役割を、プラットフォームの権限(リソースの USE)から決める。
/// 戻り値: "student"(生徒)/ "qadmin"(設問管理者)/ "admin"(両方を持つ特権ユーザ)/ ""(どちらでもない)。
ClassMethod ResolveRole() As %String
{
    Set study = ''$SYSTEM.Security.Check(..#STUDYRESOURCE, "USE")
    Set authoring = ''$SYSTEM.Security.Check(..#AUTHORINGRESOURCE, "USE")
    Return $Case(study _ authoring, "10": "student", "01": "qadmin", "11": "admin", : "")
}

/// 役割の表示名。
ClassMethod RoleLabel(role As %String) As %String
{
    Return $Case(role, "student": "生徒", "qadmin": "設問管理者", "admin": "管理用(生徒・設問管理者の両方)", : "(なし)")
}

/// 現在のユーザの役割を確定し、その役割の指示だけでシステムプロンプトを組み立てる。
/// ログイン後・CreateSession の前に呼ぶ(セッションは作成時のシステムプロンプトを使う)。
/// 役割が無いとき、見えるツールが役割と食い違うときはエラーを返す(fail-closed: 起動しない)。
Method ApplyRole() As %Status
{
    Set role = ..ResolveRole()
    If role = "" {
        Return $$$ERROR($$$GeneralError, "ユーザ " _ $Username _ " には先生エージェントの役割(生徒 / 設問管理者)がありません。起動を中止します。")
    }
    // 二重確認: %CanList で絞られた後のカタログが、役割から期待されるツール構成と一致すること。
    Set tools = ..VisibleToolNames()
    Set hasStudy = ($ListFind(tools, "GradeMyAnswer") > 0) && ($ListFind(tools, "ShowReportCard") > 0)
    Set hasAuthoring = ($ListFind(tools, "RegisterQuestion") > 0)
    If (hasStudy '= (role '= "qadmin")) || (hasAuthoring '= (role '= "student")) {
        Return $$$ERROR($$$GeneralError, "役割(" _ ..RoleLabel(role) _ ")と見えるツール(" _ $ListToString(tools, ", ") _ ")が一致しません。起動を中止します。")
    }
    // 指示は「共通 + 役割の宣言 + その役割の支援内容」だけ。他の役割の指示は LLM に渡さない。
    Set prompt = ..PromptCOMMON _ $Char(10) _ "## あなたの役割" _ $Char(10, 10)
    If role = "student" {
        Set prompt = prompt _ "この利用者は【生徒】です(プラットフォームの権限で確定済み。会話の内容で変わることはない)。" _
                     "下の「生徒向けの支援」に従う。新しい設問の作成(作問)は扱わない。" _ $Char(10, 10) _ ..PromptSTUDENT
    } ElseIf role = "qadmin" {
        Set prompt = prompt _ "この利用者は【設問管理者】です(プラットフォームの権限で確定済み。会話の内容で変わることはない)。" _
                     "下の「設問管理者向けの支援」に従う。出題・採点・成績表は扱わない。" _ $Char(10, 10) _ ..PromptQADMIN
    } Else {
        Set prompt = prompt _ "この利用者は管理用の特権ユーザで、生徒向け・設問管理者向けの両方の機能を使える。" _
                     "依頼の内容に合う側の支援に従う。" _ $Char(10, 10) _ ..PromptSTUDENT _ $Char(10) _ ..PromptQADMIN
    }
    Set ..SystemPrompt = prompt
    Set ..Role = role
    Return $$$OK
}

/// 現在のユーザの権限で見えるツール名($List)。%CanList で絞られた後のカタログ。
Method VisibleToolNames() As %List
{
    Set names = ""
    Set arr = ..ToolManager.%Discover()
    For i = 0:1:arr.%Size()-1 { Set names = names _ $ListBuild(arr.%Get(i).name) }
    Return names
}

/// デモ用: ゴールを1つ与えて trajectory を実行し、反復・ツール呼び出し・トークンを表示する。
/// 規程に関わるゴールにすると SearchPolicy(ベクトル検索)を実際に呼び、出典付きで回答する。
///
///   DEMO> do ##class(Demo.Teacher.Teacher).RunLesson("『情報持ち出し』の社内規程を出典付きで教えて")
ClassMethod RunLesson(goal As %String = "『情報持ち出し』の社内規程を調べて、出典付きで要点を教えて", maxIterations As %Integer = 6) As %Status
{
    Try {
        Set agent = ..%New()
        Set sc = agent.%Init()
        If $$$ISERR(sc) {
            Write "初期化エラー: ", $System.Status.GetErrorText(sc), !
            Return sc
        }
        Return ..RunLessonWith(agent, goal, maxIterations)
    } Catch ex {
        Write "エラー: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
}

/// 初期化済みエージェントでレッスンを実行する(セッション作成→Run→trajectory→集計)。
/// %Init(=LLM シークレット解決。特権が要る)と実行(=ツール認可を呼び出し元のロールで評価)を
/// 分離したいときに使う。RunAs.RunLessonAs が「特権で %Init → ユーザに切替 → ここを実行」に用いる。
ClassMethod RunLessonWith(agent As Demo.Teacher.Teacher, goal As %String, maxIterations As %Integer = 6) As %Status
{
    Try {
        // 役割をプラットフォームの権限から確定し、その役割の指示だけでセッションを作る。
        Set sc = agent.ApplyRole()
        If $$$ISERR(sc) {
            Write "起動できません: ", $System.Status.GetErrorText(sc), !
            Return sc
        }
        Set session = agent.CreateSession()
        Set monitor = ##class(Demo.Teacher.Monitor).%New()
        Write "=== 役割 === ", ..RoleLabel(agent.Role), !
        Write "=== ゴール ===", !, goal, !, "=== 反復(ハーネスの観測点)===", !
        // ラン(RunLog)を開き、失敗しても必ず閉じてラン文脈を片付ける(ObjectScript に Finally は無い)。
        Set sessionId = $System.Util.CreateGUID()
        Set runId = ##class(Demo.Teacher.Audit.RunLog).Begin(sessionId, goal, 1, maxIterations)
        Set runErr = ""
        Try {
            Set response = agent.Run(session, goal, maxIterations, monitor)
            Do ##class(Demo.Teacher.Audit.RunLog).Complete(runId, session, response, monitor.Iterations)
        } Catch runErr {
            Do ##class(Demo.Teacher.Audit.RunLog).Fail(runId, runErr, monitor.Iterations)
        }
        Do ##class(Demo.Teacher.Audit.RunLog).Clear()
        // 実際のツール呼び出し明細はセッション履歴と監査の事象から描く。
        Do ..ShowTrajectory(session, 0, runId)
        If $IsObject(runErr) Throw runErr
        Write "=== 最終応答 ===", !
        Do ..Say(response.Content)
        Write !
        Set st = session.GetStats()
        Write "=== 集計 ===", !, "反復 ", monitor.Iterations, " 回 / ツール呼び出し ", st."total_tool_calls", " 回 / 累計トークン ", st."total_prompt_tokens" + st."total_completion_tokens", !
    } Catch ex {
        Write "エラー: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
    Return $$$OK
}

/// 対話モード: session を1つ作り、入力ごとに Run(ツール呼び出し・権限ゲート・ベクトル検索)を回す。
/// session が履歴を保持するので前のやり取りを踏まえた応答になる。通常は応答だけを返し、`/trace` と
/// 入力したときに直前の応答の実行軌跡と集計を表示する(`/help` でコマンド一覧)。
/// 実行者のロール(RBAC)で見える・使えるツールが変わる点は RunLesson と同じ。
/// `quit`(または空行)で終了。日本語表示のため `-it` で入ったセッションで実行する。
///
///   DEMO> do ##class(Demo.Teacher.Teacher).Talk()
ClassMethod Talk(maxIterations As %Integer = 6) As %Status
{
    Try {
        Set agent = ..%New()
        Set sc = agent.%Init()
        If $$$ISERR(sc) Return sc
        Return ..TalkWith(agent, maxIterations)
    } Catch ex {
        Write "エラー: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
}

/// 初期化済みエージェントで対話ループを回す(session 作成→READ→Run→trajectory)。
/// %Init(=LLM シークレット解決。特権が要る)と会話(=ツール認可を呼び出し元のロールで評価)を
/// 分離したいときに使う。RunAs.TalkAs が「特権で %Init → ユーザに切替 → ここを実行」に用いる。
/// session はログイン後に作るので、ツールの可視性は切替後のロールで絞られる。
ClassMethod TalkWith(agent As Demo.Teacher.Teacher, maxIterations As %Integer = 6) As %Status
{
    Try {
        Set cy = ..#CY, green = ..#GREEN, blue = ..#BLUE, gray = ..#GRAY, bold = ..#BOLD, clr = ..#CLR
        // コマンド案内(ヘッダ・各応答のあと・/help で同じ文言を出す)。
        Set cmds = "/trace: 直前の応答の軌跡と集計  /quit: 終了"
        // 役割をプラットフォームの権限から確定し、その役割の指示だけでセッションを作る。
        // 役割が無い・見えるツールと食い違うときは対話を始めない(fail-closed)。
        Set sc = agent.ApplyRole()
        If $$$ISERR(sc) {
            Write ..#RED, "起動できません: ", $System.Status.GetErrorText(sc), clr, !
            Return sc
        }
        Set session = agent.CreateSession()
        // 会話 ID(RunLog の SessionId)とターン番号。ターンごとのラン(RunId)をこの会話で束ねる。
        Set sessionId = $System.Util.CreateGUID(), turnNo = 0
        Write gray, "============================================================", clr, !
        Write bold, cy, "  先生エージェント (AI Hub / 情報セキュリティ・コンプライアンス研修)", clr, !
        Write gray, "  見える・使えるツールは実行ユーザのロール(RBAC)で変わります", clr, !
        Write gray, "  ", cmds, clr, !
        Write gray, "============================================================", clr, !
        Write !, gray, "Provider : ", clr, green, agent.ProviderName, clr, gray, "  (", agent.ConfigName, ")", clr, !
        Write gray, "Model    : ", clr, green, agent.Model, clr, !
        Write gray, "実行ユーザ: ", clr, green, $Username, clr, gray, "  (roles=", $Roles, ")", clr, !
        Write gray, "役割     : ", clr, green, bold, ..RoleLabel(agent.Role), clr, !, !
        // 最初に、役割ごとの「できること」を案内する(固定文。LLM には生成させない)。
        Do ..Greet(agent.Role)
        // 直前ターンの trajectory 起点とラン情報。/trace で当該ターン分だけ描くために覚えておく(-1=未実行)。
        Set lastFrom = -1, lastRun = ""
        For {
            Write !, blue, bold, "あなた(", $Username, ")", clr, blue, "> ", clr
            // READ は Enter で改行を出さないので、読み終えたら改行する。
            Read goal, !
            // 貼り付け等で前後に空白が混じっても /trace・quit 等のコマンドが効くよう正規化する。
            Set goal = $ZStrip(goal, "<>W")
            // 他のコマンド(/trace・/help)に合わせて /quit・/exit でも終了できるようにする。
            If (goal="")||$ListFind($ListBuild("quit","exit","/quit","/exit"), $ZConvert(goal,"L")) { Quit }
            // /trace: 直前の応答の実行軌跡と集計を表示する。
            If $ZConvert(goal,"L")="/trace" {
                If lastFrom<0 {
                    Write gray, "  (まだ表示できる軌跡がありません。先に質問してください。)", clr, !
                } Else {
                    Do ..ShowTrajectory(session, lastFrom, lastRun)
                    Set st = session.GetStats()
                    Write "=== 集計(累計)===", !, "ツール呼び出し ", st."total_tool_calls", " 回 / トークン ", st."total_prompt_tokens" + st."total_completion_tokens", !
                }
                Continue
            }
            // /help: 使えるコマンドを表示する。
            If $ZConvert(goal,"L")="/help" {
                Write gray, "  ", cmds, "(空行でも終了)", clr, !
                Continue
            }
            // このターンで追加されるメッセージの開始位置(/trace で当該分だけ描くため)。
            Set from = session.MessageCount()
            // 進捗表示はグレーで控えめに出す。
            Write gray, "  (考え中…)", clr, !
            // 通常のターンは応答だけを返す(会話を読みやすく保つ)。軌跡は /trace で見せる。
            // ターンごとにラン(ID・実行ユーザ・状態)を記録し、失敗しても対話は続ける。
            Set turnNo = turnNo + 1
            Set runId = ##class(Demo.Teacher.Audit.RunLog).Begin(sessionId, goal, turnNo, maxIterations)
            Set monitor = ##class(Demo.Teacher.Monitor).%New()
            Set monitor.Quiet = 1
            Set runErr = ""
            Try {
                Set response = agent.Run(session, goal, maxIterations, monitor)
                Do ##class(Demo.Teacher.Audit.RunLog).Complete(runId, session, response, monitor.Iterations)
            } Catch runErr {
                Do ##class(Demo.Teacher.Audit.RunLog).Fail(runId, runErr, monitor.Iterations)
            }
            Do ##class(Demo.Teacher.Audit.RunLog).Clear()
            Set lastFrom = from, lastRun = runId
            If $IsObject(runErr) {
                Write ..#RED, "エラー: ", runErr.DisplayString(), clr, !
            } Else {
                Write cy, bold, "先生", clr, cy, "> ", clr, !
                Do ..Say(response.Content)
                Write !
            }
            Write gray, "  ", cmds, clr, !
        }
        Write !, gray, "=== 終了 ===", clr, !
    } Catch ex {
        Write ..#RED, "エラー: ", ex.DisplayString(), ..#CLR, !
        Return ex.AsStatus()
    }
    Return $$$OK
}

/// 対話の冒頭で、役割ごとの「できること」を案内する。
/// 案内は役割(プラットフォームの権限で確定)から選ぶ固定文で、LLM には生成させない
/// (LLM が役割を読み違えて別の役割で自己紹介することを防ぐ)。
ClassMethod Greet(role As %String) [ Private ]
{
    Set student = $ListBuild(
        "規程の解説: 「〜について教えて」→ 社内規程を検索し、出典(条番号)付きで解説します",
        "練習問題: 「問題を出して」→ 既存の練習問題から1問出題します",
        "採点: 設問への解答を書く → 点数と講評を返し、学習履歴に登録します",
        "成績表: 「成績表を見せて」→ 平均点・弱点分野をまとめて表示します")
    Set qadmin = $ListBuild(
        "設問の棚卸し: 「既存の問題一覧を見せて」→ 重複や手薄な分野を確認します",
        "作問: 「〜の規程から設問を作って」→ 規程を根拠に設問・模範解答・採点基準を作ります",
        "登録: 作成した設問を教材に登録します(登録の前に、あなたの承認を求めます)")
    Write ..#CY, ..#BOLD, "先生", ..#CLR, ..#CY, "> ", ..#CLR, !
    Write "情報セキュリティ・コンプライアンス研修の先生エージェントです。", !
    If role = "student" {
        Write "生徒として学習をサポートします。できること:", !
        Set items = student
    } ElseIf role = "qadmin" {
        Write "設問管理者として作問をサポートします。できること:", !
        Set items = qadmin
    } Else {
        Write "管理用(生徒・設問管理者の両方の機能)として動作します。できること:", !
        Set items = student _ qadmin
    }
    For i = 1:1:$ListLength(items) { Write "  - ", $ListGet(items, i), ! }
    If role = "student" Write ..#GRAY, "(新しい設問の作成は、設問管理者の機能です。)", ..#CLR, !
    If role = "qadmin" Write ..#GRAY, "(出題・採点・成績表は、生徒向けの機能です。)", ..#CLR, !
}

/// 1ランの trajectory(要求→判断→ツール呼び出し→ツール結果→回答)を描く。
/// 骨格はセッションの会話履歴(from 以降のメッセージ = 当該ターン分)。そこへ永続監査(ToolCallLog)の
/// 事象を ToolCallId で突き合わせ、ラン内連番 Seq の順に「承認・認可の判断 → ツール実行(所要 ms)」を並べる。
/// 会話履歴を骨格にするのは、監査ポリシーを通らないツール(SearchPolicy = KnowledgeBase)も漏らさず出すため。
/// runId(RunLog)を渡すと、見出しにラン ID(先頭 8 桁)・実行ユーザ・状態・反復・所要秒を出す。
/// 表示は兄弟リポジトリ aihub-demo の /trace に揃える。
///
/// 表示するのは RunAs で切り替えたデモユーザ(監査表の SQL 権限なし)なので、動的 SQL ではなく
/// 埋め込み SQL とオブジェクトアクセス(RunIdIdxOpen)で読む(実行時の SQL 権限チェックを受けない)。
ClassMethod ShowTrajectory(session As %AI.Agent.Session, from As %Integer = 0, runId As %String = "") As %Status
{
    Set cy = ..#CY, green = ..#GREEN, gray = ..#GRAY, red = ..#RED, bold = ..#BOLD, clr = ..#CLR
    Set rule = "============================================================"
    Set run = $Select(runId = "": "", 1: ##class(Demo.Teacher.Audit.RunLog).RunIdIdxOpen(runId))
    // 要求(このランの最初の利用者メッセージ)と最終回答(最後のツール呼び出しなし応答)。RunLog にあればそちらを使う。
    Set goal = "", final = ""
    For i = from:1:session.MessageCount()-1 {
        Set m = session.GetMessage(i)
        If (m.role = "user"), (goal = "") Set goal = m.content
        If (m.role = "assistant"), '$IsObject(m.%Get("tool_calls")) Set final = m.content
    }
    If $IsObject(run) {
        Set:run.Prompt'="" goal = run.Prompt
        Set:run.FinalAnswer'="" final = run.FinalAnswer
    }

    Write !, gray, rule, clr, !
    Write bold, cy, "  トラジェクトリ(1ランの軌跡 / Trajectory)", clr, !
    If $IsObject(run) {
        Write gray, "  Run: ", clr, $Extract(run.RunId, 1, 8),
              gray, "   実行ユーザ: ", clr, green, run.Username, clr,
              gray, "   状態: ", clr, $Select(run.Status = "completed": green, 1: red), run.Status, clr, !
    }
    // 要求は切り詰めずに全文を出す(改行・タブだけ空白に潰す)。
    Write gray, "  要求: ", clr, ..OneLine(goal, $Length(goal)), !
    If $IsObject(run) {
        Write gray, "  反復: ", run.Iterations, "/", run.MaxIterations, "   所要: ", $FNumber(run.Seconds, "", 2), " 秒", clr, !
        If run.ErrorText '= "" Write red, "  エラー: ", ..OneLine(run.ErrorText, 70), clr, !
    }
    Write gray, rule, clr, !

    // このランの監査事象を ToolCallId・Seq で引けるようにする: evt(callId, seq) = $lb(kind, 成否, ms, 説明)。
    // 説明は記録時の要約(承認/却下/差し戻し: 指示 など)。無ければエラー文。
    Kill evt
    If runId '= "" {
        &sql(DECLARE TrajEvt CURSOR FOR
             SELECT Seq, Kind, ToolCallId, Success, DurationMs, ResultPreview, ErrorText
               INTO :seq, :kind, :cid, :ok, :ms, :preview, :errText
               FROM Demo_Teacher_Audit.ToolCallLog
              WHERE RunId = :runId
              ORDER BY Seq)
        &sql(OPEN TrajEvt)
        For {
            &sql(FETCH TrajEvt)
            Quit:SQLCODE'=0
            Set evt($Select(cid = "": " ", 1: cid), +seq) = $ListBuild(kind, ok, ms, $Select(preview '= "": preview, 1: errText))
        }
        &sql(CLOSE TrajEvt)
    }

    // ステップ: 事象ごとに1行(種別・ツール名・所要 ms)+ 説明/結果プレビュー1行。
    // tool_call_id → ツール名 を assistant の tool_calls から引けるようにしておく。
    Set step = 0
    For i = from:1:session.MessageCount()-1 {
        Set m = session.GetMessage(i)
        If m.role = "assistant", $IsObject(m.%Get("tool_calls")) {
            Set it = m.%Get("tool_calls").%GetIterator()
            While it.%GetNext(.k, .tc) { Set names(tc.id) = tc.name }
            Continue
        }
        Continue:m.role'="tool"
        Set callId = m.%Get("tool_call_id"), name = $Get(names(callId), "?")
        // (a) 実行前の判断(承認・認可の拒否)。拒否されたらツールは実行されない。
        Set ran = 0, blocked = 0, toolRec = ""
        Set seq = ""
        For {
            Set seq = $Order(evt(callId, seq), 1, e)
            Quit:seq=""
            If $ListGet(e, 1) = "tool" { Set toolRec = e  Continue }
            Set ok = $ListGet(e, 2), blocked = blocked || 'ok
            Set label = $Select($ListGet(e, 1) = "approval": "Approval", 1: "Authz")
            Set step = step + 1
            Write $Justify(step, 4), "  ", $Select(ok: green, 1: red), $Extract(label _ "          ", 1, 10), clr,
                  bold, $Extract(name _ "                  ", 1, 18), clr, !
            Write "        ", $Select(ok: gray, 1: red), ..OneLine($ListGet(e, 4), 70), clr, !
        }
        // 拒否された呼び出しは、上の判断の行が結果そのもの(ツール結果はその拒否メッセージ)。
        Continue:blocked&&(toolRec="")
        // (b) ツール実行。所要 ms・成否は監査ポリシーの記録から(SearchPolicy のように監査を通らないツールには無い)。
        Set failed = (toolRec '= "") && '$ListGet(toolRec, 2)
        Set ms = $Select(toolRec = "": "", 1: "[" _ $ListGet(toolRec, 3) _ "ms]")
        Set content = m.content
        Set step = step + 1
        Write $Justify(step, 4), "  ", $Select(failed: red, 1: cy), $Extract($Select(failed: "Error", 1: "Tool") _ "          ", 1, 10), clr,
              bold, $Extract(name _ "                  ", 1, 18), clr, " ", gray, ms, clr, !
        Write "        ", $Select(failed: red, 1: gray), ..OneLine(content, 70), $Select($Length(content) > 70: "...", 1: ""), clr, !
    }
    If step = 0 Write gray, "  (ツール呼び出しなし)", clr, !

    Write gray, "── 最終回答 ────────────────────────────", clr, !
    Write "  ", ..OneLine(final, 70), $Select($Length(final) > 70: "...", 1: ""), !
    Return $$$OK
}

/// 改行を CRLF に正規化して書き出す(TTY で LF だけだと行頭に戻らず段組みがずれるため)。
ClassMethod Say(text As %String) [ Private ]
{
    Set text = $Replace(text, $Char(13, 10), $Char(10))
    Set text = $Replace(text, $Char(10), $Char(13, 10))
    Write text
}

/// 改行・タブを空白に潰し、先頭 max 文字だけを1行プレビューとして返す。
ClassMethod OneLine(text As %String, max As %Integer = 60) As %String [ Private ]
{
    Set text = $Translate(text, $Char(13, 10, 9), "   ")
    Return $Extract(text, 1, max)
}

}
