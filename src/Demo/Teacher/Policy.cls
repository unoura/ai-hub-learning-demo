/// 社内ポリシー(情報セキュリティ・コンプライアンス)の規程コーパス。
/// 先生エージェントの SearchPolicy ツールが参照する教材の原本(source of truth)。
/// 本文 (Body) をベクトル化して <class>Demo.Teacher.Setup</class> が検索インデックスへ投入する。
Class Demo.Teacher.Policy Extends %Persistent
{

/// 分類(例: パスワード管理 / アクセス管理 / 情報持ち出し / インシデント / 個人情報保護 / コンプライアンス)。
Property Category As %String(MAXLEN = 100);

/// 規程の見出し。
Property Title As %String(MAXLEN = 200);

/// 規程の本文。ベクトル検索の対象。
Property Body As %String(MAXLEN = 2000);

/// 引用元(例: 「情報セキュリティ規程 第3条」)。回答時の根拠提示に使う。
Property Source As %String(MAXLEN = 200);

Index CategoryIdx On Category;

}
