/// 先生エージェントのツールセット。生徒向け(学習・採点・成績)と設問管理者向け(作問)を
/// 1 つのセットにまとめ、クラス単位で `resource` 要件を付与する。
/// 権限判定は <class>Demo.Teacher.RoleGuard</class>(Authorization ポリシー)に集約し、
/// 掲載段階(%CanList)で権限差を、実行段階(%CanExecute)で二重ガードを効かせる。
/// さらに <class>Demo.Teacher.Audit.PersistentAudit</class>(Audit ポリシー)で、実行された
/// ツールを「誰が・いつ・成否」まで DB に永続監査する(RBAC × 永続監査の層)。
///
///   - Demo.Teacher.Tools.Catalog(ListPracticeQuestions)… 要件なし=誰でも(設問一覧の閲覧)。
///   - Demo.Teacher.Tools.Study(GradeMyAnswer / ShowReportCard)… 生徒(Demo_Study)専用。
///   - Demo.Teacher.Tools.Authoring(RegisterQuestion)… 設問管理者(Demo_Authoring)専用。
///
/// SearchPolicy(ベクトル検索の KnowledgeBase)も要件なしでエージェントへ別途登録する
/// (生徒・設問管理者どちらからも見える)。
///
/// DependsOn: ToolSet のジェネレータは Include するツールクラスのコンパイル済み情報を読むため、
/// 初回(クラス未登録)の一括ロードでも先にツール・ポリシーをコンパイルさせる。
Class Demo.Teacher.ToolSet Extends %AI.ToolSet [ DependsOn = (Demo.Teacher.Tools.Catalog, Demo.Teacher.Tools.Study, Demo.Teacher.Tools.Authoring, Demo.Teacher.RoleGuard, Demo.Teacher.Audit.PersistentAudit) ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="Teacher">
  <Description>情報セキュリティ・コンプライアンス研修の先生エージェント用ツールセット。採点・成績は生徒、作問は設問管理者。</Description>
  <Policies>
    <Authorization Class="Demo.Teacher.RoleGuard"/>
    <Audit Class="Demo.Teacher.Audit.PersistentAudit"/>
  </Policies>
  <Include Class="Demo.Teacher.Tools.Catalog"/>
  <Include Class="Demo.Teacher.Tools.Study">
    <Requirement Name="resource" Value="Demo_Study"/>
  </Include>
  <Include Class="Demo.Teacher.Tools.Authoring">
    <Requirement Name="resource" Value="Demo_Authoring"/>
  </Include>
</ToolSet>
}

}
