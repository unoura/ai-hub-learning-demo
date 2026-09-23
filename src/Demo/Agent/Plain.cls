/// プレインエージェント: ツールを持たず LLM と会話するだけの最小エージェント。
///
/// プロバイダは固定せず [[Demo.Agent.Base]] を継承する。構成要素の Wallet /
/// ConfigStore に登録したキー(openai / anthropic / bedrock のどれでも)が
/// `%OnInit()` で自動採用される。ソースには平文もプロバイダ名も持たない。
///
///   Base.%OnInit() が ConfigStore(AI.LLM.*)を優先順に探す
///     → GetDetails(...,resolveSecrets=1) が Wallet の secret:// を解決
///     → 平文キーは %AI.Provider 生成時のメモリ上にだけ現れる
///
/// 会話フロー: %New() → %Init() → CreateSession() → Chat(session,input)。
/// ここから権限で振る舞いが変わる先生エージェントへ発展する。
Class Demo.Agent.Plain Extends Demo.Agent.Base
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
///   DEMO> do ##class(Demo.Agent.Plain).RunOnce("自己紹介して")
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

/// 対話モード: session を1つ作り、入力ごとに Chat を回して会話を続ける。
/// session が履歴を保持するので、前のやり取りを踏まえた応答になる。
/// `quit`(または空行)で終了。日本語表示のため `-it` で入ったセッションで実行する。
///
///   DEMO> do ##class(Demo.Agent.Plain).Talk()
ClassMethod Talk() As %Status
{
	try {
		set agent = ..%New()
		do agent.%Init()
		set session = agent.CreateSession()
		write "=== プレインエージェント 対話モード ===",!
		write "メッセージを入力してください(quit または空行で終了)。",!
		for {
			write !,"あなた> "
			read input
			set input = $zstrip(input,"<>W")
			if (input="")||$listfind($listbuild("quit","exit","/quit","/exit"),$zconvert(input,"L")) { quit }
			set response = agent.Chat(session, input)
			write !,"エージェント> ",!
			do ..Say(response.Content)
			write !
		}
		write !,"=== 終了 ===",!
	} catch ex {
		write "エラー: ",ex.DisplayString(),!
		return ex.AsStatus()
	}
	return $$$OK
}

/// 改行を CRLF に正規化して書き出す(TTY で LF だけだと行頭に戻らず段組みがずれるため)。
ClassMethod Say(text As %String) [ Private ]
{
	set text = $replace(text, $char(13, 10), $char(10))
	set text = $replace(text, $char(10), $char(13, 10))
	write text
}

}
