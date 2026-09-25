/// trajectory(思考と行動の連鎖)を観測するコールバック。
/// <method>%AI.Agent.Run</method> の第4引数に渡すと、外側の反復ごとに開始/完了フックが呼ばれる。
///
/// Run の1反復の内側で Chat がツール呼び出しループ(推論→ツール実行→再推論)を回すため、
/// このコールバックが受け取る response は「その反復の最終応答」になる。よってツール呼び出しの
/// 明細は [[Demo.Teacher.Teacher]] の ShowTrajectory(セッション履歴)で描く。ここでは
/// 「反復回数」と「トークン使用量」というハーネス側の観測点を担う。
Class Demo.Teacher.Monitor Extends %RegisteredObject
{

/// 観測した反復回数。
Property Iterations As %Integer [ InitialExpression = 0 ];

/// 1 にすると画面へ何も書かず、反復回数の記録だけを行う(対話モードで応答を読みやすく保つため)。
Property Quiet As %Boolean [ InitialExpression = 0 ];

/// 反復開始フック(LLM 呼び出し前)。
Method OnIterationStart(iteration As %Integer, maxIter As %Integer, session As %AI.Agent.Session)
{
    Set ..Iterations = iteration
    Quit:..Quiet
    Write "  [反復 ", iteration, "/", maxIter, "] 推論中…", !
}

/// 反復完了フック(LLM 応答+ツール実行の後)。累計トークンを表示する。
Method OnIterationComplete(iteration As %Integer, response As %AI.LLM.Response, session As %AI.Agent.Session)
{
    If '..Quiet, $IsObject(response.Usage) {
        Write "      トークン(累計): ", response.Usage."total_tokens", !
    }
}

}
