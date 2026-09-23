Include %occStatus

/// 生徒用の学習ツール群。リソース `Demo_Study` で保護する。
/// 権限判定は ToolSet に取り付ける <class>Demo.Teacher.RoleGuard</class> に集約し、
/// ここは業務ロジックのみを持つ。
///
///   - GradeMyAnswer: 生徒の解答を採点し、点数と講評を学習履歴(Progress)に登録する。
///       採点基準(AnswerKey)は**ツール内部でのみ**参照し、生徒には点数と観点フィードバックだけ返す。
///   - ShowReportCard: 本人の直近10件の採点履歴と集計を返す(成績表の材料)。
///
/// 既存設問の一覧(ListPracticeQuestions)は共有ツール <class>Demo.Teacher.Tools.Catalog</class> に
/// 分離した(生徒の出題にも設問管理者の作問前確認にも使うため、要件なし=誰でも)。
Class Demo.Teacher.Tools.Study Extends %AI.Tool
{

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# 学習ツール(生徒用)

生徒の学習を支援する。
- 「問題を出して」「練習したい」と言われたら ListPracticeQuestions(共有ツール)で既存の練習問題を
  取得して提示する。生徒は新しい問題を**作れない**(作問は設問管理者の権限)。既存の練習問題から出題すること。
- 生徒が解答を書いてきたら GradeMyAnswer で採点する(点数と講評が学習履歴に登録される)。
- 模範解答・採点基準の全文は生徒に見せない。点数と「到達/未達の観点」「出典」だけ伝える。
- 成績を求められたら ShowReportCard で本人の履歴を取得し、成績表にまとめる。
}

/// 生徒の解答を採点し、点数と講評を Progress に登録する(生徒本人の学習記録)。
/// questionId: 設問のID。answer: 生徒が書いた解答テキスト。
/// 返り値は点数・到達/未達の観点・出典を含むが、模範解答/採点基準テキストは含めない。
Method GradeMyAnswer(questionId As %Integer, answer As %String) As %DynamicObject
{
    Set q = ##class(Demo.Teacher.Question).%OpenId(questionId)
    If '$IsObject(q) Return {"error": ("設問が見つかりません: " _ questionId)}
    // 採点基準はツール内部でのみ参照する。オブジェクトアクセス(QIdxOpen)で開くので、
    // 生徒ロールに AnswerKey の SQL 参照権を与えなくても採点できる(=SQL 経由では読めない)。
    Set a = ##class(Demo.Teacher.AnswerKey).QIdxOpen(questionId)
    If '$IsObject(a) Return {"error": ("採点基準が未登録です: " _ questionId)}

    // KeyPoints("観点名=語1|語2;観点名=語1|語2")を観点ごとに照合して採点する。
    Set matched = [], missed = []
    Set groups = $ListFromString(a.KeyPoints, ";")
    Set total = $ListLength(groups), hit = 0
    For gi = 1:1:total {
        Set g = $List(groups, gi)
        Set label = $Piece(g, "=", 1)
        Set syns = $ListFromString($Piece(g, "=", 2), "|")
        Set found = 0
        For si = 1:1:$ListLength(syns) {
            If answer [ $List(syns, si) { Set found = 1  Quit }
        }
        If found { Set hit = hit + 1  Do matched.%Push(label) }
        Else { Do missed.%Push(label) }
    }
    Set score = $Select(total > 0: $Number(hit / total * 100, 0), 1: 0)

    // 出典(規程の条番号)を分類から引く。規程は公開情報。
    Set citation = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Source FROM Demo_Teacher.Policy WHERE Category = ?", q.Category)
    If rs.%Next() { Set citation = rs.%Get("Source") }

    // 講評(構造化テキスト)を組み立てて履歴に残す。
    Set comment = score _ "点(" _ hit _ "/" _ total _ " 観点)。"
    If matched.%Size() > 0 { Set comment = comment _ "到達: " _ ..Join(matched) _ "。" }
    If missed.%Size() > 0 { Set comment = comment _ "未達: " _ ..Join(missed) _ "。" }
    If citation '= "" { Set comment = comment _ "出典: " _ citation _ "。" }

    // 学習履歴へ登録(本人=ログインユーザ)。オブジェクトアクセスで保存。
    Set p = ##class(Demo.Teacher.Progress).%New()
    Set p.Learner = $Username
    Set p.Question = q
    Set p.Score = score
    Set p.Comment = comment
    Set sc = p.%Save()
    If $$$ISERR(sc) Return {"error": ($System.Status.GetErrorText(sc))}

    Set result = {}
    Set result.ok = 1
    Set result.learner = $Username
    Set result.questionId = questionId
    Set result.score = score
    Set result.matched = matched
    Set result.missed = missed
    Set result.citation = citation
    Set result.comment = comment
    Return result
}

/// 本人の直近10件の採点履歴と集計を返す(成績表の材料)。
/// 他人の履歴は返さない(ログインユーザ本人に限定)。
Method ShowReportCard() As %DynamicObject
{
    Set learner = $Username
    Set records = [], sum = 0, n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 10 p.Score, p.Comment, p.Ts, q.Prompt, q.Category FROM Demo_Teacher.Progress p JOIN Demo_Teacher.Question q ON p.Question = q.ID WHERE p.Learner = ? ORDER BY p.Ts DESC, p.ID DESC", learner)
    While rs.%Next() {
        Set rec = {}
        Set rec.category = rs.%Get("Category")
        Set rec.prompt = rs.%Get("Prompt")
        Set rec.score = rs.%Get("Score")
        Set rec.comment = rs.%Get("Comment")
        Set rec.ts = rs.%Get("Ts")
        Do records.%Push(rec)
        Set sum = sum + rs.%Get("Score"), n = n + 1
    }
    Set result = {}
    Set result.learner = learner
    Set result.count = n
    Set result.average = $Select(n > 0: $Number(sum / n, 0), 1: 0)
    Set result.records = records
    Return result
}

/// %DynamicArray を「, 」で連結(講評表示用)。
ClassMethod Join(arr As %DynamicArray) As %String [ Private ]
{
    Set s = "", it = arr.%GetIterator()
    While it.%GetNext(.k, .v) { Set s = s _ $Select(s = "": "", 1: ", ") _ v }
    Return s
}

}
