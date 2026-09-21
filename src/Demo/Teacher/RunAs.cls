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

/// 指定ユーザの identity で先生エージェントの会話(RunLesson)を丸ごと実行する。
/// 同じゴールを learner01(生徒)/ auditor01(先生=監査者)で投げると、呼べるツールが
/// 権限で変わる様子が trajectory に出る(生徒は GetAnswerKey が見えない、等)。
///
///   >>> do ##class(Demo.Teacher.RunAs).RunLessonAs("auditor01", "この設問の模範解答を教えて")
///   >>> do ##class(Demo.Teacher.RunAs).RunLessonAs("learner01", "情報持ち出しの社内規程を出典付きで教えて")
ClassMethod RunLessonAs(username As %String, goal As %String = "『情報持ち出し』の社内規程を調べて、出典付きで要点を教えて", pwd As %String = "SecDemo!2026") As %Status
{
    Set outfile = "/tmp/runas_lesson_" _ username _ ".txt"
    Do ##class(%File).Delete(outfile)
    Write "=== ", username, " として先生エージェントを実行 ===", !
    Job ##class(Demo.Teacher.RunAs).LessonChild(username, pwd, goal, outfile)
    // LLM 応答を待つので長め(最大 ~90 秒)。子は完了時に .part → 本ファイルへリネームする。
    For i = 1:1:900 {
        Quit:##class(%File).Exists(outfile)
        Hang 0.1
    }
    If '##class(%File).Exists(outfile) {
        Write "(タイムアウト。子プロセスが応答しません)", !
        Return $$$OK
    }
    Do ..Emit(..ReadFile(outfile))
    Return $$$OK
}

/// 子プロセス:先生エージェントの会話を実行し、その出力を一時ファイルへ捕捉する。
///
/// LLM シークレットの解決には %DB_IRISSECURITY(ロールに付与不可)相当の特権が要るため、
/// 「特権のうちに %Init でシークレットをメモリへ解決 → デモユーザに Login → 会話を実行」
/// の順で行う。以降のツール認可(RoleGuard)と教材 SQL は、切替後のデモユーザのロールで評価される。
/// 完了時のみ本ファイルへリネームし、親が「途中の空ファイル」を読むのを防ぐ。
ClassMethod LessonChild(username As %String, pwd As %String, goal As %String, outfile As %String)
{
    Set tmp = outfile _ ".part"
    Do ##class(%File).Delete(tmp)
    // 1) 特権のうちに初期化(LLM シークレットをメモリ上の Provider へ解決)。
    Set agent = ##class(Demo.Teacher.Teacher).%New()
    Set sc = agent.%Init()
    If $$$ISERR(sc) {
        Do ..WriteFile(outfile, "初期化エラー: " _ $System.Status.GetErrorText(sc))
        Quit
    }
    // 2) デモユーザへ切替(不可逆)。以降のツール可視性/実行・教材 SQL はこのロールで判定。
    If '$SYSTEM.Security.Login(username, pwd) {
        Do ..WriteFile(outfile, "ログイン失敗: " _ username)
        Quit
    }
    Set io = $IO
    Try {
        // UTF-8 で書く(K\UTF8\)。既定変換だと日本語が ? に落ちる。
        Open tmp:("WNSK\UTF8\"):5
        Use tmp
        Write "[identity] user=", $Username, "  roles=", $Roles, !!
        Do ##class(Demo.Teacher.Teacher).RunLessonWith(agent, goal)
    } Catch ex {
        Write !, "子プロセス例外: ", ex.DisplayString(), !
    }
    Use io
    Close tmp
    Do ##class(%File).Rename(tmp, outfile)
}

/// 捕捉した出力を親の端末へ書き出す。改行を CRLF に正規化(TTY で段組みがずれないように)。
ClassMethod Emit(text As %String) [ Private ]
{
    Set text = $Replace(text, $Char(13, 10), $Char(10))
    Set text = $Replace(text, $Char(10), $Char(13, 10))
    Write text, !
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

/// ファイル全体を文字列で読む(UTF-8。子プロセスの日本語出力を保持するため)。
ClassMethod ReadFile(path As %String) As %String [ Private ]
{
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.TranslateTable = "UTF8"
    Set f.Filename = path
    Set s = ""
    While 'f.AtEnd { Set s = s _ f.Read(32000) }
    Return s
}

/// 文字列をファイルへ書く(UTF-8。ReadFile と対で日本語を保持)。
ClassMethod WriteFile(path As %String, content As %String) [ Private ]
{
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.TranslateTable = "UTF8"
    Set f.Filename = path
    Do f.Write(content)
    Do f.%Save()
}

}
