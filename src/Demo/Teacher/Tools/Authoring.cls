Include %occStatus

/// 設問管理者用の作問ツール。リソース `Demo_Authoring` で保護する。
/// エージェントが規程(SearchPolicy)を基に設問・模範解答・採点基準・採点キーポイントを
/// 生成し、このツールで <class>Demo.Teacher.Question</class> / <class>Demo.Teacher.AnswerKey</class> に登録する。
///
/// 「LLM が規程を要約して設問を生成し、その成果物を DB に登録する」という
/// 生成 + 情報登録の両面を1ツールで見せる。
Class Demo.Teacher.Tools.Authoring Extends %AI.Tool
{

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# 作問ツール(設問管理者用)

社内規程を基に生成した設問を教材へ登録する。
- まず SearchPolicy で根拠となる規程を調べ、その内容に沿った設問文・模範解答・採点基準・
  採点キーポイントを作ってから RegisterQuestion で登録する。
- 採点キーポイント(keyPoints)は自動採点に使う。"観点名=語1|語2;観点名=語1|語2" の形式で、
  各観点に、解答へ含まれうる語(同義語)を "|" 区切りで並べる。
}

/// 生成した設問を教材に登録する(設問管理者専用)。
/// category: 規程分類(既存の規程分類に合わせると出典が引ける)。prompt: 設問文。
/// difficulty: 難易度(基礎/応用)。modelAnswer: 模範解答。rubric: 採点基準の説明。
/// keyPoints: 自動採点用キーポイント。"観点名=語1|語2;観点名=語1|語2" 形式。
Method RegisterQuestion(category As %String, prompt As %String, difficulty As %String = "基礎", modelAnswer As %String = "", rubric As %String = "", keyPoints As %String = "") As %DynamicObject
{
    If (category = "") || (prompt = "") Return {"error": "category と prompt は必須です。"}
    // オブジェクトアクセス(%Save)で登録する。%DB_DEMO_DATA を持つ実行基盤ロールで動く。
    Set q = ##class(Demo.Teacher.Question).%New()
    Set q.Category = category
    Set q.Prompt = prompt
    Set q.Difficulty = difficulty
    Set sc = q.%Save()
    If $$$ISERR(sc) Return {"error": ($System.Status.GetErrorText(sc))}
    Set a = ##class(Demo.Teacher.AnswerKey).%New()
    Set a.Question = q
    Set a.ModelAnswer = modelAnswer
    Set a.Rubric = rubric
    Set a.KeyPoints = keyPoints
    Set sc = a.%Save()
    If $$$ISERR(sc) Return {"error": ($System.Status.GetErrorText(sc))}
    Set result = {}
    Set result.ok = 1
    Set result.questionId = q.%Id()
    Set result.category = category
    Set result.prompt = prompt
    Set result.difficulty = difficulty
    Return result
}

}
