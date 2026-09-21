/// 受講者の学習履歴・スコア(個人情報)。ViewProgress で参照し、RecordScore が書き込む。
/// 監査者(トレーナー)権限でのみ扱える実行時状態で、受講者エージェントからは
/// ツールごと封じる(データ分離 × 権限ゲートの二重ガードの対象)。
Class Demo.Teacher.Progress Extends %Persistent
{

/// 受講者の識別子(ユーザ名など)。
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
