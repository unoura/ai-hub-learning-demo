Include %occStatus

/// 先生エージェントのツール実行(および認可・承認の事象)を1件ずつ永続化する監査ログ。
///
/// AI Hub の監査ポリシー <class>Demo.Teacher.Audit.PersistentAudit</class>(<class>%AI.Policy.Audit</class> 継承)が
/// ツール実行のたびに1行 <method>%Save</method> する。<b>誰が(切替後のデモユーザ)・いつ・どのツールを・
/// 成否・所要 ms</b> が、その会話が終わっても DB に残り、後から SQL / オブジェクトで照会できる。
///
/// trajectory(セッション履歴からの再構成)は会話が終われば揮発するのに対し、こちらは
/// <b>プラットフォーム側に残る永続監査証跡</b>。RBAC(見えるツール/取れる行動)× 永続監査の層になる。
/// (IRIS の「システム監査DB」= <method>$SYSTEM.Security.Audit</method> とは別物。用途で使い分ける。)
///
/// SQL テーブル名は既定で Demo_Teacher_Audit.ToolCallLog。
Class Demo.Teacher.Audit.ToolCallLog Extends (%Persistent, %JSON.Adaptor)
{

/// 記録時刻(ISO 相当 "YYYY-MM-DD HH:MM:SS")。
Property CreatedAt As %String(MAXLEN = 32);

/// 実行したユーザ($USERNAME)。RBAC デモで「誰が何を呼んだか」を残す要。
Property Username As %String(MAXLEN = 128);

/// ツール呼び出しの一意ID(call.id)。
Property ToolCallId As %String(MAXLEN = 128);

/// 呼ばれたツール名(call.name)。
Property ToolName As %String(MAXLEN = 128);

/// 呼び出し引数(call.arguments)の JSON 文字列。
Property Arguments As %String(MAXLEN = "");

/// 成否($$$ISOK(status))。
Property Success As %Boolean;

/// 実行時間(ミリ秒)。
Property DurationMs As %Integer;

/// 戻り値 JSON(result_json)の長さ。
Property ResultSize As %Integer;

/// 戻り値 JSON の先頭 1000 文字(全文は保持しない)。
Property ResultPreview As %String(MAXLEN = 1000);

/// 失敗時のエラーメッセージ($SYSTEM.Status.GetErrorText)。成功時は空。
Property ErrorText As %String(MAXLEN = "");

/// ラン ID(<class>Demo.Teacher.Audit.RunLog</class> の RunId)。trajectory 表示の「Run:」は先頭 8 桁で、
/// 画面の軌跡から永続監査の行をたどれる。ラン外(直接 ExecuteTool 等)の実行では空。
/// (Storage をソースに持たないため、既存データの格納位置を保つよう新規プロパティは末尾に足す。)
Property RunId As %String(MAXLEN = 64);

/// 会話 ID(RunLog の SessionId)。
Property SessionId As %String(MAXLEN = 64);

/// ラン内の事象の連番(1 始まり)。ツール実行・認可の拒否・承認の判断が同じ連番を共有する。
Property Seq As %Integer;

/// 事象の種別: tool(ツール実行)/ authorization(権限ゲートの拒否)/ approval(人手承認の判断)。
Property Kind As %String(MAXLEN = 32);

/// 記録時刻の降順で照会するためのインデックス。
Index CreatedAtIdx On CreatedAt;

/// ラン単位で照会するためのインデックス。
Index RunIdIdx On RunId;

/// ツール実行以外の事象(権限ゲートの拒否・人手承認の判断)を記録する。<class>Demo.Teacher.RoleGuard</class> から呼ぶ。
/// これらは実行に入らないので監査ポリシー(%LogExecution)を通らない。ランの外では記録しない。
///   kind     - authorization / approval
///   toolName - ツール名
///   call     - ツール呼び出し(call.id でツール実行の行・会話履歴と結べる)
///   status   - 判断の結果(承認は $$$OK、拒否・却下・差し戻しはエラー)
///   summary  - 1行の説明(例: 承認されました)
ClassMethod LogEvent(kind As %String, toolName As %String, call As %DynamicObject, status As %Status, summary As %String = "")
{
    Try {
        Set runId = ##class(Demo.Teacher.Audit.RunLog).CurrentRunId()
        Quit:runId=""
        Set log = ..%New()
        Set log.CreatedAt = $ZDateTime($Horolog, 3)
        Set log.Username = $Username
        Set log.RunId = runId
        Set log.SessionId = ##class(Demo.Teacher.Audit.RunLog).CurrentSessionId()
        Set log.Seq = ##class(Demo.Teacher.Audit.RunLog).NextSeq()
        Set log.Kind = kind
        Set log.ToolName = toolName
        If $IsObject(call) {
            Set log.ToolCallId = call.%Get("id")
            Set args = call.%Get("arguments")
            Set log.Arguments = $Select($IsObject(args): args.%ToJSON(), 1: args)
        }
        Set log.Success = $$$ISOK(status)
        Set log.ResultPreview = $Extract(summary, 1, 1000)
        If $$$ISERR(status) Set log.ErrorText = $System.Status.GetErrorText(status)
        Do log.%Save()
    } Catch ex {
        // 監査の失敗を認可判断に波及させない。痕跡はプロセス外グローバルに残す。
        Set ^Demo.Teacher.AuditError($Increment(^Demo.Teacher.AuditError)) = $ZDateTime($Horolog, 3) _ " LogEvent " _ ex.DisplayString()
    }
}

}
