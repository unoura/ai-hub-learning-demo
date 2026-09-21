/// 採点・進捗ツール(監査者専用)。リソース `Demo_Grade` で保護する。
/// 受講者の学習履歴(個人情報)の閲覧と、採点結果の記録を行う。
/// 権限判定は ToolSet に取り付ける <class>Demo.Teacher.RoleGuard</class> に集約し、
/// ここは業務ロジックのみを持つ。
Class Demo.Teacher.Tools.Grade Extends %AI.Tool
{

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# 採点・進捗ツール(監査者専用)

トレーナーが受講者の理解度を確認・記録するためのツール。
- ViewProgress: 受講者の学習履歴・スコアを参照する(個人情報)。
- RecordScore: 採点結果を記録する。
}

/// 受講者の学習履歴・スコアを返す。監査者専用(個人情報)。
/// learner: 受講者の識別子。
Method ViewProgress(learner As %String) As %DynamicObject
{
    Set records = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT p.Question, q.Prompt, p.Score, p.Ts, p.Comment FROM Demo_Teacher.Progress p JOIN Demo_Teacher.Question q ON p.Question = q.ID WHERE p.Learner = ? ORDER BY p.Ts", learner)
    While rs.%Next() {
        Set rec = {}
        Set rec.questionId = rs.%Get("Question")
        Set rec.prompt = rs.%Get("Prompt")
        Set rec.score = rs.%Get("Score")
        Set rec.ts = rs.%Get("Ts")
        Set rec.comment = rs.%Get("Comment")
        Do records.%Push(rec)
    }
    Set result = {}
    Set result.learner = learner
    Set result.records = records
    Return result
}

/// 採点結果を記録する。監査者専用。
/// learner: 受講者の識別子。questionId: 設問のID。score: 0〜100 のスコア。comment: 任意コメント。
Method RecordScore(learner As %String, questionId As %Integer, score As %Integer, comment As %String = "") As %DynamicObject
{
    Set q = ##class(Demo.Teacher.Question).%OpenId(questionId)
    If '$IsObject(q) Return {"error": ("設問が見つかりません: " _ questionId)}
    Set p = ##class(Demo.Teacher.Progress).%New()
    Set p.Learner = learner
    Set p.Question = q
    Set p.Score = score
    Set p.Comment = comment
    Set sc = p.%Save()
    If $$$ISERR(sc) Return {"error": ($system.Status.GetErrorText(sc))}
    Set result = {}
    Set result.ok = 1
    Set result.progressId = p.%Id()
    Set result.learner = learner
    Set result.questionId = questionId
    Set result.score = score
    Return result
}

}
