/// 先生エージェントのツールセット。学習支援(誰でも可)と監査・採点(監査者専用)を
/// 1 つのセットにまとめ、各ツールに `resource` 要件を付与する。
/// 権限判定は <class>Demo.Teacher.RoleGuard</class>(Authorization ポリシー)に集約し、
/// 掲載段階(%CanList)で権限差を、実行段階(%CanExecute)で二重ガードを効かせる。
///
/// SearchPolicy(ベクトル検索の KnowledgeBase)は要件なしでエージェントへ別途登録する
/// (受講者・監査者どちらからも見える)。
Class Demo.Teacher.ToolSet Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Teacher">
  <Description>情報セキュリティ・コンプライアンス研修の先生エージェント用ツールセット。学習支援は全員、模範解答・採点は監査者のみ。</Description>
  <Policies>
    <Authorization Class="Demo.Teacher.RoleGuard"/>
  </Policies>
  <Include Class="Demo.Teacher.Tools.Learn">
    <Requirement Name="resource" Value="Demo_LearnRead"/>
  </Include>
  <Include Class="Demo.Teacher.Tools.AnswerKey">
    <Requirement Name="resource" Value="Demo_AnswerKey"/>
  </Include>
  <Include Class="Demo.Teacher.Tools.Grade">
    <Requirement Name="resource" Value="Demo_Grade"/>
  </Include>
</ToolSet>
}

}
