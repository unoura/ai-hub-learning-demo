Include %occStatus

/// 共有カタログツール。**要件リソースを持たない**ので、生徒・設問管理者のどちらからも見える
/// (SearchPolicy と同じ「誰でも」枠)。権限判定は ToolSet に取り付ける
/// <class>Demo.Teacher.RoleGuard</class> に集約するが、このクラスのツールには resource 要件を
/// 付けないため %CanList は常に掲載し、%CanExecute も素通しする。
///
///   - ListPracticeQuestions: 既存の設問一覧(questionId / category / prompt / difficulty)を返す。
///       模範解答・採点基準は返さない。生徒には「出題」、設問管理者には「作問前のカタログ確認
///       (重複回避・分野の把握)」として役立つ共有機能。
Class Demo.Teacher.Tools.Catalog Extends %AI.Tool
{

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# 設問カタログ(共有)

- 「問題を出して」「一覧を見せて」「どんな設問がある?」と言われたら ListPracticeQuestions で
  既存の設問一覧を取得して提示する。category を渡すと分野で絞れる。
- 生徒にとっては「出題」(既存問題から1問選んで解いてもらう)、設問管理者にとっては
  「作問前のカタログ確認」(既にある設問を見て重複を避け、手薄な分野を把握する)に使う。
- どちらの役割でも、模範解答・採点基準は返さない(このツールは設問文までしか扱わない)。
}

/// 既存の設問一覧を返す。category を指定すると分野で絞る。
/// 返り値は questionId / category / prompt / difficulty のみで、模範解答・採点基準は含めない。
/// 生徒=出題、設問管理者=作問前のカタログ確認、として共有で使う。
Method ListPracticeQuestions(category As %String = "") As %DynamicObject
{
    Set questions = []
    If category = "" {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Category, Prompt, Difficulty FROM Demo_Teacher.Question ORDER BY ID")
    } Else {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Category, Prompt, Difficulty FROM Demo_Teacher.Question WHERE Category = ? ORDER BY ID", category)
    }
    While rs.%Next() {
        Set item = {}
        Set item.questionId = rs.%Get("ID")
        Set item.category = rs.%Get("Category")
        Set item.prompt = rs.%Get("Prompt")
        Set item.difficulty = rs.%Get("Difficulty")
        Do questions.%Push(item)
    }
    Return {"count": (questions.%Size()), "questions": (questions)}
}

}
