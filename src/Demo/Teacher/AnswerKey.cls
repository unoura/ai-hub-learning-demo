/// 設問の模範解答と採点基準(ルーブリック)。監査者(トレーナー)権限でのみ参照する教材。
/// 受講者エージェントからは GetAnswerKey ツール自体が見えない/実行できないように後段の
/// ポリシーで封じる。ここではデータとして分離しておくことがその封じ込めの前提になる。
Class Demo.Teacher.AnswerKey Extends %Persistent
{

/// 対応する設問。
Property Question As Demo.Teacher.Question;

/// 模範解答。
Property ModelAnswer As %String(MAXLEN = 2000);

/// 採点基準(ルーブリック)。RecordScore の判断材料。
Property Rubric As %String(MAXLEN = 2000);

}
