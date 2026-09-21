# AI Hub で実践するハーネスエンジニアリング(実践ガイド)

AI Hub を活用した**ハーネスエンジニアリング**を、以下の手順で実践できます。
「安全性はプロンプトのお願いではなく、プラットフォーム(ハーネス)側の権限で担保する」という考え方を、
実際に手を動かしながら確かめていきます。

進め方は 1 本の流れになっています。**構成要素(Docker → 暗号化 → Wallet)で土台を作り**、
その上で**プレインエージェント**、さらに**先生エージェント**へと発展させます。
各手順に「実行するコマンド / 確認できること / 何が起きているか」を添えています。

各トピックの詳しい背景は個別ガイドを参照してください(このページは通しの流れと要点をまとめたものです):
[docker](building-blocks/docker.md) / [encryption](building-blocks/encryption.md) / [wallet](building-blocks/wallet.md) /
[plain-agent](agents/plain-agent.md) / [teacher-agent](agents/teacher-agent.md)。

> 一言でいうと: **暗号化された土台に Wallet で API キーを守り、その上でエージェントを動かす。
> 安全性はプロンプトではなく、プラットフォーム(ハーネス)側の権限で担保される。**

---

## 1. セットアップ(最初に一度だけ)

以下は**時間がかかる/対話入力が要る/一度きり**の準備です。
Durable %SYS に永続化されるので、一度実行すれば `docker compose down`(`-v` なし)/ `up` をまたいで再利用できます。

```bash
# (1) ビルド & 起動。初回起動で IRISSECURITY の暗号化まで自動実行される(数分)。
docker compose up -d --build
docker compose logs -f iris | grep "\[demo\]"   # 「暗号化を確認しました(EncryptedDB=1)」まで待つ

# (2) LLM プロバイダのキーを手動登録(対話・非表示入力)。bedrock / openai / anthropic のどれか1つでよい。
docker compose exec -it iris bash /home/irisowner/dev/docker/register-key.sh bedrock
#   → プロンプトにキー(Bedrock は bearer token)を貼り付け。region は既定 us-east-1。
#   → "[wallet] AISecrets.Bedrock / AI.LLM.bedrock 登録完了 ..." が出れば成功。

# (3) 先生エージェントの教材投入 + ベクトル索引の構築(FastEmbed が走る。数十秒)。
# (4) RBAC(ロール/ユーザ/SQL 権限)の作成。
docker compose exec -T iris iris session iris -U DEMO <<'OBJ'
 do ##class(Demo.Teacher.Setup).Rebuild()
 do ##class(Demo.Teacher.Security).SetupRBAC()
 halt
OBJ
```

> やり直したいとき: `docker compose down -v`(永続ボリューム削除)→ `up -d --build` で真っさらから。
> 状態を残したまま止めるなら `docker compose down`(`-v` なし)。

準備ができたら、IRIS セッションに入ります(**日本語を正しく表示するため `-it`**)。
構成要素の確認(手順 2)では `%SYS` セッションを別ターミナルで開いておくと進めやすいです。

```bash
docker compose exec -it iris iris session iris -U DEMO
```

---

## 2. 土台(構成要素)を確認する

エージェントを動かす前に、土台が安全に整っていることを自分の目で確認します。

> **実行場所に注意**: 手順 2 の確認は**ホストのシェル**で打つコマンドです(IRIS の `DEMO>` プロンプトに貼らない)。
> すでに IRIS セッション内にいる場合は、後述の「IRIS セッション内で確認する場合」を使ってください。

**2a. 暗号化を確認する**(ホストのシェル)

```bash
IRIS_USERNAME=_SYSTEM IRIS_PASSWORD=SYS iris-agentic-dev exec -n %SYS \
  'set db=##class(SYS.Database).%OpenId("/durable/iscdata/mgr/irissecurity/") write "enc=",db.EncryptedDB'
# → enc=1
```

- 確認できること: `enc=1`(IRISSECURITY は暗号化済み)。
- 何が起きているか: 認証情報と次の Wallet シークレットが**保存時(at-rest)**で守られます。解錠資格は自動生成・内部保存で、**パスワードを `.env` に置きません**。

**2b. Wallet を確認する**(ホストのシェル。登録したプロバイダに合わせる。ここでは bedrock)

```bash
docker compose exec -T iris iris session IRIS -U %SYS <<'OBJ'
 write "wallet exists: ",##class(%Wallet.KeyValue).%ExistsId("AISecrets.Bedrock"),!
 do ##class(%ConfigStore.Configuration).GetDetails("AI.LLM.bedrock",.d,0,0)
 write "config api_key: ",d.%Get("api_key"),!
 halt
OBJ
```

**IRIS セッション内で確認する場合**(すでに `DEMO>` にいるとき。`'...'` で囲まず、`%SYS` に切り替えて打つ):

```objectscript
DEMO> zn "%SYS"
%SYS> set db=##class(SYS.Database).%OpenId("/durable/iscdata/mgr/irissecurity/")  write "enc=",db.EncryptedDB
%SYS> write "wallet exists: ",##class(%Wallet.KeyValue).%ExistsId("AISecrets.Bedrock"),!  do ##class(%ConfigStore.Configuration).GetDetails("AI.LLM.bedrock",.d,0,0)  write "config api_key: ",d.%Get("api_key"),!
%SYS> zn "DEMO"
```

- 確認できること: `wallet exists: 1` と `config api_key: secret://AISecrets.Bedrock#key`(**平文でなく参照だけ**)。
- 何が起きているか: キーの実体は暗号化 Wallet(`^WALLET`)にあり、設定側は名前参照だけを持ちます。**`.env`・環境変数・`docker inspect`・シェル履歴のどこにも平文が出ません**。

---

## 3. プレインエージェントを動かす(会話するだけ)

まずはツールを持たない最小構成のエージェントで、土台が機能していることを確かめます。

```objectscript
DEMO> do ##class(Demo.Agent.Plain).RunOnce("あなたは何ができますか?一言で。")
```

- 確認できること: LLM の応答本文 + トークン使用量。
- 何が起きているか: Wallet のキーを **ConfigStore の名前参照だけ**で解決して LLM に到達しています。プロバイダは登録済みのものを**自動採用**(このガイドでは Bedrock 上の Claude)。平文キーはメモリ上の生成時にしか存在しません。

続けて会話したいときは**対話モード**を使います(`quit` または空行で終了。会話履歴は保持されます):

```objectscript
DEMO> do ##class(Demo.Agent.Plain).Talk()
```

---

## 4. 先生エージェントを動かす(権限で振る舞いが変わる)

ここがハーネスエンジニアリングの核心です。**同じエージェント・同じ質問でも、呼び出す人の権限で
見えるツール・取れる行動が変わる**ことを、3 つの見どころで確かめます。

**4a. 権限でツールディスカバリが変わる**

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).Compare()
```

- 確認できること: `learner01 → GetHint` のみ / `auditor01 → GetAnswerKey, GetHint, RecordScore, ViewProgress`。
- 何が起きているか: **同じエージェント・同じ探索処理でも、実行者のロールで見えるツールが変わります**。`%CanList` がカタログから除外するので、受講者には監査・採点ツールが**そもそも見えません**=土台での封じ込め(プロンプトインジェクションでも呼べない)。

**4b. 取れる行動も変わる(実際に実行してみる)**

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).CompareActions()
```

- 確認できること: `learner01` は両方 **✗ 権限なし(カタログに存在しない)**。`auditor01` は **✓ 模範解答を取得 / ✓ 採点を記録(ok:1)**。
- 何が起きているか: 見えるだけでなく**取れる行動**も identity で変わります。しかも SQL レベルでもロールを揃えており(受講者は教材の SELECT だけ)、**受講者は SQL からも模範解答を読めません**=ツール層 × SQL 層の多層防御です。

**4c. trajectory とベクトル検索**

```objectscript
DEMO> do ##class(Demo.Teacher.Teacher).RunLesson("『情報持ち出し』の社内規程を調べて、出典付きで要点を教えて")
```

- 確認できること: 反復の観測 → trajectory(👤質問 → 🤖→🔧 SearchPolicy 呼び出し → 🔧→🤖 結果 → 🤖 回答) → **出典(条番号)付きの最終応答** → 集計(反復/ツール呼び出し/トークン)。
- 何が起きているか: エージェントが自分で**ベクトル検索ツールを呼ぶ判断**をし、DB の規程を根拠に**出典付き**で答えます。**思考と行動の連鎖を後から追える**=監査・再現の土台になります。意味検索は IRIS のベクトル機能です。

続けて質問したいときは**対話モード**を使います(毎ターンその分の trajectory を表示。権限ゲートも同じく効く。`quit` で終了):

```objectscript
DEMO> do ##class(Demo.Teacher.Teacher).Talk()
```

---

## 5. まとめ

```
構成要素: 軽量 IRIS(Docker) → IRISSECURITY 暗号化 → Wallet に API キー保護
  → プレインエージェント(会話するだけ)
  → 先生エージェント(権限 × ツールディスカバリ × 取れる行動 × trajectory × ベクトル検索)
```

キーを一度も平文で置かず、権限差はプラットフォームで担保し、過程は追える。
**安全なエージェント運用の土台**を、AI Hub を使って IRIS 側で成立させられます。
これがハーネスエンジニアリングの実践です。

---

## リセット / 後始末

```objectscript
; 書き込んだ採点データを消す(任意。RunAs.CompareActions が Progress に行を追加する)
DEMO> &sql(DELETE FROM Demo_Teacher.Progress)

; RBAC(ロール/ユーザ)を撤去する場合
DEMO> do ##class(Demo.Teacher.Security).Teardown()
```

```bash
# 状態を残して停止(暗号化・Wallet・RBAC・教材は保持)
docker compose down

# 完全リセット(次回は「1. セットアップ」からやり直し)
docker compose down -v
```

## うまくいかないとき / 注意

- **日本語が `?` に化ける**: セッションは `-it`(TTY)で入る。`-T`(パイプ)だと表示だけ化ける(データは正常)。
- **`RunLesson` がツールを呼ばず一般論で答える**: ゴールを「〜を調べて出典付きで教えて」のように**ツールを使う必然**がある形にする。
- **キー貼り付けで先頭1文字が欠ける端末**: `register-key.sh` の `len=` が想定より短ければ再実行(上書き登録)。
- **`RunLesson` は特権セッション(通常の DEMO 入室)で実行**する。SearchPolicy はベクトル索引を読むため、受講者 identity では別途 SELECT 権限が要る(このガイドの範囲外)。
- **構成要素の確認(手順 2)は `%SYS` セッション**で。エージェント実行(手順 3 / 4)は `DEMO` セッションで。
