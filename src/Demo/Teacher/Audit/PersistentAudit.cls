Include %occStatus

/// 先生エージェント用の永続監査ポリシー。ツール実行のたびに <class>%AI.Policy.Audit</class> の
/// <method>%LogExecution</method> が呼ばれ、その内容を <class>Demo.Teacher.Audit.ToolCallLog</class> に
/// 1行 <method>%Save</method> する。
///
/// <class>%AI.Policy.ConsoleAudit</class>(stdout に書くだけ・プロセス終了で消える)と違い、監査証跡が
/// DB に永続化されるので、後から SQL で「誰が・いつ・どのツールを・成否・所要 ms」を照会できる。
/// stdout に一切書かないため、対話モードや MCP 経由でも出力を汚さない。
///
/// 適用方法(2通り。このデモは (2) を採用):
///   1) コードから: Do agent.ToolManager.SetAuditPolicy(##class(Demo.Teacher.Audit.PersistentAudit).%New())
///   2) ToolSet の XData <Policies> に: <Audit Class="Demo.Teacher.Audit.PersistentAudit" />
///
/// <b>誰が</b>記録されるか: 監査は切替後のプロセスで走るので <var>$USERNAME</var> は
/// <class>Demo.Teacher.RunAs</class> で Login したデモユーザ(student01 / qadmin01)になる。
/// RBAC でツールが割れることと、その実行が別ユーザ名で監査に残ることを、そのまま対比できる。
Class Demo.Teacher.Audit.PersistentAudit Extends %AI.Policy.Audit
{

/// ツール実行(成功・失敗どちらも)を1件永続化する。
/// call:     ツール呼び出し。call.id / call.name / call.arguments(%DynamicObject)
/// metadata: ツールの Requirements(未使用)
/// result:   成功時のみ有効なラッパ。result.result_json(JSON文字列)/ result.display_text。失敗時は null
/// duration: 実行時間(ミリ秒)
/// status:   ツール実行の %Status
Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
    Try {
        Set log = ##class(Demo.Teacher.Audit.ToolCallLog).%New()
        Set log.CreatedAt = $ZDATETIME($HOROLOG, 3)
        Set log.Username = $USERNAME
        Set log.DurationMs = +duration
        Set log.Success = $$$ISOK(status)

        If $ISOBJECT(call) {
            Set log.ToolCallId = call.id
            Set log.ToolName = call.name
            // arguments は %DynamicObject の想定だが、文字列で渡る経路も許容する。
            If $ISOBJECT(call.arguments) {
                Set log.Arguments = call.arguments.%ToJSON()
            } Else {
                Set log.Arguments = call.arguments
            }
        }

        If $$$ISOK(status) {
            // 成功時: result は生の戻り値ではなくラッパ。JSON 文字列は result.result_json に入る。
            // result_json はキー名に "_" を含むため %Get で取得(ドット記法だと連結演算子に化ける)。
            Set resultJson = ""
            If $ISOBJECT(result) Set resultJson = result.%Get("result_json")
            Set log.ResultSize = $LENGTH(resultJson)
            Set log.ResultPreview = $EXTRACT(resultJson, 1, 1000)
        } Else {
            // 失敗時: result は null。エラーテキストを残す。
            Set log.ErrorText = $SYSTEM.Status.GetErrorText(status)
        }

        // 実行中のラン(Demo.Teacher.Audit.RunLog が文脈を立てる)に紐づけ、ラン内の連番を振る。
        // 認可・承認の事象(ToolCallLog.LogEvent)と同じ連番を共有するので、Seq 順に並べると軌跡になる。
        Set log.Kind = "tool"
        Set log.RunId = ##class(Demo.Teacher.Audit.RunLog).CurrentRunId()
        If log.RunId '= "" {
            Set log.SessionId = ##class(Demo.Teacher.Audit.RunLog).CurrentSessionId()
            Set log.Seq = ##class(Demo.Teacher.Audit.RunLog).NextSeq()
        }
        Do log.%Save()
    } Catch ex {
        // 監査の失敗をツール実行に波及させない。痕跡はプロセス外グローバルに残す。
        Set ^Demo.Teacher.AuditError($INCREMENT(^Demo.Teacher.AuditError)) = $ZDATETIME($HOROLOG, 3) _ " " _ ex.DisplayString()
    }
    Return $$$OK
}

}
