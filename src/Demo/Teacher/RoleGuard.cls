Include (%AI, %occStatus)

/// ツールの権限ゲート。ToolSet の各ツールに付与された `resource` 要件を、
/// IRIS プラットフォームの RBAC(<method>$SYSTEM.Security.Check</method>)で検証する。
///
/// 見どころは 2 点:
///   1. %CanList  … 実行前の「カタログ」段階で権限のないツールを LLM から隠す
///                   (受講者の目にはトレーナー用ツールが見えない = ツールディスカバリの権限差)。
///   2. %CanExecute … 万一呼ばれても、プラットフォーム権限で実行を拒否する(二重ガード)。
///
/// `resource` 要件を持たないツール(SearchPolicy / GetHint など)は誰でも利用可。
/// リソース定義は <class>Demo.Teacher.Security</class> が作成する。
Class Demo.Teacher.RoleGuard Extends %AI.Policy.Authorization
{

/// カタログ掲載可否。resource 要件があり USE 権限が無ければ 0(=LLM から隠す)。
/// tool: ツール名。metadata: <Requirement> で付与されたメタデータ。
Method %CanList(tool As %String, metadata As %DynamicObject) As %Boolean
{
    Set resource = ..RequiredResource(metadata)
    If resource = "" Return 1
    Return $SYSTEM.Security.Check(resource, "USE")
}

/// 実行可否。権限が無ければアクセス拒否ステータスを返す(二重ガード)。
/// tool: ツール名。call: 呼び出し内容。metadata: 付与メタデータ。
Method %CanExecute(tool As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
    Set resource = ..RequiredResource(metadata)
    If resource = "" Return $$$OK
    If $SYSTEM.Security.Check(resource, "USE") Return $$$OK
    Return $$$ERROR($$$AICoreToolAccessDenied, "権限がありません(必要リソース: " _ resource _ ")")
}

/// メタデータから resource 要件を取り出す(未設定なら空文字)。
Method RequiredResource(metadata As %DynamicObject) As %String [ Private ]
{
    If '$IsObject(metadata) Return ""
    Set resource = metadata.%Get("resource")
    Return $Get(resource)
}

}
