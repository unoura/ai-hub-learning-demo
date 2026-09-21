# 先生エージェント: 権限で振る舞いが変わる

プレインエージェントは「ツールを持たず LLM と会話するだけ」でした。ここではその発展形として、
**ツールを持ち、呼び出す人の権限で振る舞いが変わる**先生エージェントを動かします。題材は
**情報セキュリティ・コンプライアンス研修**のトレーナーです。

見どころは 3 つ:

1. **権限でツールディスカバリが変わる** — 同じエージェントでも、受講者にはトレーナー用ツール(模範解答・採点)が**そもそも見えない**。
2. **trajectory(思考と行動の連鎖)を可視化** — エージェントがどのツールをどう呼んだかを追える。
3. **IRIS ベクトル検索** — 社内規程を意味検索し、**出典付き**で答える。

安全性はプロンプトのお願いではなく、**IRIS プラットフォームの RBAC(土台)**で担保されます。これが
ハーネスエンジニアリングの核心です。

> 設計・判断根拠は [../../design/agents/teacher-agent.md](../../design/agents/teacher-agent.md) を参照。

## 登場するクラス(`src/Demo/Teacher/`)

| クラス | 役割 |
|---|---|
| `Demo.Teacher.Teacher` | 先生エージェント本体([Demo.Agent.Base](plain-agent.md) 継承。プロバイダは自動採用) |
| `Demo.Teacher.ToolSet` | ツールセット。各ツールに**必要リソース**を紐付ける |
| `Demo.Teacher.RoleGuard` | 権限ゲート。`%CanList`(見せるか)/ `%CanExecute`(実行してよいか) |
| `Demo.Teacher.Tools.Learn` | `GetHint` — 答えでなく「調べる観点」を返す(全員) |
| `Demo.Teacher.Tools.AnswerKey` | `GetAnswerKey` — 模範解答・評価基準(**監査者のみ**) |
| `Demo.Teacher.Tools.Grade` | `ViewProgress` / `RecordScore` — 学習履歴の閲覧・採点(**監査者のみ**) |
| `Demo.Teacher.Security` | デモ用の RBAC(リソース / ロール / ユーザ)を作成 |
| `Demo.Teacher.RunAs` | 別ユーザの権限で「見えるツール」の違いを実演 |
| `Demo.Teacher.Monitor` | trajectory の観測(反復数・トークン) |
| `Demo.Teacher.Setup` | 教材データ投入 + ベクトル索引の構築 |

ツールと必要リソースの対応:

| ツール | 必要リソース | 受講者 | 監査者 |
|---|---|:--:|:--:|
| `SearchPolicy`(規程のベクトル検索) | なし | ✅ | ✅ |
| `GetHint` | `Demo_LearnRead` | ✅ | ✅ |
| `GetAnswerKey` | `Demo_AnswerKey` | ❌ | ✅ |
| `ViewProgress` / `RecordScore` | `Demo_Grade` | ❌ | ✅ |

## 前提

- Wallet 構成要素で **openai / anthropic / bedrock のいずれか1つ**を登録済み([Wallet 構成要素](../building-blocks/wallet.md))。
  先生エージェントは [プレインエージェント](plain-agent.md)と同じ `Demo.Agent.Base` を継承し、登録済みプロバイダを自動採用します。
- コードは起動時に自動ロードされます(`docker/start.sh` の `$system.OBJ.LoadDir`)。`src/` を編集したら再起動、
  または手動リロード:

  ```bash
  docker compose exec -T iris iris session IRIS -U DEMO \
    <<< ' set sc=$system.OBJ.LoadDir("/home/irisowner/dev/src","ck",,1) halt'
  ```

## 手順 1: RBAC(リソース / ロール / ユーザ)を作る

「誰が何を使えるか」の土台を IRIS 側に作ります。冪等なので何度実行しても構いません。

```bash
docker compose exec -it iris iris session iris -U DEMO
```

```objectscript
DEMO> do ##class(Demo.Teacher.Security).SetupRBAC()
[security] リソース3 / ロール3(基盤1+アプリ2) / ユーザ2 を用意しました。
```

作られるもの:

- **リソース**: `Demo_LearnRead`(学習支援)/ `Demo_AnswerKey`(模範解答)/ `Demo_Grade`(採点・進捗)
- **アプリロール**: `Demo_Learner`(LearnRead のみ)/ `Demo_Auditor`(全3リソース)
- **実行基盤ロール**: `Demo_Runtime`(DEMO 名前空間でコードを動かすための DB 権限)
- **ユーザ**: `learner01`(受講者)/ `auditor01`(トレーナー)。各アプリロール + `Demo_Runtime` を付与

> 「動かせる土台(`Demo_Runtime`)」と「何を見せるか(アプリロール)」を**層で分ける**のがポイントです。
> アプリ権限だけのユーザはそもそも名前空間で動けません。この分離自体がハーネスの設計思想です。
>
> 簡易的措置: デモ用にユーザを直接作成しています。本番は既存の認証基盤(LDAP / OAuth / Delegated 等)に接続します。
> パスワードはローカルデモ専用です。後始末は `do ##class(Demo.Teacher.Security).Teardown()`。

## 手順 2: 教材と検索索引を作る

社内規程・練習問題・模範解答を投入し、規程をベクトル索引化します(FastEmbed / 384次元、キー不要)。

```objectscript
DEMO> do ##class(Demo.Teacher.Setup).Rebuild()
```

これで `SearchPolicy`(規程のベクトル検索ツール)が使えるようになります。ベクトルは
`Demo_Teacher.PolicyVec` に永続化され、以後は再埋め込みなしで検索できます。

## 見どころ 1: 権限でツールディスカバリが変わる

**同じエージェント・同じ探索処理**でも、実行するユーザのロールで「見えるツール」が変わることを実演します。

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).Compare()
=== RunAs: ロール別のツールディスカバリ ===
learner01(...)が見えるツール: GetHint
auditor01(...)が見えるツール: GetAnswerKey, GetHint, RecordScore, ViewProgress
----
受講者には監査・採点ツールがそもそも見えない(%CanList で除外)。
```

- **受講者(learner01)には `GetHint` だけ**、監査者(auditor01)には 4 ツール全部が見えます。
- 判定は `RoleGuard.%CanList()` が `$SYSTEM.Security.Check(リソース, "USE")` で行います。
  **LLM は見えないツールを呼べない** — プロンプトインジェクションで模範解答を引き出そうとしても、
  そのツールは存在しないのと同じです(=土台での封じ込め)。
- 万一呼ばれても `%CanExecute()` が実行段階で再度拒否します(二重ガード)。

> なぜ別ユーザで実行するのに一手間かけるのか: `$SYSTEM.Security.Login` はプロセスの識別情報を
> **不可逆に**切り替えるため、`RunAs` は各ロールごとに `JOB` で子プロセスを起こし、その中でログイン→
> ディスカバリしています。

## 見どころ 2: trajectory とベクトル検索

規程に関わるゴールを 1 つ与えて、エージェントの**思考と行動の連鎖**を可視化します。

```objectscript
DEMO> do ##class(Demo.Teacher.Teacher).RunLesson("『情報持ち出し』の社内規程を調べて、出典付きで要点を教えて")
```

出力の流れ:

```
=== ゴール ===
『情報持ち出し』の社内規程を調べて、出典付きで要点を教えて
=== 反復(ハーネスの観測点)===
  [反復 1/6] 推論中…
      トークン(累計): ....
=== trajectory(思考と行動の連鎖)===
  👤 質問: 『情報持ち出し』の社内規程を調べて、出典付きで要点を教えて
  🤖→🔧 ツール呼び出し: SearchPolicy {"query":"情報持ち出し ..."}
  🔧→🤖 ツール結果: [{"title":"情報管理規程 ...
  🤖 回答を生成(... 文字)
=== 最終応答 ===
(情報管理規程 第7条・第25条を出典に、要点を日本語で説明)
=== 集計 ===
反復 1 回 / ツール呼び出し 1 回 / 累計トークン ....
```

- エージェントは自分で **`SearchPolicy`(ベクトル検索)を呼ぶ**判断をし、DB の規程本文を根拠に**出典(条番号)付き**で回答します。
- **trajectory はセッション履歴から再構成**しています(質問 → ツール呼び出し → ツール結果 → 回答生成)。
  誰が何をどのツールで行ったかを後から追える = 監査・再現の土台です。

> **プロンプトのコツ**: 「〜を調べて出典付きで教えて」のように**ツールを使う必然**があるゴールにすると、
> 確実にベクトル検索が走ります。
>
> **検索品質の正直な注意**: FastEmbed は英語モデルのため、語彙が一致する日本語質問には強い一方、
> 意味理解が要る質問(例: 「端末を紛失」→インシデント報告)では外すことがあります。デモは検索が
> 効く質問に寄せています。本番で日本語品質が要る場合は OpenAI 埋め込み等に切り替えます(設計ドキュメント参照)。

## 暗号化構成要素とのつながり

先生エージェントが扱う**受講者スコア(個人情報)**と**模範解答**は、[暗号化構成要素](../building-blocks/encryption.md)で
暗号化された `DEMO_DATA` に載っています。暗号化の価値が「API キー」だけでなく「学習データ」にも及ぶことを、
この題材で示せます。権限(RBAC)× データ暗号化 × ツール分離の多層で守ります。

## ここまでの全体像

```
構成要素: Docker → 暗号化 → Wallet
  → プレインエージェント(会話するだけ)
  → 先生エージェント(権限 × ツールディスカバリ × trajectory × ベクトル検索)
```

同じエージェント・同じ質問でも、**呼び出す人の権限で見えるツールと取れる行動が変わる**。しかもその過程を
追える。安全なエージェント運用の土台が、プラットフォーム側で成立していることを確認できました。
