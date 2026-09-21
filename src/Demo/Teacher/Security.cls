Include %occStatus

/// 先生エージェント用の RBAC(リソース/ロール/デモユーザ)を作成する。冪等。
///
/// プラットフォーム(IRIS)の権限で、監査・採点ツールを受講者から封じるのが狙い。
/// アプリ側の <class>Demo.Teacher.RoleGuard</class> は、ここで作るリソースへの
/// USE 権限を <method>$SYSTEM.Security.Check</method> で確認する。
///
///   リソース: Demo_LearnRead(学習支援) / Demo_AnswerKey(模範解答) / Demo_Grade(採点・進捗)
///   ロール  : Demo_Learner(学習のみ)   / Demo_Auditor(学習+模範解答+採点)
///            + Demo_Runtime(DEMO 名前空間で動くための DB 権限。アプリ権限と実行基盤を層で分離)
///   ユーザ  : learner01(受講者)       / auditor01(トレーナー)
///
/// セットアップ(%SYS への切替はメソッド内で行う。どの名前空間から呼んでもよい):
///   >>> do ##class(Demo.Teacher.Security).SetupRBAC()
///
/// パスワードはローカルデモ専用。本番の資格情報ではないため、必要に応じて引数で上書きする。
Class Demo.Teacher.Security
{

/// アプリケーションリソースの型(Security.Resources.Type)。
Parameter RESOURCETYPE = 8;

/// 実行基盤ロールが持つ DB リソース。DEMO 名前空間でコードを動かすための最小限。
Parameter RUNTIMEDBS = "%DB_DEMO_CODE:RW,%DB_DEMO_DATA:RW,%DB_DEMO_DATASECONDARY:RW,%DB_IRISLIB:R,%DB_IRISSYS:RW,%DB_IRISTEMP:RW,%DB_IRISLOCALDATA:RW,%DB_%DEFAULT:RW";

/// リソース/ロール/ユーザをまとめて作成(既存はスキップ)。
/// pwd: デモユーザのパスワード(ローカル専用)。
ClassMethod SetupRBAC(pwd As %String = "SecDemo!2026") As %Status
{
    New $Namespace
    Set $Namespace = "%SYS"

    // 1) リソース
    Set sc = ..EnsureResource("Demo_LearnRead", "学習支援ツールの利用")
    If $$$ISERR(sc) Return sc
    Set sc = ..EnsureResource("Demo_AnswerKey", "模範解答の参照(監査者専用)")
    If $$$ISERR(sc) Return sc
    Set sc = ..EnsureResource("Demo_Grade", "受講者スコアの閲覧・記録(監査者専用)")
    If $$$ISERR(sc) Return sc

    // 2) 実行基盤ロール(DEMO 名前空間で ObjectScript を動かすための DB 権限)。
    //    アプリの権限差(Learn/AnswerKey/Grade)とは独立した「土台」。
    Set sc = ..EnsureRole("Demo_Runtime", "DEMO 名前空間の実行基盤(DB 権限)", ..#RUNTIMEDBS)
    If $$$ISERR(sc) Return sc

    // 3) アプリロール
    Set sc = ..EnsureRole("Demo_Learner", "受講者(学習支援のみ)", "Demo_LearnRead:U")
    If $$$ISERR(sc) Return sc
    Set sc = ..EnsureRole("Demo_Auditor", "トレーナー(学習+模範解答+採点)", "Demo_LearnRead:U,Demo_AnswerKey:U,Demo_Grade:U")
    If $$$ISERR(sc) Return sc

    // 4) デモユーザ(ユーザ名はロール名と重複できないため接尾辞を付ける)。
    //    アプリロール + 実行基盤ロールの2本立てで付与。
    Set sc = ..EnsureUser("learner01", "Demo_Learner,Demo_Runtime", pwd, "研修受講者(デモ)")
    If $$$ISERR(sc) Return sc
    Set sc = ..EnsureUser("auditor01", "Demo_Auditor,Demo_Runtime", pwd, "研修トレーナー(デモ)")
    If $$$ISERR(sc) Return sc

    // 5) SQL 権限(DEMO 名前空間のテーブル)。RoleGuard の可視性/実行ゲートと層を揃える。
    Do ..GrantSql()

    Write "[security] リソース3 / ロール3(基盤1+アプリ2) / ユーザ2 を用意しました。", !
    Return $$$OK
}

/// 各アプリロールに、担当ツールが使う SQL 権限を付与する。
///
/// %DB_* の DB 権限(オブジェクトアクセス。<method>%OpenId</method>/<method>%Save</method> はこれで動く)とは別に、
/// ツールが使う SQL(<method>%SQL.Statement.%ExecDirect</method>)には**テーブル単位の GRANT** が要る。
/// 権限の層は <class>Demo.Teacher.RoleGuard</class>(ツールの可視性/実行)と揃え、SQL レベルでも
/// 受講者が模範解答・進捗を読めないようにする(多層防御)。
///
/// 注: 規程検索(SearchPolicy)が読むベクトル索引 <class>Demo_Teacher.PolicyVec</class> は
/// 「誰でも検索可」の土台なので、共有ロール Demo_Runtime に SELECT を付ける。
/// 模範解答・採点の権限差は、あくまで AnswerKey/Progress 側の GRANT で表す。
ClassMethod GrantSql() As %Status
{
    New $Namespace
    Set $Namespace = "DEMO"
    // 実行基盤(誰でも): 規程検索のためのベクトル索引の参照。
    Do ..Grant("SELECT ON Demo_Teacher.PolicyVec TO Demo_Runtime")
    Do ..Grant("SELECT ON Demo_Teacher.PolicyVec_Config TO Demo_Runtime")
    // 受講者: 教材(規程・設問)の参照のみ。
    Do ..Grant("SELECT ON Demo_Teacher.Policy TO Demo_Learner")
    Do ..Grant("SELECT ON Demo_Teacher.Question TO Demo_Learner")
    // 監査者: 教材 + 模範解答 + 進捗(参照・記録)。
    Do ..Grant("SELECT ON Demo_Teacher.Policy TO Demo_Auditor")
    Do ..Grant("SELECT ON Demo_Teacher.Question TO Demo_Auditor")
    Do ..Grant("SELECT ON Demo_Teacher.AnswerKey TO Demo_Auditor")
    Do ..Grant("SELECT ON Demo_Teacher.Progress TO Demo_Auditor")
    Do ..Grant("INSERT ON Demo_Teacher.Progress TO Demo_Auditor")
    Return $$$OK
}

/// GRANT を1つ実行(冪等)。SQLCODE 100(既に付与済み)は正常扱い、負値のみ警告表示。
ClassMethod Grant(clause As %String) As %Status [ Private ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "GRANT " _ clause)
    If rs.%SQLCODE < 0 {
        Write "  GRANT ", clause, " → SQLCODE ", rs.%SQLCODE, " ", rs.%Message, !
    }
    Return $$$OK
}

/// リソースが無ければ作成。
ClassMethod EnsureResource(name As %String, desc As %String) As %Status
{
    If ##class(Security.Resources).Exists(name) {
        Write "  resource ", name, " (既存)", !
        Return $$$OK
    }
    Set sc = ##class(Security.Resources).Create(name, desc, "", ..#RESOURCETYPE)
    If $$$ISOK(sc) Write "  resource ", name, " 作成", !
    Return sc
}

/// ロールが無ければ作成(resources は "Res:Perm,Res:Perm" 形式)。
ClassMethod EnsureRole(name As %String, desc As %String, resources As %String) As %Status
{
    If ##class(Security.Roles).Exists(name) {
        Write "  role ", name, " (既存)", !
        Return $$$OK
    }
    Set sc = ##class(Security.Roles).Create(name, desc, resources)
    If $$$ISOK(sc) Write "  role ", name, " 作成", !
    Return sc
}

/// ユーザが無ければ作成(DEMO 名前空間を既定に、ロールを付与)。
ClassMethod EnsureUser(name As %String, role As %String, pwd As %String, full As %String) As %Status
{
    If ##class(Security.Users).Exists(name) {
        Write "  user ", name, " (既存)", !
        Return $$$OK
    }
    Set sc = ##class(Security.Users).Create(name, role, pwd, full, "DEMO")
    If $$$ISOK(sc) Write "  user ", name, " 作成(role=", role, ")", !
    Return sc
}

/// リソース/ロール/ユーザを削除(デモの後始末用)。冪等。
ClassMethod Teardown() As %Status
{
    New $Namespace
    Set $Namespace = "%SYS"
    Do ##class(Security.Users).Delete("learner01")
    Do ##class(Security.Users).Delete("auditor01")
    Do ##class(Security.Roles).Delete("Demo_Learner")
    Do ##class(Security.Roles).Delete("Demo_Auditor")
    Do ##class(Security.Roles).Delete("Demo_Runtime")
    Do ##class(Security.Resources).Delete("Demo_LearnRead")
    Do ##class(Security.Resources).Delete("Demo_AnswerKey")
    Do ##class(Security.Resources).Delete("Demo_Grade")
    Write "[security] デモ用の RBAC を削除しました。", !
    Return $$$OK
}

}
