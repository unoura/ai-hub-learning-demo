Include (%AI, %syPrompt, %occStatus)

/// ツールの権限ゲート + 人手承認ゲート(human-in-the-loop)。
///
/// ToolSet の各ツールに付与された `resource` 要件を IRIS の RBAC(<method>$SYSTEM.Security.Check</method>)で
/// 検証し、さらに**副作用のある書き込み系ツール**には実行の直前に人間の承認を求める。
///
/// 見どころは 3 点:
///   1. %CanList     … 実行前の「カタログ」段階で権限のないツールを LLM から隠す
///                      (生徒の目には作問ツールが見えない = ツールディスカバリの権限差)。
///   2. %CanExecute  … 万一呼ばれても、プラットフォーム権限で実行を拒否する(二重ガード)。
///   3. 人手承認ゲート … 書き込み系(既定 RegisterQuestion)は実行前に人間へ諮る。
///                      承認 / 却下 に加え、**フィードバック(指示)を返して差し戻す**ことができ、
///                      エージェントは指示に沿って作り直して再提案する(= 人間が最終決定する)。
///
/// RBAC(誰が呼べるか)と承認(この一件を実行してよいか)は別軸なので併用する。
/// `resource` 要件を持たないツール(SearchPolicy など)は誰でも利用可・承認も不要。
/// リソース定義は <class>Demo.Teacher.Security</class> が作成する。
///
/// 承認プロンプトは端末を持つプロセスでしか出せない。対話実行 [[Demo.Teacher.RunAs]] の `TalkAs`
/// (在プロセス=端末あり)で人間に諮り、単発の `RunLessonAs`(JOB 子=端末なし)では非対話のため
/// 自動承認する(注記を出す)。テスト/決定的動作にはプロセス内グローバル `^||Demo.Teacher.Approval` を使う。
Class Demo.Teacher.RoleGuard Extends %AI.Policy.Authorization
{

/// 人手承認を要求するツール名(部分一致、カンマ区切りで複数可)。既定は作問(書き込み)のみ。
/// 採点(GradeMyAnswer)は毎回・低リスクなので承認対象にしない。
Parameter APPROVALTOOLS = "RegisterQuestion";

/// カタログ掲載可否。resource 要件があり USE 権限が無ければ 0(=LLM から隠す)。
/// tool: ツール名。metadata: <Requirement> で付与されたメタデータ。
Method %CanList(tool As %String, metadata As %DynamicObject) As %Boolean
{
    Set resource = ..RequiredResource(metadata)
    If resource = "" Return 1
    Return $SYSTEM.Security.Check(resource, "USE")
}

/// 実行可否。(1) RBAC で権限を確認し、(2) 書き込み系なら人間の承認を得る。
/// tool: ツール名。call: 呼び出し内容。metadata: 付与メタデータ。
Method %CanExecute(tool As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
    // (1) RBAC: 必要リソースの USE 権限が無ければ拒否(二重ガード)。
    Set resource = ..RequiredResource(metadata)
    If resource '= "", '$SYSTEM.Security.Check(resource, "USE") {
        Return $$$ERROR($$$AICoreToolAccessDenied, "権限がありません(必要リソース: " _ resource _ ")")
    }

    // (2) 人手承認ゲート(human-in-the-loop): 書き込み系ツールだけ人間に諮る。
    Set name = ..ToolName(tool, call)
    If ..RequiresApproval(name) {
        Set decision = ..Decide(name, call)
        If decision = "APPROVE" Return $$$OK
        If decision = "REJECT" {
            Return $$$ERROR($$$AICoreToolAccessDenied, "人間の承認ゲートで却下されました。登録は行いません(ツール: " _ name _ ")。")
        }
        // それ以外 = 人間のフィードバック(指示)による差し戻し。指示を添えて拒否すると、
        // エージェントは失敗理由=指示を読み、作り直して再度 name を実行する(承認ループ)。
        Set feedback = $Extract(decision, $Length("REVISE:") + 1, *)
        Return $$$ERROR($$$AICoreToolAccessDenied, "人間のフィードバックにより差し戻されました。次の指示に従って内容を修正し、改めて " _ name _ " を実行してください → " _ feedback)
    }
    Return $$$OK
}

/// 人間の判断を得る。戻り: "APPROVE"(承認) / "REJECT"(却下) / "REVISE:<指示>"(フィードバック差し戻し)。
///   - テスト/決定的動作: プロセス内グローバル `^||Demo.Teacher.Approval` を最優先で使う。
///     連番添字(1,2,…)でキューにでき、消費するたびに次を返す(revise→approve のような往復も再現可)。
///     値の意味は 1=承認 / 0=却下 / それ以外の文字列=その文字列をフィードバックとして差し戻し。
///   - 端末が無い(JOB 子など非対話): 承認を取りようがないので**自動承認**し、その旨を注記する。
///   - 端末あり: 承認要求を整形表示し、y=承認 / n(空行)=却下 / それ以外=修正指示、を1行で受ける。
ClassMethod Decide(name As %String, call As %DynamicObject) As %String [ Private ]
{
    // スクリプト上書き(テスト/ヘッドレス。同一プロセス内のみ有効)。
    If $Data(^||Demo.Teacher.Approval) {
        Set ptr = $Increment(^||Demo.Teacher.ApprovalPtr)
        If $Data(^||Demo.Teacher.Approval(ptr)) { Set v = ^||Demo.Teacher.Approval(ptr) }
        Else { Set v = $Get(^||Demo.Teacher.Approval) }
        If v = 1 Return "APPROVE"
        If v = 0 Return "REJECT"
        Return "REVISE:" _ v
    }
    // 端末が無ければ人間に諮れない → 非対話。自動承認(注記)。
    If ($Principal = "/dev/null") || ($Principal = "") {
        Write !, "  → (非対話実行のため自動承認します。対話モード TalkAs では人間が承認します)", !
        Return "APPROVE"
    }
    // 端末あり: 人間に諮る。
    Set bar = "========================================"
    Set args = $Select($IsObject(call) && $IsObject(call.arguments): call.arguments, 1: {})
    Write !, bar, !
    Write "  【承認要求】設問を教材に登録します (human-in-the-loop)", !
    Write "    ツール : ", name, !
    If args.%Get("category") '= "" Write "    カテゴリ: ", args.%Get("category"), !
    If args.%Get("prompt") '= "" Write "    設問    : ", args.%Get("prompt"), !
    If args.%Get("modelAnswer") '= "" Write "    模範解答: ", args.%Get("modelAnswer"), !
    Write bar, !
    Set line = ""
    Set rc = ##class(%Library.Prompt).GetString("承認=y / 却下=n / 修正の指示を入力(例: もっと難しく): ", .line, , , , 0)
    If rc '= $$$SuccessResponse Return "REJECT"   // タイムアウト/中断は却下(安全側)
    Set low = $ZConvert($ZStrip(line, "<>W"), "L")
    If (low = "y") || (low = "yes") || (low = "はい") { Write "  → 承認されました。登録します。", ! Return "APPROVE" }
    If (low = "") || (low = "n") || (low = "no") || (low = "いいえ") { Write "  → 却下しました。登録しません。", ! Return "REJECT" }
    Write "  → 差し戻します(指示を反映して作り直します)。", !
    Return "REVISE:" _ line
}

/// 承認プロンプト表示用にツール名を求める。call.name を最優先、無ければ tool がツール定義 JSON なら
/// name を取り出し、どちらも取れなければ tool をそのまま返す(既に短いツール名のこともある)。
ClassMethod ToolName(tool As %String, call As %DynamicObject) As %String [ Private ]
{
    If $IsObject(call), (call.%Get("name") '= "") Return call.%Get("name")
    If $Extract($ZStrip(tool, "<W")) = "{" {
        Try {
            Set obj = ##class(%DynamicObject).%FromJSON(tool)
            If obj.%Get("name") '= "" Return obj.%Get("name")
        } Catch {}
    }
    Return tool
}

/// tool が承認対象か(APPROVALTOOLS のいずれかを部分一致で含むか)。
ClassMethod RequiresApproval(tool As %String) As %Boolean [ Private ]
{
    Set list = ..#APPROVALTOOLS
    For i = 1:1:$Length(list, ",") {
        Set name = $ZStrip($Piece(list, ",", i), "<>W")
        If (name '= ""), (tool [ name) Return 1
    }
    Return 0
}

/// メタデータから resource 要件を取り出す(未設定なら空文字)。
Method RequiredResource(metadata As %DynamicObject) As %String [ Private ]
{
    If '$IsObject(metadata) Return ""
    Set resource = metadata.%Get("resource")
    Return $Get(resource)
}

}
