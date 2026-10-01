# AI Hub で実践するハーネスエンジニアリング(実践ガイド)

**ハーネスエンジニアリング**の要素のうち、権限制御・監査・人間の承認などを、AI Hub を使って以下の手順で試せます。
「安全性をプロンプトのお願いだけに頼らず、プラットフォーム(ハーネス)側の権限でも担保する」という考え方を、
実際に手を動かしながら確かめていきます。

進め方は 1 本の流れになっています。**構成要素(Docker → 暗号化 → Wallet)で土台を作り**、
その上で**プレインエージェント**、さらに**先生エージェント**へと発展させます。
各手順に「実行するコマンド / 確認できること / 何が起きているか」を添えています。

各トピックの詳しい背景は個別ガイドを参照してください(このページは通しの流れと要点をまとめたものです):
[docker](building-blocks/docker.md) / [encryption](building-blocks/encryption.md) / [wallet](building-blocks/wallet.md) /
[plain-agent](agents/plain-agent.md) / [teacher-agent](agents/teacher-agent.md)。

> 一言でいうと: **暗号化された土台に Wallet で API キーを守り、その上でエージェントを動かす。
> 安全性をプロンプトだけに頼らず、プラットフォーム(ハーネス)側の権限でも担保する。**

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
- できないこと: ツールを持たないので、データベースへのアクセス(規程の検索や採点結果の登録など)はできません。LLM が持つ一般的な知識で答えるだけです。

続けて会話したいときは**対話モード**を使います(`quit` または空行で終了。会話履歴は保持されます):

```objectscript
DEMO> do ##class(Demo.Agent.Plain).Talk()
```

---

## 4. 先生エージェントを動かす(権限で振る舞いが変わる)

**同じエージェント・同じ質問でも、呼び出す人の権限で見えるツール・取れる行動が変わる**ことを、
対話しながら確かめます。登場人物は 2 人です。

- **生徒(student01)**: 規程を**教わり**、**練習問題**を出してもらい、自分の解答を**採点**してもらい(点数+講評が学習履歴に登録される)、**成績表**を見られる。
- **設問管理者(qadmin01)**: 規程を基に**設問を作成**して教材に登録できる(登録前に**人間が承認**する)。

ツールは役割でほぼ排他です: 採点・成績(`GradeMyAnswer` / `ShowReportCard`)は生徒だけ、作問(`RegisterQuestion`)は設問管理者だけ。規程検索(`SearchPolicy`)と設問一覧(`ListPracticeQuestions`)は誰でも使えます(生徒には「出題」、設問管理者には「作問前の確認」)。

対話には `TalkAs` を使います。**入口でそのユーザとして IRIS にログインし直し**、以降の会話は
そのユーザの権限で動きます。ログインは取り消せないので、**1 セッション = 1 ロール**です。
役割ごとに IRIS セッションを開いてください(ホストのシェルから):

```bash
docker compose exec -it iris iris session iris -U DEMO
```

**4a. 生徒として対話する**

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).TalkAs("student01")
=== student01 でログインします ===
student01 のパスワード(demo): ****      ; ← 入力は伏せ字(非表示)。demo と入力して Enter
ログインしました。

============================================================
  先生エージェント (AI Hub / 情報セキュリティ・コンプライアンス研修)
  見える・使えるツールは実行ユーザのロール(RBAC)で変わります
  /trace: 直前の応答の軌跡と集計  /quit: 終了
============================================================

Provider : bedrock  (AI.LLM.bedrock)
Model    : us.anthropic.claude-sonnet-4-6
実行ユーザ: student01  (roles=Demo_Runtime,Demo_Student)
役割     : 生徒

先生>
情報セキュリティ・コンプライアンス研修の先生エージェントです。
生徒として学習をサポートします。できること:
  - 規程の解説: 「〜について教えて」→ 社内規程を検索し、出典(条番号)付きで解説します
  - 練習問題: 「問題を出して」→ 既存の練習問題から1問出題します
  - 採点: 設問への解答を書く → 点数と講評を返し、学習履歴に登録します
  - 成績表: 「成績表を見せて」→ 平均点・弱点分野をまとめて表示します
(新しい設問の作成は、設問管理者の機能です。)

あなた(student01)>
```

生徒の学びは「**教わる → 練習 → 採点 → 復習**」の一周です。次の順に話しかけてみてください:

```
あなた(student01)> 情報持ち出しについて教えてください。
あなた(student01)> 練習問題を1問出してください。
あなた(student01)> questionId=1 に「12文字以上にして、記号を混ぜて、使い回さない」と答えます。採点してください。
あなた(student01)> 成績表を見せてください。
あなた(student01)> 新しい設問を作って登録して。          ; ← 生徒の権限では作れない
あなた(student01)> /trace
あなた(student01)> /quit
```

- 確認できること:
  - **冒頭の案内が役割で変わる**: 役割(生徒 / 設問管理者)は、ログインしたユーザの権限(IRIS のリソース)からコードで決まり、ヘッダの「役割」に出ます。「いまできること」の案内もその役割の固定文で、生徒なら出題・採点・成績表、設問管理者なら作問です。
  - **教わる** → **SearchPolicy**(ベクトル検索)で規程を調べ、**出典(条番号)付き**で解説し、練習を提案します。
  - **練習** → **ListPracticeQuestions** で既存の設問から出題します(生徒は作問できないので既存問題から)。
  - **採点** → **GradeMyAnswer** が**点数・到達/未達の観点・出典**を返し、学習履歴に登録します。模範解答の全文は出しません。未達の観点は再解説して復習につなげ、成績表の表示を提案します。
  - **成績表** → **ShowReportCard** で**本人の**直近履歴から平均点・弱点分野を要約します(他人の成績は見えない)。
  - **作問を頼んでも作れない**: `RegisterQuestion` は生徒のカタログに**そもそも無い**ので、どう促しても呼べません。
- 何が起きているか:
  - **役割の判定を LLM に任せない**: LLM に渡す指示(システムプロンプト)は「共通 + その役割の分」だけです。生徒のエージェントは設問管理者向けの指示を受け取らないので、別の役割を名乗ることがありません。役割と見えるツールが一致しない場合や、どちらの役割も無い場合は、対話を始めません。
  - **見えるツールが権限で絞られる**: 認可ポリシー `RoleGuard` の `%CanList` が、権限の無いツールを LLM に渡すカタログから除外します。呼ばれても `%CanExecute` が止める二重ガードです。プロンプトのお願いではなく**土台での封じ込め**なので、プロンプトインジェクションでも呼べません。
  - **SQL 層でも守る**: 採点基準(AnswerKey)は生徒に SQL の SELECT を与えていません。採点はサーバ側で採点基準と突き合わせて点数を出すので、**生徒は採点基準を読めず、点数を自己申告することもできません**(ツール層 × SQL 層の多層防御)。

**/trace: 直前の応答の軌跡を見る**

通常は応答だけを返してクリーンに会話でき、`/trace` と入力すると直前の応答の trajectory(エージェントの実行軌跡)を表示します:

```
============================================================
  トラジェクトリ(1ランの軌跡 / Trajectory)
  Run: 7D355AB9   実行ユーザ: student01   状態: completed
  要求: questionId=1 に「12文字以上にして、記号を混ぜて、使い回さない」と答えます。採点してください。
  反復: 1/6   所要: 7.86 秒
============================================================
   1  Tool      GradeMyAnswer      [0ms]
        {"citation":"情報セキュリティ規程 第12条","comment":"100点(3/3 観点)…
── 最終回答 ────────────────────────────
  採点結果は100点です。…
=== 集計(累計)===
ツール呼び出し … 回 / トークン …
```

- 見出しの **Run(ラン ID)・実行ユーザ・状態**で「どの実行の・誰の・どう終わった軌跡か」が特定できます。同じ Run ID が永続監査(4c)にも残るので、画面の軌跡から証跡をたどれます。
- `/quit`(または空行)で終了すると、**セッション自体が閉じます**。ログインは取り消せず、デモユーザは `%Development` を持たないので `DEMO>` に戻れないためです。続けるにはセッションを開き直します。

**4b. 設問管理者として対話する(人間の承認)**

新しいセッションを開いて、設問管理者になります:

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).TalkAs("qadmin01")
qadmin01 のパスワード(demo): ****
…
あなた(qadmin01)> 既存の問題一覧を見せて。
あなた(qadmin01)> パスワード管理の規程から設問を1問作って登録して。
  (SearchPolicy → 生成 → RegisterQuestion の直前で↓)
========================================
  【承認要求】設問を教材に登録します (human-in-the-loop)
    ツール : RegisterQuestion
    カテゴリ: パスワード管理
    設問    : 安全なパスワードの管理方法を説明してください。
    模範解答: 12文字以上・記号を混在・使い回さない …
========================================
承認=y / 却下=n / 修正の指示を入力(例: もっと難しく): もっと難しい応用レベルにして
  → 差し戻します(指示を反映して作り直します)。
  (エージェントが応用レベルに作り直し → 再度 RegisterQuestion → 承認要求が再度出る)
承認=y / 却下=n / 修正の指示を入力: y
  → 承認されました。登録します。
あなた(qadmin01)> 設問1の解答を採点して。          ; ← 設問管理者の権限では採点できない
あなた(qadmin01)> /trace
```

- 確認できること:
  - **問題一覧**は作問前の**棚卸し**(重複回避・手薄な分野の把握)として使われ、生徒のように出題・採点はしません。
  - **作問** → まず SearchPolicy で規程を調べ、設問・模範解答・採点基準を**生成**して RegisterQuestion で登録を試みます。
  - **登録の直前で人間の承認**が入ります。**承認(y)/ 却下(n・空行)/ フィードバック(それ以外の入力)** の 3 択で、指示を返すと**エージェントが作り直して再提案**します(承認されるまで往復)。「AI は生成、最終決定は人間」です。
  - **採点・成績表は頼んでも使えません**(生徒のツールはカタログに無い)。
  - `/trace` では、承認の判断がツール実行の直前に `Approval` の行として出ます(承認は緑、却下・差し戻しは赤):

    ```
       1  Tool      SearchPolicy
       2  Approval  RegisterQuestion
            差し戻し: もっと難しい応用レベルにして
       3  Approval  RegisterQuestion
            承認されました
       4  Tool      RegisterQuestion   [0ms]
    ```
- 何が起きているか: 承認ゲートは `RoleGuard` の `%CanExecute` に組み込まれています。RBAC(**誰が**呼べるか)を通した**あと**で、承認(**この一件を**実行してよいか)を求める別軸の 2 段目です。差し戻しの指示は「実行拒否の理由」としてエージェントに返り、エージェントはそれを読んで作り直します。

**4c. 永続監査(誰が・何を実行し・何を判断したかが DB に残る)**

trajectory が「その会話の中で過程を追う」のに対し、**証跡をプラットフォーム側に永続化**します。
対話を終えたら、**特権セッション(通常の DEMO 入室)**で直近の監査ログを見ます:

```objectscript
DEMO> do ##class(Demo.Teacher.RunAs).ShowAudit()
=== 永続監査ログ(直近 10 件)===
  2026-09-23 04:57:05  Run:1B3AE518#4    qadmin01  ✓ RegisterQuestion  (0ms)
  2026-09-23 04:57:05  Run:1B3AE518#3    qadmin01  ✓ [approval] RegisterQuestion
  2026-09-23 04:57:01  Run:1B3AE518#2    qadmin01  ✗ [approval] RegisterQuestion
  2026-09-23 04:56:40  Run:097901ED#1   student01  ✓ GradeMyAnswer  (1ms)
  …
```

- 確認できること: `student01 → GradeMyAnswer` / `qadmin01 → RegisterQuestion` が**ログインしたユーザ名・成否・所要 ms・引数**とともに残り、承認・却下・差し戻しの判断(`[approval]`)も同じ表に残っています。
- 何が起きているか:
  - ToolSet に監査ポリシー(`%AI.Policy.Audit` 継承の `PersistentAudit`)を 1 つ付けてあり、ツールが実行されるたびに `Demo_Teacher_Audit.ToolCallLog` に 1 行残します。承認・権限拒否の判断は実行に入らないので、`RoleGuard` が同じ表に記録します。
  - `Run:1B3AE518#2` は「**どのラン(1 ターン)の何番目の事象か**」です。ランは `Demo_Teacher_Audit.RunLog` に 1 行(誰の・どの要求が・completed / failed・最終回答)残り、会話が終わった後でも SQL でその流れを再構成できます。
  - `%CanList` でカタログに無いツールは呼び出し自体が起きないので、何も残りません。監査は起きたことを正直に残します。
- やり直し: `do ##class(Demo.Teacher.RunAs).ClearAudit()`(監査ログは `Setup.Rebuild()` では消しません)。

**4d. TalkAs の仕組み**

`TalkAs` は現在のプロセスで、次の順に処理します。

1. **特権のうちに LLM キーを解決する**(Wallet のシークレットをメモリ上のプロバイダへ)。
2. **`$SYSTEM.Security.Login` でそのユーザに切り替える**(入口のパスワード入力はここで使う)。
3. **そのユーザのまま対話ループを回す**。ツールの認可・教材の SQL は、切替後のユーザのロールで判定される。

LLM への到達(Wallet シークレット)には特権が要る一方、何ができるかはユーザの権限で決まります。
「鍵の取り扱い」と「ユーザ権限」を層で分けています。

> **その他のエントリポイント**(ヘッドレス実行・比較用。詳細は [teacher-agent](agents/teacher-agent.md)):
>
> | コマンド | 用途 |
> |---|---|
> | `do ##class(Demo.Teacher.RunAs).Compare()` | ロール別に見えるツールを並べて表示 |
> | `do ##class(Demo.Teacher.RunAs).CompareActions()` | ロール別に採点・作問を実際に実行して成否を表示 |
> | `do ##class(Demo.Teacher.RunAs).RunLessonAs("student01", "…")` | 指定ユーザで1問だけ実行し、軌跡を表示(非対話なので承認は自動) |
> | `do ##class(Demo.Teacher.Teacher).RunLesson("…")` | 特権ユーザで1問だけ実行し、軌跡を表示 |
> | `do ##class(Demo.Teacher.Teacher).Talk()` | 特権ユーザのまま対話(ログインの切替なし) |

---

## 5. まとめ

```
構成要素: 軽量 IRIS(Docker) → IRISSECURITY 暗号化 → Wallet に API キー保護
  → プレインエージェント(会話するだけ)
  → 先生エージェント(生徒=採点・成績 / 設問管理者=作問。権限でツール・行動が変わる
      × 要約・生成・情報登録 × trajectory × ベクトル検索 × 永続監査 × 人間の承認)
```

キーを一度も平文で置かず、権限差はプラットフォームで担保し、過程は追え、証跡は残り、書き込みは人間が承認する。
**安全なエージェント運用の土台**を、AI Hub を使って IRIS 側で成立させられます。
ハーネスエンジニアリングを構成する要素の一部を、ここで実践しました。

---

## リセット / 後始末

```objectscript
; 教材・採点履歴を初期状態へ戻す(デモ中に採点・作問すると Progress / Question が増えるため)。
; 規程・設問・模範解答・成績表デモ用の履歴をまとめて作り直す。
DEMO> do ##class(Demo.Teacher.Setup).Rebuild()

; 永続監査ログを消去する(証跡なので Rebuild では消えない。デモをやり直すとき)
DEMO> do ##class(Demo.Teacher.RunAs).ClearAudit()

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
- **ツールを呼ばず一般論で答える**: 「〜を調べて出典付きで教えて」「questionId=1 に…と答えます。採点して」のように、**ツールを使う必然**がある頼み方にする。
- **キー貼り付けで先頭1文字が欠ける端末**: `register-key.sh` の `len=` が想定より短ければ再実行(上書き登録)。
- **構成要素の確認(手順 2)は `%SYS` セッション**で。エージェント実行(手順 3 / 4)は `DEMO` セッションで。
