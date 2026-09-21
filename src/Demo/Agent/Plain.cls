/// デモ用の最小エージェント(手順4)。
///
/// プロバイダは固定せず [[Demo.Agent.Base]] を継承する。手順3で Secure Wallet /
/// ConfigStore に登録したキー(openai / anthropic / bedrock のどれでも)が
/// `%OnInit()` で自動採用される。ソースには平文もプロバイダ名も持たない。
///
///   Base.%OnInit() が ConfigStore(AI.LLM.*)を優先順に探す
///     → GetDetails(...,resolveSecrets=1) が Wallet の secret:// を解決
///     → 平文キーは %AI.Provider 生成時のメモリ上にだけ現れる
///
/// 会話フロー: %New() → %Init() → CreateSession() → Chat(session,input)。
Class Demo.Agent.Hello Extends Demo.Agent.Base
{

/// システムプロンプト。text/markdown として %LoadInstructions() が読み込む。
XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
# 役割

あなたは「InterSystems AI Hub デモ」の案内役です。
ハーネスエンジニアリング(AI エージェントが安全に動く土台づくり)と AI Hub の
関係について、聞かれたことに簡潔な日本語で答えます。

## 応答方針

- 3文以内で簡潔に答える。
- 専門用語には一言の補足を添える。
}

/// デモ用ワンショット実行: 1メッセージ送って応答本文を表示する。
///
///   DEMO> do ##class(Demo.Agent.Hello).RunOnce("自己紹介して")
ClassMethod RunOnce(input As %String = "自己紹介して") As %Status
{
	try {
		set agent = ..%New()
		do agent.%Init()
		set session = agent.CreateSession()
		set response = agent.Chat(session, input)
		write "=== 応答 ===",!,response.Content,!
		if $isobject(response.Usage) {
			write "=== usage ===",!,response.Usage.%ToJSON(),!
		}
	} catch ex {
		write "エラー: ",ex.DisplayString(),!
		return ex.AsStatus()
	}
	return $$$OK
}

}
