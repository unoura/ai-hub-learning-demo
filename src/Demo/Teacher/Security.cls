Include %occStatus

/// 先生エージェント用の RBAC(リソース/ロール/デモユーザ)を作成する。冪等。
///
/// プラットフォーム(IRIS)の権限で、生徒には作問を、設問管理者には採点・成績を封じるのが狙い。
/// アプリ側の <class>Demo.Teacher.RoleGuard</class> は、ここで作るリソースへの
/// USE 権限を <method>$SYSTEM.Security.Check</method> で確認する。
///
///   リソース: Demo_Study(採点・成績表) / Demo_Authoring(作問)
///   ロール  : Demo_Student(生徒) / Demo_QuestionAdmin(設問管理者)
///            + Demo_Runtime(DEMO 名前空間で動くための DB 権限。アプリ権限と実行基盤を層で分離)
///   ユーザ  : student01(生徒)   / qadmin01(設問管理者)
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

/// リソース/ロール/ユーザをまとめて作成(既存はスキップ。ユーザのパスワードは既定値に揃える)。
/// pwd: デモユーザの共通パスワード(ローカルデモ専用。既定 "demo")。
ClassMethod SetupRBAC(pwd As %String = "demo") As %Status
{
    New $Namespace
    Set $Namespace = "%SYS"

    // 1) リソース
    Set sc = ..EnsureResource("Demo_Study", "採点・成績表の利用(生徒専用)")
    If $$$ISERR(sc) Return sc
    Set sc = ..EnsureResource("Demo_Authoring", "設問の作成(設問管理者専用)")
    If $$$ISERR(sc) Return sc

    // 2) 実行基盤ロール(DEMO 名前空間で ObjectScript を動かすための DB 権限)。
    //    アプリの権限差(Study/Authoring)とは独立した「土台」。
    Set sc = ..EnsureRole("Demo_Runtime", "DEMO 名前空間の実行基盤(DB 権限)", ..#RUNTIMEDBS)
    If $$$ISERR(sc) Return sc

    // 3) アプリロール(生徒 / 設問管理者。担当ツールがほぼ排他になるよう分ける)
    Set sc = ..EnsureRole("Demo_Student", "生徒(採点・成績表)", "Demo_Study:U")
    If $$$ISERR(sc) Return sc
    Set sc = ..EnsureRole("Demo_QuestionAdmin", "設問管理者(作問)", "Demo_Authoring:U")
    If $$$ISERR(sc) Return sc

    // 4) デモユーザ(ユーザ名はロール名と重複できないため接尾辞を付ける)。
    //    アプリロール + 実行基盤ロールの2本立てで付与。
    Set sc = ..EnsureUser("student01", "Demo_Student,Demo_Runtime", pwd, "研修の生徒(デモ)")
    If $$$ISERR(sc) Return sc
    Set sc = ..EnsureUser("qadmin01", "Demo_QuestionAdmin,Demo_Runtime", pwd, "設問管理者(デモ)")
    If $$$ISERR(sc) Return sc

    // 5) SQL 権限(DEMO 名前空間のテーブル)。RoleGuard の可視性/実行ゲートと層を揃える。
    Do ..GrantSql()

    Write "[security] リソース2 / ロール3(基盤1+アプリ2) / ユーザ2 を用意しました。", !
    Return $$$OK
}

/// 各アプリロールに、担当ツールが使う SQL 権限を付与する。
///
/// %DB_* の DB 権限(オブジェクトアクセス。<method>%OpenId</method>/<method>%Save</method> はこれで動く)とは別に、
/// ツールが使う SQL(<method>%SQL.Statement.%ExecDirect</method>)には**テーブル単位の GRANT** が要る。
/// 権限の層は <class>Demo.Teacher.RoleGuard</class>(ツールの可視性/実行)と揃える。
///
/// 要点(多層防御):採点基準 <class>Demo_Teacher.AnswerKey</class> は**生徒に SELECT を与えない**。
/// GradeMyAnswer はオブジェクトアクセス(QIdxOpen)で採点基準を読むので採点は成立するが、
/// 生徒が SQL で採点基準を直接読むことはできない。作問(Question/AnswerKey への書き込み)は
/// オブジェクトアクセスで行い、ツール層(RoleGuard)で設問管理者に限定する。
///
/// 注: 規程検索(SearchPolicy)が読むベクトル索引 <class>Demo_Teacher.PolicyVec</class> は
/// 「誰でも検索可」の土台なので、共有ロール Demo_Runtime に SELECT を付ける。
ClassMethod GrantSql() As %Status
{
    New $Namespace
    Set $Namespace = "DEMO"
    // 実行基盤(誰でも): 規程検索のためのベクトル索引と、設問一覧(共有カタログ)の参照。
    //   設問文(模範解答は含まない)は生徒の出題にも設問管理者の作問前確認にも使う共有情報
    //   なので、共有ロール Demo_Runtime に SELECT を寄せる(ListPracticeQuestions が読む)。
    Do ..Grant("SELECT ON Demo_Teacher.PolicyVec TO Demo_Runtime")
    Do ..Grant("SELECT ON Demo_Teacher.PolicyVec_Config TO Demo_Runtime")
    Do ..Grant("SELECT ON Demo_Teacher.Question TO Demo_Runtime")
    // 生徒: 規程・自分の学習履歴の参照。採点基準(AnswerKey)は与えない。
    //   ・出典の引用(GradeMyAnswer)と成績表(ShowReportCard)の SQL に使う。
    //   ・履歴の本人限定は各ツール内で WHERE Learner=$Username により行う(暫定措置。
    //     本番は行レベルセキュリティで担保する)。
    Do ..Grant("SELECT ON Demo_Teacher.Policy TO Demo_Student")
    Do ..Grant("SELECT ON Demo_Teacher.Progress TO Demo_Student")
    // 設問管理者: 規程・採点基準の参照(作問の下調べ用)。設問一覧は上の共有 SELECT で足りる。
    Do ..Grant("SELECT ON Demo_Teacher.Policy TO Demo_QuestionAdmin")
    Do ..Grant("SELECT ON Demo_Teacher.AnswerKey TO Demo_QuestionAdmin")
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
/// 既存の場合はパスワードだけデモ既定に揃える(SetupRBAC を「パスワードの唯一の正」にする)。
ClassMethod EnsureUser(name As %String, role As %String, pwd As %String, full As %String) As %Status
{
    If ##class(Security.Users).Exists(name) {
        // デモの共通パスワードに合わせて上書き(再実行で TalkAs のログインが確実に通るように)。
        Set props("Password") = pwd
        Set sc = ##class(Security.Users).Modify(name, .props)
        If $$$ISOK(sc) { Write "  user ", name, " (既存: パスワードを既定に更新)", ! }
        Else { Write "  user ", name, " (既存: パスワード更新失敗 ", $System.Status.GetErrorText(sc), ")", ! }
        Return sc
    }
    Set sc = ##class(Security.Users).Create(name, role, pwd, full, "DEMO")
    If $$$ISOK(sc) Write "  user ", name, " 作成(role=", role, ")", !
    Return sc
}

/// リソース/ロール/ユーザを削除(デモの後始末用)。冪等。
/// 旧設計(受講者/監査者)の名残も併せて削除し、作り直しをきれいにする。
ClassMethod Teardown() As %Status
{
    New $Namespace
    Set $Namespace = "%SYS"
    // 現行(生徒 / 設問管理者)
    Do ##class(Security.Users).Delete("student01")
    Do ##class(Security.Users).Delete("qadmin01")
    Do ##class(Security.Roles).Delete("Demo_Student")
    Do ##class(Security.Roles).Delete("Demo_QuestionAdmin")
    Do ##class(Security.Roles).Delete("Demo_Runtime")
    Do ##class(Security.Resources).Delete("Demo_Study")
    Do ##class(Security.Resources).Delete("Demo_Authoring")
    // 旧設計(受講者 / 監査者)の名残があれば併せて削除。
    Do ##class(Security.Users).Delete("learner01")
    Do ##class(Security.Users).Delete("auditor01")
    Do ##class(Security.Roles).Delete("Demo_Learner")
    Do ##class(Security.Roles).Delete("Demo_Auditor")
    Do ##class(Security.Resources).Delete("Demo_LearnRead")
    Do ##class(Security.Resources).Delete("Demo_AnswerKey")
    Do ##class(Security.Resources).Delete("Demo_Grade")
    Write "[security] デモ用の RBAC を削除しました。", !
    Return $$$OK
}

}
