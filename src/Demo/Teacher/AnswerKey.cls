/// 設問の模範解答・採点基準(ルーブリック)・採点キーポイント。
/// 生徒には**開示しない**教材。採点(GradeMyAnswer)はサーバ側でこの採点キーポイントと
/// 突き合わせて点数を出すため、生徒に SQL 参照権を与えなくてもよい(=生徒は SQL でも読めない)。
/// 設問管理者は作問(RegisterQuestion)でここを書き込む。
///
/// Question を一意インデックスにしてあるので、<method>QIdxOpen</method>(questionId) で
/// 設問IDから採点基準をオブジェクトアクセスで開ける(SQL 権限に依存しない)。
Class Demo.Teacher.AnswerKey Extends %Persistent
{

/// 対応する設問(1 設問につき 1 採点基準)。
Property Question As Demo.Teacher.Question;

/// 模範解答。
Property ModelAnswer As %String(MAXLEN = 2000);

/// 採点基準(ルーブリック)の説明文。人間向けの根拠。
Property Rubric As %String(MAXLEN = 2000);

/// 自動採点用キーポイント。"観点名=語1|語2;観点名=語1|語2" 形式。
/// 各観点は ";" 区切り、観点内の同義語は "|" 区切り。解答にいずれかの語が含まれれば
/// その観点は到達とみなす(暫定措置。本番は意味照合/LLM 採点に置き換える)。
Property KeyPoints As %String(MAXLEN = 2000);

/// 設問ごとに一意。QIdxOpen(questionId) で採点基準をオブジェクトアクセスで開くために使う。
Index QIdx On Question [ Unique ];

}
