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
見えるツール・取れる行動が変わる**ことを確かめます。登場人物は 2 人です。

- **生徒(student01)**: **練習問題を出してもらい**、自分の解答を**採点**してもらい(点数+講評が学習履歴に登録される)、**成績表**を見られる。
- **設問管理者(qadmin01)**: 規程を基に**設問を作成**して教材に登録できる。

ツールは役割でほぼ排他です: 出題・採点・成績(`ListPracticeQuestions` / `GradeMyAnswer` / `ShowReportCard`)は生徒だけ、作問(`RegisterQuestion`)は設問管理者だけ。規程検索(`SearchPolicy`)は誰でも使えます。

**4a. 権限でツールディスカバリが変わる**

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).Compare()
```

- 確認できること: `student01 → GradeMyAnswer, ListPracticeQuestions, ShowReportCard` / `qadmin01 → RegisterQuestion`。
- 何が起きているか: **同じエージェント・同じ探索処理でも、実行者のロールで見えるツールが変わります**。`%CanList` がカタログから除外するので、生徒には作問ツールが、設問管理者には採点・成績ツールが**そもそも見えません**=土台での封じ込め(プロンプトインジェクションでも呼べない)。

**4b. 取れる行動も変わる(実際に実行してみる)**

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).CompareActions()
```

- 確認できること: `student01` は **GradeMyAnswer ✓ 実行OK / RegisterQuestion ✗ カタログに存在しない**。`qadmin01` はその逆。
- 何が起きているか: 見えるだけでなく**取れる行動**も identity で割れます。さらに SQL レベルでもロールを揃えており、採点基準(AnswerKey)には**生徒に SELECT を与えていません**。採点(GradeMyAnswer)は**サーバ側で**採点基準と突き合わせて点数を出すため、**生徒は SQL からも採点基準を読めず、点数を自己申告することもできません**=ツール層 × SQL 層の多層防御です。

**4c. trajectory とベクトル検索(誰でも使える規程検索)**

```objectscript
DEMO> do ##class(Demo.Teacher.Teacher).RunLesson("『情報持ち出し』の社内規程を調べて、出典付きで要点を教えて")
```

- 確認できること: 反復の観測 → trajectory(👤質問 → 🤖→🔧 SearchPolicy 呼び出し → 🔧→🤖 結果 → 🤖 回答) → **出典(条番号)付きの最終応答** → 集計(反復/ツール呼び出し/トークン)。
- 何が起きているか: エージェントが自分で**ベクトル検索ツールを呼ぶ判断**をし、DB の規程を根拠に**出典付き**で答えます。**思考と行動の連鎖を後から追える**=監査・再現の土台になります。意味検索は IRIS のベクトル機能です。

続けて質問したいときは**対話モード**を使います(毎ターンその分の trajectory を表示。権限ゲートも同じく効く。`quit` で終了):

```objectscript
DEMO> do ##class(Demo.Teacher.Teacher).Talk()
```

**4d. 「生徒として」採点・成績表、「設問管理者として」作問**

会話そのものを、生徒 / 設問管理者の identity で実行して見比べます。同じエージェントでも、
LLM が**呼び出し元に見えるツール**を手がかりに役割を判断し、振る舞いを変えます。

```objectscript
; 生徒(student01)として: 練習問題を出してもらう(既存の設問から提示。作問はできない)
DEMO> do ##class(Demo.Teacher.RunAs).RunLessonAs("student01", "何か練習問題を1問出してください。")

; 生徒(student01)として: 解答を採点してもらう(点数+講評が学習履歴に登録される)
DEMO> do ##class(Demo.Teacher.RunAs).RunLessonAs("student01", "設問1に『12文字以上にして、記号を混ぜて、使い回さない』と答えます。採点してください。")

; 生徒(student01)として: 成績表を見る(直近の履歴から平均・弱点を要約)
DEMO> do ##class(Demo.Teacher.RunAs).RunLessonAs("student01", "これまでの私の成績表を見せてください。弱点も教えて。")

; 設問管理者(qadmin01)として: 規程を基に設問を作って登録する
DEMO> do ##class(Demo.Teacher.RunAs).RunLessonAs("qadmin01", "『情報持ち出し』の規程を根拠に、応用レベルの設問を1問つくって登録してください。")
```

- 確認できること:
  - 生徒(出題)→ **ListPracticeQuestions** を呼び、**既存の練習問題**(questionId 付き)を提示する。生徒は新しい設問を**作れない**(作問は設問管理者の権限)ので、既存問題から出題します。
  - 生徒(採点)→ **GradeMyAnswer** を呼び、**点数・到達/未達の観点・出典**を返す(模範解答の全文は出さない)。同じ質問を設問管理者で投げても、GradeMyAnswer が**見えない**ので採点できません。
  - 生徒(成績表)→ **ShowReportCard** で本人の直近履歴を取得し、**平均点・弱点分野**を要約して見せる(他人の成績は見えない)。
  - 設問管理者(作問)→ まず **SearchPolicy** で規程を調べ、その内容から設問・模範解答・採点基準を**生成**して **RegisterQuestion** で登録する。生徒側では RegisterQuestion が**カタログに無い**ので、どう促しても作問できません。
- 何が起きているか: エージェントは**呼び出し元の権限を「使えるツールの有無」として受け取り**、役割に応じて振る舞いを変えます。ここには「自律的な情報取得(ベクトル検索)」だけでなく、**要約(成績表)・生成(作問)・情報登録(採点結果/設問の書き込み)** という LLM ならではの働きが揃っています。しかもそれらの**実行可否は土台の権限で封じ込められて**います。
- 仕組み: `RunAs` が子プロセスで **「特権のうちに LLM キーを解決 → `Security.Login` で当該ユーザに切替 → 会話を実行」** します。LLM への到達(=Wallet シークレット)には特権が要る一方、**ツール認可と教材 SQL は切替後のユーザのロールで判定**されます。「鍵の取り扱い」と「ユーザ権限」を層で分けるハーネスの考え方そのものです。
- 補足: 上の `RunLessonAs` は**単発**の実行です。同じ役割差を**対話モード**で見たいときは `TalkAs` を使います(下記 4e)。

**4e. 対話モードで役割差を見る(TalkAs)**

対話しながら役割差を確かめたいときは、identity 付きの対話モードを使います。
**セッションを1本開いてそのユーザになりきる**ので、役割ごとにセッションを分けて開きます。

```objectscript
; 生徒として対話(別ターミナル / 別セッション)
DEMO> do ##class(Demo.Teacher.RunAs).TalkAs("student01")
あなた> 設問1に「12文字以上、記号を混ぜる、使い回さない」と答えます。採点して。
;   → GradeMyAnswer で採点(点数+講評)。続けて「成績表を見せて」も試せる。

; 設問管理者として対話(別のセッション)
DEMO> do ##class(Demo.Teacher.RunAs).TalkAs("qadmin01")
あなた> パスワード管理の規程から応用レベルの設問を1問作って登録して。
;   → SearchPolicy → RegisterQuestion で作問・登録。採点や成績表は頼んでも使えない。
```

- 確認できること: 4d と同じ役割差を、**対話しながら**確認できます。`quit` または空行で対話を終了します。
  対話の**冒頭で、エージェントが「いまできること」を自己紹介**します。この案内は**見えるツールに基づく**ので、生徒なら出題・採点・成績表、設問管理者なら作問、と**ロールで内容が自動的に変わり**、利用者は最初に何を頼めるか分かります。
- 何が起きているか: `TalkAs` は**現プロセスで**「特権のうちに LLM キーを解決 → `Security.Login` でそのユーザに切替 → 対話ループ」を行います。対話は端末入力(`READ`)を伴い子プロセスにできないため、この方式を取ります。
- 補足(重要): `Security.Login` は**取消不可**です。`TalkAs` を実行したセッションは以降そのユーザのままなので、**別の役割を試すときはセッションを開き直して**ください(1 ターミナル = 1 ロール)。

---

## 5. まとめ

```
構成要素: 軽量 IRIS(Docker) → IRISSECURITY 暗号化 → Wallet に API キー保護
  → プレインエージェント(会話するだけ)
  → 先生エージェント(生徒=採点・成績 / 設問管理者=作問。権限でツール・行動が変わる
      × 要約・生成・情報登録 × trajectory × ベクトル検索)
```

キーを一度も平文で置かず、権限差はプラットフォームで担保し、過程は追える。
**安全なエージェント運用の土台**を、AI Hub を使って IRIS 側で成立させられます。
これがハーネスエンジニアリングの実践です。

---

## リセット / 後始末

```objectscript
; 教材・採点履歴を初期状態へ戻す(デモ中に採点・作問すると Progress / Question が増えるため)。
; 規程・設問・模範解答・成績表デモ用の履歴をまとめて作り直す。
DEMO> do ##class(Demo.Teacher.Setup).Rebuild()

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
- **`RunLesson` は特権セッション(通常の DEMO 入室)で実行**する。identity 別に動かすのは `RunAs.RunLessonAs` / `TalkAs`(生徒 = student01 / 設問管理者 = qadmin01)。SearchPolicy が読むベクトル索引の SELECT 権限は共有ロール Demo_Runtime に付与済み。
- **構成要素の確認(手順 2)は `%SYS` セッション**で。エージェント実行(手順 3 / 4)は `DEMO` セッションで。
