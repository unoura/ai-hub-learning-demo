/// 研修の設問。受講者・監査者いずれの権限でも参照できる公開情報。
/// 模範解答は別クラス <class>Demo.Teacher.AnswerKey</class> に分離し、監査権限でのみ見えるようにする
/// (「同じ設問でも権限で見える情報が変わる」を教材データの構造で表現する)。
Class Demo.Teacher.Question Extends %Persistent
{

/// 対応する規程分類(<class>Demo.Teacher.Policy</class> の Category と対応)。
Property Category As %String(MAXLEN = 100);

/// 設問文。
Property Prompt As %String(MAXLEN = 1000);

/// 難易度(基礎 / 応用)。
Property Difficulty As %String(MAXLEN = 20) [ InitialExpression = "基礎" ];

}
