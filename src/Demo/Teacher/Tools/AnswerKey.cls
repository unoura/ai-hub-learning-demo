/// 模範解答参照ツール(監査者専用)。リソース `Demo_AnswerKey` で保護する。
/// 権限判定は ToolSet に取り付ける <class>Demo.Teacher.RoleGuard</class> に集約し、
/// ここは業務ロジックのみを持つ。
Class Demo.Teacher.Tools.AnswerKey Extends %AI.Tool
{

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# 模範解答ツール(監査者専用)

設問の模範解答と採点基準(ルーブリック)を参照する。受講者には見せない。
}

/// 設問の模範解答と採点基準(ルーブリック)を返す。監査者専用。
/// questionId: 設問のID。
Method GetAnswerKey(questionId As %Integer) As %DynamicObject
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT a.ModelAnswer, a.Rubric, q.Prompt FROM Demo_Teacher.AnswerKey a JOIN Demo_Teacher.Question q ON a.Question = q.ID WHERE a.Question = ?", questionId)
    If 'rs.%Next() Return {"error": ("模範解答が見つかりません: " _ questionId)}
    Set result = {}
    Set result.questionId = questionId
    Set result.prompt = rs.%Get("Prompt")
    Set result.modelAnswer = rs.%Get("ModelAnswer")
    Set result.rubric = rs.%Get("Rubric")
    Return result
}

}
