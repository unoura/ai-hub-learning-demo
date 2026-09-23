/// 先生エージェント教材のセットアップ。サンプル規程/設問/模範解答を投入し、
/// 規程コーパスを FastEmbed(ローカル・キー不要・384次元)でベクトル化して
/// SearchPolicy 検索インデックスを構築する。
///
/// このフェーズでは「教材データ + IRIS ベクトル検索」までを対象にする
/// (権限制御・trajectory・採点ツールは後段)。
///
/// 手動セットアップ(起動時に FastEmbed を毎回走らせないため):
///   docker compose exec -T iris iris session iris -U DEMO
///   >>> do ##class(Demo.Teacher.Setup).Rebuild()
///   >>> do ##class(Demo.Teacher.Setup).Search("パスワードは何文字必要?")
Class Demo.Teacher.Setup
{

/// SearchPolicy ツール(= KnowledgeBase)の名前。
Parameter KBNAME = "SearchPolicy";

/// ベクトルを格納する SQL テーブル名。
Parameter VECTABLE = "Demo_Teacher.PolicyVec";

/// 冪等な全再構築: 既存データ/インデックスを消してサンプルを再投入し、検索インデックスを作り直す。
ClassMethod Rebuild() As %Status
{
    Set sc = ..Clear()
    If $$$ISERR(sc) Return sc
    Set sc = ..LoadSampleData()
    If $$$ISERR(sc) Return sc
    Set sc = ..BuildIndex()
    If $$$ISERR(sc) Return sc
    Set sc = ..SeedProgress()
    If $$$ISERR(sc) Return sc
    Write "[setup] 完了: 規程 ", ..CountOf("Demo_Teacher.Policy"), " 件 / 設問 ", ..CountOf("Demo_Teacher.Question"), " 件 をインデックス化し、成績表デモ用の履歴 ", ..CountOf("Demo_Teacher.Progress"), " 件を投入しました。", !
    Return $$$OK
}

/// SQL でテーブルの行数を返す(小さなユーティリティ)。
ClassMethod CountOf(table As %String) As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM " _ table)
    Return $Select(rs.%Next(): rs.%Get("N"), 1: 0)
}

/// 既存の教材データとベクトルインデックスを消去。
ClassMethod Clear() As %Status
{
    Do ##class(Demo.Teacher.Progress).%DeleteExtent()
    Do ##class(Demo.Teacher.AnswerKey).%DeleteExtent()
    Do ##class(Demo.Teacher.Question).%DeleteExtent()
    Do ##class(Demo.Teacher.Policy).%DeleteExtent()
    // ベクトルストアのテーブルを破棄(存在しなければ無害)。
    Try {
        Set vs = ##class(%AI.RAG.VectorStore.IRIS).%New()
        Set vs.TableName = ..#VECTABLE
        Do vs.Cleanup()
    } Catch {}
    Return $$$OK
}

/// サンプルの規程/設問/模範解答を投入。
ClassMethod LoadSampleData() As %Status
{
    // Category ^ Title ^ Source ^ Body
    Set policies = $ListBuild(
        $ListBuild("パスワード管理", "パスワードの要件", "情報セキュリティ規程 第12条", "業務アカウントのパスワードは12文字以上とし、英大文字・小文字・数字・記号のうち3種類以上を含める。他サービスとの使い回しを禁止する。多要素認証(MFA)が利用可能な場合は必ず有効化する。"),
        $ListBuild("アクセス管理", "最小権限と退職時対応", "情報セキュリティ規程 第18条", "アクセス権限は業務上必要な範囲に限定する(最小権限の原則)。従業員の退職・異動時は当日中に不要なアカウントとアクセス権を無効化する。権限の棚卸しを四半期ごとに実施する。"),
        $ListBuild("情報持ち出し", "機密データの持ち出し", "情報管理規程 第7条", "個人情報・顧客データを含む機密情報のUSBメモリ等での持ち出しは原則禁止。やむを得ず持ち出す場合は上長承認と暗号化を必須とする。私物端末への機密データの保存を禁止する。"),
        $ListBuild("インシデント", "インシデント報告", "情報セキュリティ規程 第25条", "情報漏えい・不正アクセス・端末紛失などのインシデントを発見した場合は、隠さず速やかに情報システム部門とセキュリティ責任者へ報告する。自己判断での対処や隠蔽を禁止する。"),
        $ListBuild("メール", "不審メール・フィッシング対応", "情報セキュリティ規程 第22条", "差出人不明のメールの添付ファイルやリンクを開かない。取引先を装ったパスワードや送金の依頼は電話等の別経路で確認する。誤って開いた場合は直ちにセキュリティ窓口へ報告する。"),
        $ListBuild("物理セキュリティ", "クリアデスク・クリアスクリーン", "情報管理規程 第11条", "離席時は端末をロックし、機密書類は施錠可能な場所に保管する。来客エリアに機密情報を放置しない。オフィス外での画面ののぞき見に注意する。"),
        $ListBuild("個人情報保護", "個人情報の取り扱い", "個人情報保護規程 第4条", "個人情報は取得時に明示した利用目的の範囲内でのみ利用する。第三者提供には原則として本人同意を要する。保管期間を過ぎた個人情報は適切に削除・廃棄する。"),
        $ListBuild("コンプライアンス", "接待・贈答と利益相反", "コンプライアンス規程 第9条", "取引先との接待・贈答は社会通念上の範囲を超えない。一定金額を超える贈答の授受は事前申告と承認を要する。自身の利益と会社の利益が相反しうる場合は利益相反として申告する。"),
        $ListBuild("委託先管理", "業務委託先の管理", "情報管理規程 第15条", "業務委託契約には守秘義務と情報の適正管理を明記する。再委託には委託元の事前承認を要する。委託先のセキュリティ対策状況を定期的に確認する。"),
        $ListBuild("情報発信", "SNS・社外発信の注意", "コンプライアンス規程 第14条", "業務上知り得た非公開情報をSNS等に投稿しない。所属を明示して発信する場合は会社の見解と個人の見解を区別する。顧客が特定される情報の投稿を禁止する。"))

    For i = 1:1:$ListLength(policies) {
        Set row = $List(policies, i)
        Set p = ##class(Demo.Teacher.Policy).%New()
        Set p.Category = $ListGet(row, 1)
        Set p.Title = $ListGet(row, 2)
        Set p.Source = $ListGet(row, 3)
        Set p.Body = $ListGet(row, 4)
        Set sc = p.%Save()
        If $$$ISERR(sc) Return sc
    }

    // Category ^ Prompt ^ ModelAnswer ^ Rubric ^ KeyPoints
    // KeyPoints は自動採点用。"観点名=語1|語2;観点名=語1|語2"(観点は ";"、同義語は "|" 区切り)。
    Set quizzes = $ListBuild(
        $ListBuild("パスワード管理", "安全なパスワードの要件を3つ挙げてください。", "12文字以上であること / 英大文字・小文字・数字・記号を混在させ他サービスと使い回さないこと / 多要素認証(MFA)を併用すること。", "3要件それぞれ1点。文字数・複雑さ・使い回し禁止・MFAのうち3つ挙げていれば満点。", "文字数=12文字|12 文字|文字数|長さ;複雑さ=記号|大文字|小文字|数字|複雑|文字種|混在;使い回し・MFA=使い回|使いまわ|MFA|多要素|二要素|ワンタイム"),
        $ListBuild("情報持ち出し", "在宅勤務で顧客データを扱う際の注意点を述べてください。", "USB等での持ち出しは原則禁止。やむを得ない場合は上長承認と暗号化を行う。私物端末に機密データを保存しない。", "承認/暗号化/私物端末禁止 の観点を各1点で評価。", "承認=承認|上長|上司|許可;暗号化=暗号化|暗号;私物端末禁止=私物|個人端末|個人のPC|自分の端末"),
        $ListBuild("インシデント", "不審メールの添付ファイルを誤って開いてしまいました。最初にすべきことは?", "自己判断で対処・隠蔽せず、直ちに情報システム部門/セキュリティ窓口へ報告する。", "『速やかに報告』『隠蔽しない』が含まれれば正答。個別の技術対処は加点要素。", "速やかに報告=報告|連絡|窓口|情報システム|速やか|直ち;隠さない=隠さ|隠蔽しない|自己判断しない"),
        $ListBuild("コンプライアンス", "取引先から高額な贈答を受けそうな場合の対応は?", "社会通念上の範囲を超える贈答は受けず、一定金額を超える場合は事前申告と承認を得る。利益相反の懸念があれば申告する。", "事前申告・承認、利益相反申告の観点を評価。", "事前申告・承認=申告|承認|事前|届け出;利益相反=利益相反|範囲を超え|社会通念|受けない"))

    For i = 1:1:$ListLength(quizzes) {
        Set row = $List(quizzes, i)
        Set q = ##class(Demo.Teacher.Question).%New()
        Set q.Category = $ListGet(row, 1)
        Set q.Prompt = $ListGet(row, 2)
        Set sc = q.%Save()
        If $$$ISERR(sc) Return sc
        Set a = ##class(Demo.Teacher.AnswerKey).%New()
        Set a.Question = q
        Set a.ModelAnswer = $ListGet(row, 3)
        Set a.Rubric = $ListGet(row, 4)
        Set a.KeyPoints = $ListGet(row, 5)
        Set sc = a.%Save()
        If $$$ISERR(sc) Return sc
    }
    Return $$$OK
}

/// 成績表デモ用の初期履歴を投入する(生徒 student01)。
/// ShowReportCard が「直近10件」から平均・傾向を要約できるよう、複数設問・点数の履歴を作る。
/// Learner はユーザ名の文字列で、student01 が未作成でも投入できる(採点履歴はユーザ実体に依存しない)。
ClassMethod SeedProgress() As %Status
{
    // questionId ^ score ^ comment
    Set rows = $ListBuild(
        $ListBuild(1, 100, "100点(3/3 観点)。到達: 文字数, 複雑さ, 使い回し・MFA。出典: 情報セキュリティ規程 第12条。"),
        $ListBuild(2, 67, "67点(2/3 観点)。到達: 承認, 暗号化。未達: 私物端末禁止。出典: 情報管理規程 第7条。"),
        $ListBuild(3, 100, "100点(2/2 観点)。到達: 速やかに報告, 隠さない。出典: 情報セキュリティ規程 第25条。"),
        $ListBuild(4, 50, "50点(1/2 観点)。到達: 事前申告・承認。未達: 利益相反。出典: コンプライアンス規程 第9条。"),
        $ListBuild(1, 67, "67点(2/3 観点)。到達: 文字数, 複雑さ。未達: 使い回し・MFA。出典: 情報セキュリティ規程 第12条。"),
        $ListBuild(3, 100, "100点(2/2 観点)。到達: 速やかに報告, 隠さない。出典: 情報セキュリティ規程 第25条。"))
    For i = 1:1:$ListLength(rows) {
        Set row = $List(rows, i)
        Set q = ##class(Demo.Teacher.Question).%OpenId($ListGet(row, 1))
        If '$IsObject(q) Continue
        Set p = ##class(Demo.Teacher.Progress).%New()
        Set p.Learner = "student01"
        Set p.Question = q
        Set p.Score = $ListGet(row, 2)
        Set p.Comment = $ListGet(row, 3)
        Set sc = p.%Save()
        If $$$ISERR(sc) Return sc
    }
    Return $$$OK
}

/// 規程コーパスをベクトル化して SearchPolicy インデックスを構築する。
ClassMethod BuildIndex() As %Status
{
    Set emb = ##class(%AI.RAG.Embedding.FastEmbed).Create()
    Set vs = ##class(%AI.RAG.VectorStore.IRIS).%New()
    Set vs.TableName = ..#VECTABLE
    Set vs.Dimensions = emb.Dimensions
    Set vs.ModelName = emb.ModelName
    Set sc = vs.Build()
    If $$$ISERR(sc) Return sc

    Set kb = ##class(%AI.RAG.KnowledgeBase).%New()
    Set kb.Name = ..#KBNAME
    Set kb.Description = "社内ポリシー(情報セキュリティ・コンプライアンス)の規程を検索し、根拠(出典)付きで関連条文を返す。"
    Set kb.TopK = 3
    Set sc = kb.Build(emb, vs)
    If $$$ISERR(sc) Return sc

    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Category, Title, Body, Source FROM Demo_Teacher.Policy")
    While rs.%Next() {
        Set meta = {}
        Set meta.category = rs.%Get("Category")
        Set meta.title = rs.%Get("Title")
        Set meta.source = rs.%Get("Source")
        Set meta.policyId = rs.%Get("ID")
        Set body = rs.%Get("Title") _ "。" _ rs.%Get("Body")
        Set sc = kb.AddDocument(body, meta)
        If $$$ISERR(sc) Return sc
    }
    Return $$$OK
}

/// 既存のベクトルストア上に KnowledgeBase を再構成(再埋め込みなし)して返す。
/// 検索やツール登録で使う。
ClassMethod OpenKnowledgeBase(Output kb As %AI.RAG.KnowledgeBase) As %Status
{
    Set emb = ##class(%AI.RAG.Embedding.FastEmbed).Create()
    Set vs = ##class(%AI.RAG.VectorStore.IRIS).%New()
    Set vs.TableName = ..#VECTABLE
    Set vs.Dimensions = emb.Dimensions
    Set vs.ModelName = emb.ModelName
    Set sc = vs.Build()
    If $$$ISERR(sc) Return sc
    Set kb = ##class(%AI.RAG.KnowledgeBase).%New()
    Set kb.Name = ..#KBNAME
    Set kb.Description = "社内ポリシー(情報セキュリティ・コンプライアンス)の規程を検索し、根拠(出典)付きで関連条文を返す。"
    Set kb.TopK = 3
    Return kb.Build(emb, vs)
}

/// 検索を実行して結果(出典・スコア付き)を表示する。動作確認・デモ用。
ClassMethod Search(query As %String, topK As %Integer = 3) As %Status
{
    Set sc = ..OpenKnowledgeBase(.kb)
    If $$$ISERR(sc) Return sc
    Set kb.TopK = topK
    Set mgr = ##class(%AI.ToolMgr).%New()
    Do kb.AddToManager(mgr)
    Set res = mgr.ExecuteTool(kb.Name, {"query": (query)})
    Write "検索: ", query, !
    Set hits = res.%Get("value")
    If '$IsObject(hits) { Write "(結果なし)", ! Return $$$OK }
    Set it = hits.%GetIterator()
    While it.%GetNext(.k, .hit) {
        Write "  [", $FNumber(hit.score, "", 3), "] ", hit.metadata.source, " — ", hit.text, !
    }
    Return $$$OK
}

}
