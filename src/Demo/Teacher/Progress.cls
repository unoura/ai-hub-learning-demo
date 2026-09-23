/// 生徒の学習履歴・スコア(個人情報)。GradeMyAnswer(採点)が書き込み、
/// ShowReportCard(成績表)が本人分を参照する。採点は生徒本人の行動として記録され、
/// Learner にはログインユーザ名が入る。成績表は Ts の新しい順に直近10件を見る。
Class Demo.Teacher.Progress Extends %Persistent
{

/// 生徒の識別子(ログインユーザ名)。
Property Learner As %String(MAXLEN = 100);

/// 対象の設問。
Property Question As Demo.Teacher.Question;

/// スコア(0〜100)。
Property Score As %Integer(MAXVAL = 100, MINVAL = 0);

/// 記録日時。
Property Ts As %TimeStamp [ InitialExpression = {$ZDateTime($Horolog, 3)} ];

/// 採点コメント(任意)。
Property Comment As %String(MAXLEN = 1000);

Index LearnerIdx On Learner;

}
