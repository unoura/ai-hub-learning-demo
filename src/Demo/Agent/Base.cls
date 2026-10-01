/// マルチプロバイダ対応の共通ベースエージェント(プレイン/先生エージェント共通の土台)。
///
/// プロバイダを固定せず、`%OnInit()` で **ConfigStore に登録済みの LLM 設定を優先順に探し**、
/// 最初に見つかった1つを採用する(= 構成要素の Wallet で「入れたものが採用される」)。
/// キーはコードにも環境変数にも持たず、ConfigStore の `secret://` を `GetDetails(...,resolveSecrets=1)`
/// で Wallet から解決する(Wallet 構成要素の主旨と一致)。
///
/// この動的プロバイダ決定は ai-hub-eap の `%OnInit` パターンに準拠する。ただし eap は判定を
/// **環境変数**で行うのに対し、本デモは「キーを env に出さない」ため、判定の情報源だけを
/// **ConfigStore** に差し替えている(構造は同一)。
///
/// 継承側でツール登録等を足す場合は `%OnInit()` をオーバーライドし、先頭で `do ##super()` を呼ぶ。
Class Demo.Agent.Base Extends %AI.Agent [ Abstract ]
{

/// 採用を試すプロバイダの優先順(カンマ区切り)。ConfigStore の `AI.LLM.<provider>` を探す。
/// 複数登録時のみ順序が効く(通常は1つだけ登録)。エージェント側で上書き可能。
Parameter PROVIDERPRIORITY = "bedrock,anthropic,openai";

/// 採用したプロバイダ(ConfigStore の model_provider。例: bedrock / anthropic / openai)。表示用。
/// Provider オブジェクトは汎用の %AI.Provider なので、クラス名ではどのプロバイダか分からないため保持する。
Property ProviderName As %String;

/// 採用した ConfigStore の設定名(例: AI.LLM.bedrock)。表示用。
Property ConfigName As %String;

/// LLM リクエストに足す追加パラメータ(ConfigStore の extra_params)。セッション作成時に渡す。
/// 例: OpenAI gpt-5.x でツールを使うための {"reasoning_effort":"none"}(register-key.sh が設定)。
Property ExtraParams As %DynamicObject;

/// `%Init()` の最後に呼ばれるフック。プロバイダ未設定なら ConfigStore から動的に選んで生成する。
Method %OnInit() As %Status
{
	// 外から ..Provider を明示設定済みならそれを尊重(手動切り替えの余地)。
	Return:$IsObject(..Provider) $$$OK

	// 優先順に ConfigStore を見て、登録済みの最初の1つを採用。
	Set configName = ""
	Set priority = ..#PROVIDERPRIORITY
	For i=1:1:$Length(priority, ",") {
		Set cand = $ZStrip($Piece(priority, ",", i), "<>W")
		Continue:cand=""
		If ##class(%ConfigStore.Configuration).Exists("AI.LLM."_cand) {
			Set configName = cand
			Quit
		}
	}
	If configName = "" {
		Return $$$ERROR($$$GeneralError, "登録済みの LLM 設定(AI.LLM.*)がありません。docker/register-key.sh で openai / anthropic / bedrock のいずれかを登録してください。")
	}

	// ConfigStore から secret:// を解決して詳細を取得(checkValid=0, resolveSecrets=1)。
	Set sc = ##class(%ConfigStore.Configuration).GetDetails("AI.LLM."_configName, .details, 0, 1)
	If $$$ISERR(sc) Return sc

	// model_provider から Provider を生成し、model をエージェントに設定。
	Set ..Provider = ##class(%AI.Provider).Create(details.%Get("model_provider"), details)
	Set ..Model = details.%Get("model")
	Set ..ProviderName = details.%Get("model_provider")
	Set ..ConfigName = "AI.LLM."_configName
	Set:$IsObject(details.%Get("extra_params")) ..ExtraParams = details.%Get("extra_params")
	Return $$$OK
}

/// ConfigStore の extra_params を、セッションの設定(LLM リクエストへの追加パラメータ)として渡す。
Method CreateSession(config As %DynamicObject = "") As %AI.Agent.Session
{
	If $IsObject(..ExtraParams) {
		Set:'$IsObject(config) config = {}
		Do:'config.%IsDefined("extra_params") config.%Set("extra_params", ..ExtraParams)
	}
	Return ##super(config)
}

}
