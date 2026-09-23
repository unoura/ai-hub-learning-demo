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

XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
# 役割

あなたは社会人向けの「情報セキュリティ・コンプライアンス研修」を支援するエージェントです。
日本語で丁寧に対応します。対話相手が「生徒」か「設問管理者」かは、**利用できるツールで判断**します
(あなたは呼び出し元の権限を、使えるツールの有無として受け取ります)。使えないツールは呼びません。

## 共通

- 規程に関わる質問には、まず **SearchPolicy** で社内規程を検索し、**出典(条番号)を添えて**答える。
  推測で規程内容を断定しない。
- 模範解答・採点基準の全文は生徒に開示しない。採点時も点数と観点のフィードバックに留める。

## 生徒として(ListPracticeQuestions / GradeMyAnswer / ShowReportCard が使えるとき)

- 「問題を出して」「練習したい」と言われたら、**ListPracticeQuestions** で練習問題を取得し、1問(分野の
  指定があれば該当分)を questionId とともに提示する。**新しい設問は作れない**(作問は設問管理者の権限)。
  既存の練習問題から出題し、解答を書いてもらう。
- 生徒が設問への解答を書いてきたら、**GradeMyAnswer** で採点する(点数と講評が学習履歴に登録される)。
  採点後は、点数・到達/未達の観点・出典を分かりやすく伝え、次に調べるとよい規程を SearchPolicy で案内する。
- 「成績」「成績表」「これまでの結果」を求められたら **ShowReportCard** で本人の履歴を取得し、
  平均点・傾向・弱点分野を要約した成績表を作って見せる。
- 設問の内容が曖昧なときは、questionId を確認してから採点する。

## 設問管理者として(RegisterQuestion が使えるとき)

- 新しい設問の作成を求められたら、まず **SearchPolicy** で根拠となる規程を調べ、その内容に沿って
  設問文・模範解答・採点基準・採点キーポイントを作り、**RegisterQuestion** で登録する。登録後は
  作成した設問と出典を報告する。
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
        Set session = agent.CreateSession()
        Write "=== 先生エージェント 対話モード ===", !
        // 最初に、いま使えるツールに基づいて「できること」を開示する。
        // ツールはロール(RBAC)で絞られているので、開示内容も呼び出し元のロールで自動的に変わる。
        Do ..Greet(agent, session, maxIterations)
        Write !, "質問を入力してください。/trace=直前の応答の軌跡と集計を表示 / /help=ヘルプ / quit(空行)=終了", !
        // 直前ターンの trajectory 起点。/trace で当該ターン分だけ描くために覚えておく(-1=未実行)。
        Set lastFrom = -1
        For {
            Write !, "あなた> "
            Read goal
            If (goal="")||($ZConvert(goal,"L")="quit")||($ZConvert(goal,"L")="exit") { Quit }
            // /trace: 直前の応答の軌跡(思考と行動の連鎖)と集計を表示する。
            If $ZConvert(goal,"L")="/trace" {
                If lastFrom<0 {
                    Write "  (まだ表示できる軌跡がありません。先に質問してください。)", !
                } Else {
                    Do ..ShowTrajectory(session, lastFrom)
                    Set st = session.GetStats()
                    Write "=== 集計(累計)===", !, "ツール呼び出し ", st."total_tool_calls", " 回 / トークン ", st."total_prompt_tokens" + st."total_completion_tokens", !
                }
                Continue
            }
            // /help: 使えるコマンドを表示する。
            If $ZConvert(goal,"L")="/help" {
                Write "  コマンド: /trace=直前の応答の軌跡と集計を表示 / /help=このヘルプ / quit(または空行)=終了", !
                Continue
            }
            // このターンで追加されるメッセージの開始位置(/trace で当該分だけ描くため)。
            Set from = session.MessageCount()
            Write "  (考え中…)", !
            // 通常のターンは応答だけを返す(会話を読みやすく保つ)。軌跡は /trace で見せる。
            Set response = agent.Run(session, goal, maxIterations, "")
            Set lastFrom = from
            Write "=== 応答 ===", !
            Do ..Say(response.Content)
            Write !
            Write "  (/trace で直前の応答の軌跡と集計を表示)", !
        }
        Write !, "=== 終了 ===", !
    } Catch ex {
        Write "エラー: ", ex.DisplayString(), !
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
    Write "先生> ", !
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
