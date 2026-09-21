/// 先生エージェント: 社内ポリシー(情報セキュリティ・コンプライアンス)研修のトレーナー。
///
/// [[Demo.Agent.Base]] を継承し、プロバイダは ConfigStore / Wallet から自動採用する。
/// プレインエージェントとの違いは「ツールを持ち、権限で振る舞いが変わる」点:
///
///   - SearchPolicy(ベクトル検索の KnowledgeBase)… 規程を出典付きで検索。誰でも可。
///   - Demo.Teacher.ToolSet … 学習支援 / 模範解答 / 採点。<class>Demo.Teacher.RoleGuard</class>
///       が付与され、実行者のロール(IRIS の RBAC)に応じて見える・使えるツールが変わる。
///
/// 権限差の実演は [[Demo.Teacher.RunAs]]、思考と行動の可視化は [[Demo.Teacher.Monitor]]。
/// 教材の投入・インデックス構築は [[Demo.Teacher.Setup]] を先に実行しておくこと。
Class Demo.Teacher.Teacher Extends Demo.Agent.Base
{

XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
# 役割

あなたは社会人向けの「情報セキュリティ・コンプライアンス研修」トレーナーです。
受講者が社内ポリシーを正しく理解できるよう、日本語で丁寧に導きます。

## 方針

- 規程に関わる質問には、まず **SearchPolicy** で社内規程を検索し、**出典(条番号)を添えて**答える。
  推測で規程内容を断定しない。
- 受講者の設問には **GetHint** で「調べるべき分類・観点」を示し、答えそのものは与えない。
- 模範解答の参照(GetAnswerKey)、学習履歴の閲覧(ViewProgress)、採点(RecordScore)は
  **監査者(トレーナー)権限がある場合のみ**利用できる。権限が無ければ、それらのツールは
  そもそも見えない。見えないツールを使おうとしない。
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
        If $$$ISERR(sc) Return sc
        Set session = agent.CreateSession()
        Set monitor = ##class(Demo.Teacher.Monitor).%New()
        Write "=== ゴール ===", !, goal, !, "=== 反復(ハーネスの観測点)===", !
        Set response = agent.Run(session, goal, maxIterations, monitor)
        // 実際のツール呼び出し明細はセッション履歴から描く。
        Do ..ShowTrajectory(session)
        Write "=== 最終応答 ===", !, response.Content, !
        Set st = session.GetStats()
        Write "=== 集計 ===", !, "反復 ", monitor.Iterations, " 回 / ツール呼び出し ", st."total_tool_calls", " 回 / 累計トークン ", st."total_prompt_tokens" + st."total_completion_tokens", !
    } Catch ex {
        Write "エラー: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
    Return $$$OK
}

/// セッションの会話履歴から trajectory(質問→判断→ツール呼び出し→ツール結果→回答)を描く。
ClassMethod ShowTrajectory(session As %AI.Agent.Session) As %Status
{
    Write "=== trajectory(思考と行動の連鎖)===", !
    For i = 0:1:session.MessageCount()-1 {
        Set m = session.GetMessage(i)
        Set role = m.role
        If role = "user" {
            Write "  👤 質問: ", $Extract(m.content, 1, 60), !
        }
        ElseIf role = "assistant" {
            If $IsObject(m.%Get("tool_calls")) {
                Set it = m.%Get("tool_calls").%GetIterator()
                While it.%GetNext(.k, .tc) {
                    Write "  🤖→🔧 ツール呼び出し: ", tc.name, " ", $Select($IsObject(tc.arguments): tc.arguments.%ToJSON(), 1: tc.arguments), !
                }
            }
            Else {
                Write "  🤖 回答を生成(", $Length(m.content), " 文字)", !
            }
        }
        ElseIf role = "tool" {
            Write "  🔧→🤖 ツール結果: ", $Extract(m.content, 1, 50), "…", !
        }
    }
    Return $$$OK
}

}
