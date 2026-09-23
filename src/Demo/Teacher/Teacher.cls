/// 先生エージェント: 社内ポリシー(情報セキュリティ・コンプライアンス)研修のトレーナー。
///
/// [[Demo.Agent.Base]] を継承し、プロバイダは ConfigStore / Wallet から自動採用する。
/// プレインエージェントとの違いは「ツールを持ち、権限で振る舞いが変わる」点:
///
///   - SearchPolicy(ベクトル検索の KnowledgeBase)… 規程を出典付きで検索。誰でも可。
///   - Demo.Teacher.ToolSet … 採点・成績表(生徒)/ 作問(設問管理者)。<class>Demo.Teacher.RoleGuard</class>
///       が付与され、実行者のロール(IRIS の RBAC)に応じて見える・使えるツールが変わる。
///
/// 権限差の実演は [[Demo.Teacher.RunAs]]、思考と行動の可視化は [[Demo.Teacher.Monitor]]。
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

XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
# 役割

あなたは社会人向けの「情報セキュリティ・コンプライアンス研修」を支援するエージェントです。
日本語で丁寧に対応します。あなたは呼び出し元の権限を「使えるツールの有無」として受け取ります。
**使えないツールは呼ばないだけでなく、その機能を「できること」として案内してもいけません。**

## 相手の判定(最初に必ず・ツールで決める)

自己紹介・案内・振る舞いは、次の判定に厳密に従う。役割をまたいだ機能を持ち出さない。

- **RegisterQuestion が使える → あなたは【設問管理者】の支援役**。主務は作問(既存の棚卸し → 規程を
  根拠に生成 → 登録)。**採点・成績表・生徒への出題は行わない**(それらのツールは無く、生徒向けの機能)。
  ListPracticeQuestions は「既存設問の棚卸し(重複回避・手薄分野の把握)」に使うツールであって、
  利用者に問題を出して解かせ・採点するためのものではない。
- **GradeMyAnswer / ShowReportCard が使える → あなたは【生徒】の学習支援役**。「教わる → 練習 → 採点 →
  復習」で伴走する。**作問はできない**。
- どちらのツール群も無い(SearchPolicy だけ)→ 規程検索の一般支援に徹する。

## 共通

- 規程に関わる質問には、まず **SearchPolicy** で社内規程を検索し、**出典(条番号)を添えて**答える。
  推測で規程内容を断定しない。
- 模範解答・採点基準の全文は生徒に開示しない。採点時も点数と観点のフィードバックに留める。

## 生徒として(GradeMyAnswer / ShowReportCard が使えるとき)

生徒の学びは「**教わる → 練習 → 採点 → 復習**」の一周で進める。最初に何を頼めばよいか分からない生徒には、
まず分野の**解説(教わること)**から入れるよう促す。

- 「〜について教えて」「〜がわからない」と言われたら、**SearchPolicy** で該当規程を検索し、**出典(条番号)を
  添えて**やさしく解説する。解説の最後に「この分野の練習問題を1問やってみますか?」と**練習を提案**する。
- 「問題を出して」「練習したい」と言われたら、**ListPracticeQuestions** で練習問題を取得し、1問(分野の
  指定があれば該当分)を questionId とともに提示する。**新しい設問は作れない**(作問は設問管理者の権限)ので、
  既存の練習問題から出題し、解答を書いてもらう。
- 生徒が設問への解答を書いてきたら、**GradeMyAnswer** で採点する(点数と講評が学習履歴に登録される)。
  採点後は、点数・到達/未達の観点・出典を分かりやすく伝え、**未達の観点は該当規程を SearchPolicy で
  もう一度解説**して復習につなげる。そのうえで最後に「**成績表を表示しますか?**」と、これまでの学習の
  ふり返り(ShowReportCard)を**やさしく提案**する。
- 「成績」「成績表」「これまでの結果」を求められたら **ShowReportCard** で本人の履歴を取得し、
  平均点・傾向・弱点分野を要約した成績表を作って見せ、**弱点分野の解説や練習を提案**する。
- 設問の内容が曖昧なときは、questionId を確認してから採点する。

## 設問管理者として(RegisterQuestion が使えるとき)

- 「問題一覧」「どんな設問がある?」「既存の問題を見せて」と言われたら、**ListPracticeQuestions**
  (共有ツール)で既存の設問一覧を提示する。作問の前に既存問題を確認し、**重複を避け、手薄な分野を
  補う**のに使う。これは**棚卸し**であって、利用者に問題を出して解かせ・採点することはしない
  (出題・採点・成績表は生徒向けの機能で、設問管理者の権限では扱えない)。
- 新しい設問の作成を求められたら、まず **SearchPolicy** で根拠となる規程を調べ、その内容に沿って
  設問文・模範解答・採点基準・採点キーポイントを作り、**RegisterQuestion** で登録する。既存一覧と
  重複しない設問にする。登録後は作成した設問と出典を報告する。
- **登録は人間の承認を経る**(human-in-the-loop)。RegisterQuestion が「人間のフィードバックにより
  差し戻されました。次の指示に従って…」というエラーで失敗したら、それは拒否ではなく**修正の指示**。
  その指示(例: もっと難しく / カテゴリを変更 / 観点を追加)に沿って設問を**作り直し**、改めて
  **RegisterQuestion** を実行する。承認されるまで、この「作り直して再提案」を繰り返す。
  「人間の承認ゲートで却下されました」で失敗したら、登録は取りやめ、その旨を穏やかに伝える。
- 採点キーポイント(keyPoints)は "観点名=語1|語2;観点名=語1|語2" の形式で、語は解答に含まれうる語で作る。

## 権限が無いとき

- 使えないツール(カタログに無いツール)は呼ばない。生徒に作問はできず、設問管理者に採点・成績表は無い。
  求められても、権限が無い旨を穏やかに伝え、できることを案内する。
- 回答は簡潔に。専門用語には一言の補足を添える。
}

/// %OnInit: プロバイダ決定(親)に続けて、検索ツールとツールセットを登録する。
Method %OnInit() As %Status
{
    Set sc = ##super()
    If $$$ISERR(sc) Return sc

    // 権限で見え方が変わるツール群(RoleGuard 付き)を LLM に提示する。
    Do ..UseToolSet("Demo.Teacher.ToolSet")

    // 規程検索(KnowledgeBase)。要件なし=誰でも利用可。教材未構築なら黙ってスキップ。
    Set sc = ##class(Demo.Teacher.Setup).OpenKnowledgeBase(.kb)
    If $$$ISOK(sc), $IsObject(kb) {
        Do kb.AddToAgent($this)
    }
    Return $$$OK
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
        Set session = agent.CreateSession()
        Set monitor = ##class(Demo.Teacher.Monitor).%New()
        Write "=== ゴール ===", !, goal, !, "=== 反復(ハーネスの観測点)===", !
        Set response = agent.Run(session, goal, maxIterations, monitor)
        // 実際のツール呼び出し明細はセッション履歴から描く。
        Do ..ShowTrajectory(session)
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
/// 入力したときに直前の応答の軌跡(思考と行動の連鎖)と集計を表示する(`/help` でコマンド一覧)。
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
        Set session = agent.CreateSession()
        Write gray, "============================================================", clr, !
        Write bold, cy, "  先生エージェント (AI Hub / 情報セキュリティ・コンプライアンス研修)", clr, !
        Write gray, "  見える・使えるツールは実行ユーザのロール(RBAC)で変わります", clr, !
        Write gray, "  ", cmds, clr, !
        Write gray, "============================================================", clr, !
        Write !, gray, "Provider : ", clr, green, agent.ProviderName, clr, gray, "  (", agent.ConfigName, ")", clr, !
        Write gray, "Model    : ", clr, green, agent.Model, clr, !
        Write gray, "実行ユーザ: ", clr, green, $Username, clr, gray, "  (roles=", $Roles, ")", clr, !, !
        // 最初に、いま使えるツールに基づいて「できること」を開示する。
        // ツールはロール(RBAC)で絞られているので、開示内容も呼び出し元のロールで自動的に変わる。
        Do ..Greet(agent, session, maxIterations)
        // 直前ターンの trajectory 起点。/trace で当該ターン分だけ描くために覚えておく(-1=未実行)。
        Set lastFrom = -1
        For {
            Write !, blue, bold, "あなた(", $Username, ")", clr, blue, "> ", clr
            // READ は Enter で改行を出さないので、読み終えたら改行する。
            Read goal, !
            // 貼り付け等で前後に空白が混じっても /trace・quit 等のコマンドが効くよう正規化する。
            Set goal = $ZStrip(goal, "<>W")
            // 他のコマンド(/trace・/help)に合わせて /quit・/exit でも終了できるようにする。
            If (goal="")||$ListFind($ListBuild("quit","exit","/quit","/exit"), $ZConvert(goal,"L")) { Quit }
            // /trace: 直前の応答の軌跡(思考と行動の連鎖)と集計を表示する。
            If $ZConvert(goal,"L")="/trace" {
                If lastFrom<0 {
                    Write gray, "  (まだ表示できる軌跡がありません。先に質問してください。)", clr, !
                } Else {
                    Do ..ShowTrajectory(session, lastFrom)
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
            Set response = agent.Run(session, goal, maxIterations, "")
            Set lastFrom = from
            Write cy, bold, "先生", clr, cy, "> ", clr, !
            Do ..Say(response.Content)
            Write !
            Write gray, "  ", cmds, clr, !
        }
        Write !, gray, "=== 終了 ===", clr, !
    } Catch ex {
        Write ..#RED, "エラー: ", ex.DisplayString(), ..#CLR, !
        Return ex.AsStatus()
    }
    Return $$$OK
}

/// 対話の冒頭で、いま使えるツールに基づいて「できること」を利用者に簡潔に開示する。
/// ツールは呼び出し元のロールで絞られているので、開示内容も生徒/設問管理者で自動的に変わる
/// (利用者が最初に何を頼めるか分かるようにする)。
ClassMethod Greet(agent As Demo.Teacher.Teacher, session As %AI.Agent.Session, maxIterations As %Integer = 6) [ Private ]
{
    Set prompt = "利用者への最初の挨拶です。いまあなたが使えるツールを踏まえ、この場でできることを箇条書きで簡潔に日本語で自己紹介してください。まだツールは呼ばず、案内だけにしてください。"
    Set response = agent.Run(session, prompt, maxIterations, "")
    Write ..#CY, ..#BOLD, "先生", ..#CLR, ..#CY, "> ", ..#CLR, !
    Do ..Say(response.Content)
    Write !
}

/// セッションの会話履歴から trajectory(質問→判断→ツール呼び出し→ツール結果→回答)を描く。
/// from を指定すると、その位置以降のメッセージだけを描く(対話モードで当該ターン分だけ出すため)。
ClassMethod ShowTrajectory(session As %AI.Agent.Session, from As %Integer = 0) As %Status
{
    Write "=== trajectory(思考と行動の連鎖)===", !
    For i = from:1:session.MessageCount()-1 {
        Set m = session.GetMessage(i)
        Set role = m.role
        If role = "user" {
            Write "  👤 質問: ", ..OneLine(m.content, 60), !
        }
        ElseIf role = "assistant" {
            If $IsObject(m.%Get("tool_calls")) {
                Set it = m.%Get("tool_calls").%GetIterator()
                While it.%GetNext(.k, .tc) {
                    Write "  🤖→🔧 ツール呼び出し: ", tc.name, " ", ..OneLine($Select($IsObject(tc.arguments): tc.arguments.%ToJSON(), 1: tc.arguments), 80), !
                }
            }
            Else {
                Write "  🤖 回答を生成(", $Length(m.content), " 文字)", !
            }
        }
        ElseIf role = "tool" {
            Write "  🔧→🤖 ツール結果: ", ..OneLine(m.content, 50), "…", !
        }
    }
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
