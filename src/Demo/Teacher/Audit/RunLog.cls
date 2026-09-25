Include %occStatus

/// ラン(エージェントの 1 回の Run 実行 = 対話の1ターン / 単発レッスン1回)の永続ログ。
///
/// <class>Demo.Teacher.Audit.ToolCallLog</class> が「ツール実行・認可・承認の事象を1行ずつ」残すのに対し、
/// こちらは「1ランの流れ」(誰の・どの要求が・どう終わったか・最終回答・集計)を束ねる親レコード。
/// ToolCallLog を RunId で結ぶと、1ラン分の事象を Seq 順に再構成できる。
///
/// ID の階層: SessionId(会話)⊃ RunId(1ラン)⊃ Seq(ラン内の事象の連番)。
/// SessionId は <class>Demo.Teacher.Teacher</class> が会話ごとに、RunId は <method>Begin</method> がランごとに採番する。
/// SDK の Session / Response にはラン ID や状態が無いため、ハーネス側で付与する。
///
/// 実行中のラン文脈はプロセス私有グローバル <var>^||Demo.Teacher.Traj</var> に載せ、監査ポリシー
/// (<class>Demo.Teacher.Audit.PersistentAudit</class>)と認可ポリシー(<class>Demo.Teacher.RoleGuard</class>)が
/// 「いまどのランの何番目の事象か」を知れるようにする。ObjectScript に Finally は無いので、
/// 呼び出し側は Try/Catch の後で必ず <method>Clear</method> する。
///
/// 設計は兄弟リポジトリ aihub-demo の <class>Demo.Admission.Audit.RunLog</class> に揃えている。
/// SQL テーブル名は既定で Demo_Teacher_Audit.RunLog。
Class Demo.Teacher.Audit.RunLog Extends (%Persistent, %JSON.Adaptor)
{

/// ラン文脈を載せるプロセス私有グローバル(JOB 子には引き継がれないので、ランを実行するプロセス内で立てる)。
Parameter CTXGLOBAL = "^||Demo.Teacher.Traj";

/// このランの一意 ID($SYSTEM.Util.CreateGUID())。ToolCallLog との結合キー。画面には先頭 8 桁を出す。
Property RunId As %String(MAXLEN = 64);

/// 会話 ID(同じ会話の複数ランを束ねる)。
Property SessionId As %String(MAXLEN = 64);

/// 会話内のターン番号(1 始まり)。
Property TurnNo As %Integer;

/// 開始時刻("YYYY-MM-DD HH:MM:SS")。
Property StartedAt As %String(MAXLEN = 32);

/// 終了時刻。Complete / Fail で設定。実行中は空。
Property EndedAt As %String(MAXLEN = 32);

/// 実行したユーザ($USERNAME)。RunAs でログインを切り替えた後の実 ID が残る。
Property Username As %String(MAXLEN = 128);

/// そのランの要求(利用者の入力)。
Property Prompt As %String(MAXLEN = "");

/// 最終回答(response.Content)。
Property FinalAnswer As %String(MAXLEN = "");

/// 状態: running / completed / failed。
Property Status As %String(MAXLEN = 32);

/// 失敗時のエラーメッセージ。成功時は空。
Property ErrorText As %String(MAXLEN = "");

/// 反復の上限(Run の maxIterations)。
Property MaxIterations As %Integer;

/// 実際に回った反復の数(Monitor が観測した値)。
Property Iterations As %Integer;

/// 所要秒(小数 2 桁)。
Property Seconds As %Numeric(SCALE = 2);

/// session.GetStats() の JSON(ツール呼び出し数・トークンなど。会話の累計)。
Property Stats As %String(MAXLEN = "");

Index RunIdIdx On RunId [ Unique ];

Index SessionIdIdx On SessionId;

/// 実行中のランの RunId(ランが開いていなければ "")。
ClassMethod CurrentRunId() As %String
{
    Return $Get(@..#CTXGLOBAL@("run"))
}

/// 実行中のランの SessionId。
ClassMethod CurrentSessionId() As %String
{
    Return $Get(@..#CTXGLOBAL@("session"))
}

/// ラン内の次の連番(Seq)を採番する。ツール実行・認可・承認の事象が共有する。
ClassMethod NextSeq() As %Integer
{
    Return $Increment(@..#CTXGLOBAL@("seq"))
}

/// ランを始める。ラン文脈を立て、RunLog 行(Status=running)を作って RunId を返す。
ClassMethod Begin(sessionId As %String, prompt As %String, turnNo As %Integer = 1, maxIterations As %Integer = "") As %String
{
    Set runId = $SYSTEM.Util.CreateGUID()
    Kill @..#CTXGLOBAL
    Set @..#CTXGLOBAL@("run") = runId
    Set @..#CTXGLOBAL@("session") = sessionId
    Set @..#CTXGLOBAL@("seq") = 0
    Set @..#CTXGLOBAL@("t0") = $ZHorolog
    Try {
        Set log = ..%New()
        Set log.RunId = runId
        Set log.SessionId = sessionId
        Set log.TurnNo = +turnNo
        Set log.StartedAt = $ZDateTime($Horolog, 3)
        Set log.Username = $Username
        Set log.Prompt = prompt
        Set log.Status = "running"
        Set log.MaxIterations = maxIterations
        Do log.%Save()
    } Catch ex {
        Do ..LogError("Begin", ex)
    }
    Return runId
}

/// ランを正常終了として閉じる(EndedAt / Status=completed / FinalAnswer / 反復・所要秒 / Stats)。
ClassMethod Complete(runId As %String, session As %AI.Agent.Session = "", response As %RegisteredObject = "", iterations As %Integer = "") As %Status
{
    Return ..Close(runId, "completed", session, response, iterations, "")
}

/// ランを失敗として閉じる(EndedAt / Status=failed / ErrorText)。Catch 経路から呼ぶ。
ClassMethod Fail(runId As %String, ex As %Exception.AbstractException = "", iterations As %Integer = "") As %Status
{
    Return ..Close(runId, "failed", "", "", iterations, $Select($IsObject(ex): ex.DisplayString(), 1: ""))
}

/// ラン文脈を片付ける。Try/Catch の後で必ず呼ぶ(ObjectScript に Finally は無い)。
ClassMethod Clear()
{
    Kill @..#CTXGLOBAL
}

/// Complete / Fail の共通部。監査の失敗を本処理に波及させない。
ClassMethod Close(runId As %String, status As %String, session, response, iterations As %Integer, errorText As %String) As %Status [ Private ]
{
    Quit:runId="" $$$OK
    Try {
        Set log = ..RunIdIdxOpen(runId)
        Quit:'$IsObject(log)
        Set log.EndedAt = $ZDateTime($Horolog, 3)
        Set log.Status = status
        Set log.Iterations = iterations
        Set t0 = $Get(@..#CTXGLOBAL@("t0"))
        If t0 '= "" Set log.Seconds = $ZHorolog - t0
        Set log.ErrorText = errorText
        If $IsObject(response) Set log.FinalAnswer = response.Content
        If $IsObject(session) {
            Try {
                Set stats = session.GetStats()
                Set log.Stats = $Select($IsObject(stats): stats.%ToJSON(), 1: stats)
            } Catch {}
        }
        Do log.%Save()
    } Catch ex {
        Do ..LogError(status, ex)
    }
    Return $$$OK
}

/// 記録の失敗はプロセス外グローバルに痕跡を残す(PersistentAudit と同じ置き場)。
ClassMethod LogError(where As %String, ex As %Exception.AbstractException) [ Private ]
{
    Set ^Demo.Teacher.AuditError($Increment(^Demo.Teacher.AuditError)) = $ZDateTime($Horolog, 3) _ " RunLog." _ where _ " " _ ex.DisplayString()
}

}
