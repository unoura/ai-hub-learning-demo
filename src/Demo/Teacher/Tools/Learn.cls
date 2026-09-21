/// 受講者・監査者いずれの権限でも使える学習支援ツール群。
/// 模範解答は返さない(それは監査専用の GetAnswerKey)。ここでは「どの規程を調べればよいか」
/// までを示すヒントに留める。SearchPolicy(ベクトル検索)と組み合わせて自習を促す。
Class Demo.Teacher.Tools.Learn Extends %AI.Tool
{

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# 学習支援ツール

受講者が社内ポリシーを自分で調べて理解できるよう支援する。
- 設問の答えそのものは与えない。関連する規程・観点を指し示す。
- 規程の中身は SearchPolicy(ベクトル検索)で調べる。
}

/// 設問のヒントを返す。答えは示さず、調べるべき分類と関連規程の見出しだけを返す。
/// questionId: 設問のID(Demo.Teacher.Question の ID)。
Method GetHint(questionId As %Integer) As %DynamicObject
{
    Set q = ##class(Demo.Teacher.Question).%OpenId(questionId)
    If '$IsObject(q) Return {"error": ("設問が見つかりません: " _ questionId)}
    Set titles = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Title, Source FROM Demo_Teacher.Policy WHERE Category = ?", q.Category)
    While rs.%Next() {
        Do titles.%Push(rs.%Get("Title") _ "(" _ rs.%Get("Source") _ ")")
    }
    Set result = {}
    Set result.questionId = questionId
    Set result.category = q.Category
    Set result.prompt = q.Prompt
    Set result.hint = "『" _ q.Category _ "』に関する社内規程を SearchPolicy で調べましょう。"
    Set result.relatedPolicies = titles
    Return result
}

}
