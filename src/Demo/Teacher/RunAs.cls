Include %occStatus

/// RunAs デモ:別ユーザの権限で「見えるツール」がどう変わるかを実演する。
///
/// <method>$SYSTEM.Security.Login</method> はプロセスの識別情報を不可逆に切り替えるため、
/// 現行セッションでは実行できない。そこでロールごとに子プロセスを JOB し、
/// 子側でデモユーザにログイン → <class>Demo.Teacher.ToolSet</class> をディスカバリ →
/// 見えたツール名をファイルに書き出し、親が回収して表示する。
///
/// 前提:<method>Demo.Teacher.Security.SetupRBAC</method> でユーザ/ロールを作成済みであること。
///
/// 実演:
///   >>> do ##class(Demo.Teacher.RunAs).Compare()
///   learner01 は GetHint のみ、auditor01 は 4 ツール全て見える、という差が出る。
Class Demo.Teacher.RunAs
{

/// 受講者(learner01)と監査者(auditor01)の見えるツールを並べて表示する。
ClassMethod Compare(pwd As %String = "SecDemo!2026") As %Status
{
    Write "=== RunAs: ロール別のツールディスカバリ ===", !
    Do ..ShowToolsFor("learner01", pwd)
    Do ..ShowToolsFor("auditor01", pwd)
    Write "----", !
    Write "受講者には監査・採点ツールがそもそも見えない(%CanList で除外)。", !
    Return $$$OK
}

/// 指定ユーザの権限でツールをディスカバリし、結果を表示する。
ClassMethod ShowToolsFor(username As %String, pwd As %String = "SecDemo!2026") As %Status
{
    Set outfile = "/tmp/runas_" _ username _ ".json"
    Do ##class(%File).Delete(outfile)
    Job ##class(Demo.Teacher.RunAs).Child(username, pwd, outfile)
    // 子プロセスの完了(出力ファイル)を待つ。
    For i = 1:1:100 {
        Quit:##class(%File).Exists(outfile)
        Hang 0.1
    }
    If '##class(%File).Exists(outfile) {
        Write username, ": (タイムアウト。子プロセスが応答しません)", !
        Return $$$OK
    }
    Set json = ..ReadFile(outfile)
    Set res = {}.%FromJSON(json)
    If res.%IsDefined("error") {
        Write username, ": エラー — ", res.error, !
        Return $$$OK
    }
    Write username, "(", res.roles, ")が見えるツール: "
    Set names = ""
    Set it = res.tools.%GetIterator()
    While it.%GetNext(.k, .v) { Set names = names _ $Select(names="":"", 1:", ") _ v }
    Write $Select(names="":"(なし)", 1:names), !
    Return $$$OK
}

/// 「取れる行動」の権限差を実演する。各ユーザの identity で GetAnswerKey / RecordScore を
/// 実際に実行し、監査者だけが成功する(受講者は %CanExecute で拒否される)ことを示す。
///
///   >>> do ##class(Demo.Teacher.RunAs).CompareActions()
ClassMethod CompareActions(pwd As %String = "SecDemo!2026") As %Status
{
    Write "=== RunAs: ロール別の「取れる行動」 ===", !
    Do ..ShowActionsFor("learner01", pwd)
    Do ..ShowActionsFor("auditor01", pwd)
    Write "----", !
    Write "同じツール呼び出しでも、監査者だけが模範解答の参照・採点を実行できる(実行ゲート %CanExecute)。", !
    Return $$$OK
}

/// 指定ユーザの権限で監査系ツールを実行し、成否を表示する。
ClassMethod ShowActionsFor(username As %String, pwd As %String = "SecDemo!2026") As %Status
{
    Set outfile = "/tmp/runas_act_" _ username _ ".json"
    Do ##class(%File).Delete(outfile)
    Job ##class(Demo.Teacher.RunAs).ActionChild(username, pwd, outfile)
    For i = 1:1:100 {
        Quit:##class(%File).Exists(outfile)
        Hang 0.1
    }
    If '##class(%File).Exists(outfile) {
        Write username, ": (タイムアウト。子プロセスが応答しません)", !
        Return $$$OK
    }
    Set res = {}.%FromJSON(..ReadFile(outfile))
    If res.%IsDefined("error") {
        Write username, ": エラー — ", res.error, !
        Return $$$OK
    }
    Write username, "(", res.roles, ")が取れる行動:", !
    Write "  GetAnswerKey(模範解答) → ", res.answerKey, !
    Write "  RecordScore(採点)      → ", res.recordScore, !
    Return $$$OK
}

/// 子プロセス:デモユーザにログインして監査系ツールを実行し、結果を JSON でファイルに書く。
ClassMethod ActionChild(username As %String, pwd As %String, outfile As %String)
{
    Try {
        If '$SYSTEM.Security.Login(username, pwd) {
            Do ..WriteFile(outfile, {"error": "ログイン失敗"}.%ToJSON())
            Quit
        }
        Set out = {}
        Set out.user = $Username
        Set out.roles = $Roles
        Set mgr = ##class(%AI.ToolMgr).%New()
        Do mgr.RegisterToolSet("Demo.Teacher.ToolSet")
        Set out.answerKey = ..TryTool(mgr, "GetAnswerKey", {"questionId": 1})
        Set out.recordScore = ..TryTool(mgr, "RecordScore", {"learner": (username), "questionId": 1, "score": 80, "comment": "RunAs デモ"})
        Do ..WriteFile(outfile, out.%ToJSON())
    } Catch ex {
        Do ..WriteFile(outfile, {"error": ($ZConvert(ex.DisplayString(), "O", "JSON"))}.%ToJSON())
    }
}

/// ツールを実行し、拒否/成功を人間可読な1行に整形する。
/// 実行ゲート(%CanExecute)の拒否は例外・エラー結果いずれで表面化しても捕捉する。
ClassMethod TryTool(mgr As %AI.ToolMgr, name As %String, args As %DynamicObject) As %String [ Private ]
{
    Try {
        Set res = mgr.ExecuteTool(name, args)
        If $IsObject(res), res.%IsDefined("error") {
            Return "✗ 拒否/失敗: " _ res.error
        }
        Return "✓ 実行OK: " _ $Extract($Select($IsObject(res): res.%ToJSON(), 1: res), 1, 90)
    } Catch ex {
        Set msg = ex.DisplayString()
        // %CanList でカタログから除外されると、そもそも実行時に「ツールが無い」扱いになる(=一次防御)。
        If msg [ "ToolNotFound" Return "✗ 権限なし: ツールがカタログに存在しません(%CanList で除外)"
        Return "✗ 拒否: " _ msg
    }
}

/// 子プロセス:デモユーザにログインしてツール名をディスカバリし、JSON をファイルに書く。
ClassMethod Child(username As %String, pwd As %String, outfile As %String)
{
    Try {
        If '$SYSTEM.Security.Login(username, pwd) {
            Do ..WriteFile(outfile, {"error": "ログイン失敗"}.%ToJSON())
            Quit
        }
        Set out = {}
        Set out.user = $Username
        Set out.roles = $Roles
        Set out.tools = ..DiscoverToolNames()
        Do ..WriteFile(outfile, out.%ToJSON())
    } Catch ex {
        Do ..WriteFile(outfile, {"error": ($ZConvert(ex.DisplayString(), "O", "JSON"))}.%ToJSON())
    }
}

/// ToolSet をディスカバリして、見えるツール名の配列を返す。
ClassMethod DiscoverToolNames() As %DynamicArray
{
    Set names = []
    Set mgr = ##class(%AI.ToolMgr).%New()
    Do mgr.RegisterToolSet("Demo.Teacher.ToolSet")
    Set arr = mgr.%Discover()
    For i = 0:1:arr.%Size()-1 {
        Set t = arr.%Get(i)
        Do names.%Push(t.name)
    }
    Return names
}

/// ファイル全体を文字列で読む。
ClassMethod ReadFile(path As %String) As %String [ Private ]
{
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.Filename = path
    Set s = ""
    While 'f.AtEnd { Set s = s _ f.Read(32000) }
    Return s
}

/// 文字列をファイルへ書く。
ClassMethod WriteFile(path As %String, content As %String) [ Private ]
{
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.Filename = path
    Do f.Write(content)
    Do f.%Save()
}

}
