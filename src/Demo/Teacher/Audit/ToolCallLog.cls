/// 先生エージェントのツール実行を1件ずつ永続化する監査ログ。
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

/// 記録時刻の降順で照会するためのインデックス。
Index CreatedAtIdx On CreatedAt;

}
