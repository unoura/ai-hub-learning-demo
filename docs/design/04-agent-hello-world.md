# 設計: 手順4 エージェント Hello World

## ねらい

AI Hub の Native Agent(`%AI.Agent`)で最小の「Hello World」を作り、手順3で Wallet に登録した
API キーを **ConfigStore の名前参照だけ**で解決して、実際に OpenAI と対話できることを確認する。
これで「Docker → 暗号化 → Wallet → エージェント」の一連が閉じる。

## 採用した構成(実機で疎通確認済み)

**エージェント1クラスだけ**の最小構成にした(`src/Demo/Agent/Hello.cls`、`%AI.Agent` 継承)。

| 要素 | 採用 | 理由 |
|---|---|---|
| キー解決 | `Parameter PROVIDERCONFIG = "@{config:AI.LLM.openai}"` | 手順3の ConfigStore→Wallet 参照をそのまま使う。**ソースに平文キーを書かない**のが主眼 |
| システムプロンプト | `XData INSTRUCTIONS [ MimeType = "text/markdown" ]` | `%AI.Agent` の `%LoadInstructions()` が Markdown として読む(既存 `%AI.Shell.ConsoleAgent` と同形) |
| 会話フロー | `%New()` → `%Init()` → `CreateSession()` → `Chat(session,input)` | この build で実在するメソッド。応答は `%AI.LLM.Response.Content` |
| 実行ヘルパ | `ClassMethod RunOnce(input)` | デモを1行で回せるように。例外は捕捉して読みやすく表示 |

### なぜ Tool / ToolSet を作らないか

当初案は AI Hub の4層(Tool → ToolSet → Agent → MCP)を一通り見せる構成だったが、
**「Hello World = Wallet のキーで LLM に到達できる」ことの確認**が手順4の目的なので、
ツール呼び出しは含めない最小構成にした。ツール・MCP 公開は発展形として後段に回す。

## Wallet → エージェントの解決チェーン(手順3と接続)

```
%AI.Agent Parameter PROVIDERCONFIG = "@{config:AI.LLM.openai}"
  → %Init() が %AI.Utils.SettingStore.RegisterDefaults() を呼ぶ
  → SettingStore.Expand : @{config:AI.LLM.openai} を ConfigStore 設定に展開
  → ConfigStore         : api_key = "secret://AISecrets.OpenAI#key"(参照だけ)
  → secret:// 解決      : Wallet(暗号化 IRISSECURITY)から実値を取得
  → %AI.Provider.Create : ここで初めて平文キーがメモリ上に現れる
  → Chat(session,input) → OpenAI → %AI.LLM.Response.Content
```

平文が現れるのは Provider 生成の直前・メモリ上だけ。ソース・設定・環境変数・ログには残らない。

## コードロード方式 = src/ 起動時ロード(簡易的措置)

`docker/start.sh` の初回初期化で、暗号化の**後**に
`$system.OBJ.LoadDir("/home/irisowner/dev/src","ck",,1)` を DEMO 名前空間で実行する。
リポジトリは `/home/irisowner/dev` に bind-mount 済みなので、`src/` を編集 → 再起動(または
手動リロード)で反映できる。毎起動でコンパイルする冪等な処理。

| 論点 | 採用 | 本番向け(正準) |
|---|---|---|
| パッケージング | `src/` を `LoadDir` で読む | **ZPM(`module.xml`)** でパッケージ化・依存/バージョン管理・配布 |

デモの主題は Wallet→エージェントの流れであり、パッケージング手法の紹介ではないため、
説明の焦点をぼかさない軽量ロードを採った。配布・複数クラス・依存が絡む本番では ZPM が正準。

## デモとしての簡易的措置 と 本番運用

| 簡易的措置 | 内容 | 本番向け |
|---|---|---|
| プロバイダ | OpenAI 固定(`AI.LLM.openai`) | `PROVIDERCONFIG` を切り替え、または設定でプロバイダ選択。手順3で対応キーを登録 |
| コードロード | `src/` 起動時 `LoadDir` | ZPM(`module.xml`)でパッケージ配布 |
| ツール | なし(最小 Hello World) | `%AI.Tool` / `%AI.ToolSet` / `%AI.MCP.Service` で機能拡張 |

## 手順3との接続

エージェントは平文キーを一切持たず、`@{config:AI.LLM.openai}` という**名前**でしか API キーを
参照しない。実体は手順3で Wallet(暗号化 IRISSECURITY、手順2)に保護されている。
したがって本手順は手順2・3の上にしか成立しない。
