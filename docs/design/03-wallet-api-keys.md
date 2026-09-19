# 設計: 手順3 Wallet + ConfigStore で API キー受け渡し

## ねらい

OpenAI / Claude(Anthropic)の API キーを IRIS の **Secure Wallet** に格納し、アプリからは
**ConfigStore の `secret://` 参照 → `@{config:...}`** だけで扱う。Wallet の実体は
`IRISSECURITY` データベースの `^WALLET` グローバルのため、**手順2で暗号化済み → キーは
at-rest で保護される**。この依存関係(手順3は手順2の上にしか成立しない)が本デモの核心。

> **Secure Wallet について**: IRIS 2025.3 で導入、2026.1(EM)で一般提供された比較的新しい機能。
> ソースへのパスワードべた書きや平文ファイル/グローバル退避に代わり、機密情報を IRIS 上の
> **RBAC で保護されたセキュリティ DB** に格納し、名前で取り出す仕組み。

## 登録方式 = 手動のみ(キーを環境変数に出さない)

API キーは **`.env` にも環境変数にも置かない**。対話ヘルパ `docker/register-key.sh` を
**手動で1回実行**して Wallet に登録する方式を採用した。

> **なぜ .env / 環境変数を使わないか**: `env_file` や `environment` でキーを渡すと、
> `docker inspect` やコンテナ内 `/proc/<pid>/environ`、`ps` から平文が読める。
> first-boot での自動登録も「.env にキーを置く」前提になるため、本デモでは採らない。

ヘルパのキー注入経路(平文をどこにも残さないための設計):

| 経路 | 手段 | 平文が残らない理由 |
|---|---|---|
| 入力 | `read -s`(非表示) | シェル履歴・画面に出ない |
| bash → IRIS | 0600 の一時ファイル + `%Stream.FileCharacter` で読取 | **argv・環境変数に出ない**(env で渡すのはファイルパスと非機密パラメータのみ) |
| 後始末 | 登録後に一時ファイルを即 `rm` | コンテナ `/tmp` に一瞬だけ |

> **設計上の制約(この build 固有)**: `iris session IRIS -U %SYS "<code>"` は引数を**ルーチン名**として
> 扱うため(`<NOROUTINE>`)、「コードを argv、キーを stdin にパイプ」は不成立。heredoc は
> stdin を占有するため `read` とも両立しない。よって**一時ファイル経由**でキーを渡す設計にした。

## 採用した構成 = 正準(canonical)パターン(実機で全チェーン確認済み)

「Wallet(機密の実体)+ ConfigStore(参照だけ)+ Agent(名前参照)」の3層。

| 層 | 実体 | 役割 |
|---|---|---|
| RBAC リソース | `Security.Resources`(`DemoWalletUse` / `DemoWalletEdit`) | コレクション作成に Use/Edit 指定は**必須**。ただし **KeyValue 型では実際には使われない**(下記参照) |
| Wallet コレクション | `%Wallet.Collection`(`AISecrets`) | シークレットの束 |
| Wallet シークレット | `%Wallet.KeyValue`(`AISecrets.OpenAI` / `AISecrets.Anthropic` / `AISecrets.Bedrock`) | API キー/トークンの実値。**オブジェクトで格納** `{"Secret":{"key":"..."}}`。列挙不可、`GetSecretValue` で取得 |
| ConfigStore 設定 | `%ConfigStore.Configuration`(`AI.LLM.openai` / `AI.LLM.anthropic` / `AI.LLM.bedrock`) | `model_provider` / `model` と **`api_key":"secret://AISecrets.OpenAI#key"`(参照だけ)** を保持。平文を持たない。Bedrock は非機密の `region` も同梱 |
| 解決 | `%AI.Utils.SettingStore`(`Expand`) | `@{config:AI.LLM.openai}` → ConfigStore 展開 → `secret://` 解決 → 平文キー入り config。`%AI.Agent.%Init()` が `RegisterDefaults()` を呼ぶ |

### 読み取りの本当の関門は `%Admin_Wallet` リソース

`%Wallet.KeyValue.GetSecretValue(...)` はコレクションの Use/Edit リソースではなく、
**`%Admin_Wallet` リソース**(= `%Manager` ロール等が保持)で保護される。持たないユーザが
呼ぶと「アクセスが拒否されました」。本番アプリでは `$ROLES` に `%Manager` を一時付与して
取得し、直後に戻す、といった最小権限の運用になる。

> 本デモでは操作を `_SYSTEM`(`%All`)/ 起動時 `%SYS` で行うため `%Admin_Wallet` を保持しており、
> 追加の権限付与なしに動作する。手順4のエージェントも同様。

## secret:// 解決の流れ(実機確認)

```
Agent Parameter PROVIDERCONFIG = "@{config:AI.LLM.openai}"
  → SettingStore.Expand         : @{config:AI.LLM.openai} を ConfigStore 設定に展開
  → ConfigStore 設定             : {"model_provider":"openai","model":"gpt-5.6",
                                    "api_key":"secret://AISecrets.OpenAI#key"}
  → secret:// 解決               : Wallet の AISecrets.OpenAI の "key" フィールドを取得
  → 最終 config                  : {"model_provider":"openai","model":"gpt-5.6",
                                    "api_key":"sk-..."}(ここで初めて平文)
  → %AI.Provider.Create(...)
```

平文が現れるのは **Provider 生成の直前・メモリ上だけ**。ソース・設定・ログには参照しか残らない。

## 主要な設計判断

| 論点 | 採用 | 理由 |
|---|---|---|
| 登録タイミング | **手動**(`docker/register-key.sh` を必要時に実行)。暗号化の**後** | キーを .env / 環境変数に出さないため自動化しない。暗号化済み IRISSECURITY に書くので格納の瞬間から at-rest 保護 |
| 冪等性 | 土台(リソース/コレクション)は「無ければ作る」、シークレットは**上書き**(削除→再作成) | 再実行でキー差し替えが可能。土台は壊さない |
| Secret の形 | オブジェクト `{"key":"..."}` | ConfigStore から `secret://...#key` でフィールド参照するため |
| 設定の間接参照 | ConfigStore は `secret://` 参照だけ | 平文を設定・ソースに置かない(本手順の主目的) |
| キー名 | `AISecrets.<Name>`、config `AI.LLM.<provider>`(openai / anthropic / bedrock) | 手順4のプロバイダと 1:1。`Base.%OnInit()` が `AI.LLM.*` を優先順に探して採用 |
| モデル | ヘルパ第2引数(既定 `gpt-5.6` / `claude-sonnet-5` / `us.anthropic.claude-sonnet-5`) | プロバイダの現行モデル ID に合わせて指定可能。ID は変わりやすいので登録時に確認 |
| Bedrock 認証 | bearer token を Wallet、`region` は非機密として ConfigStore に平文 | Bedrock は API キーでなく bearer token 認証。リージョンは秘密でない。model はクロスリージョン推論プロファイル ID(`us.` 等の接頭辞)が必要 |

## デモとしての簡易的措置 と 本番運用

| 簡易的措置 | 内容 | 本番向け |
|---|---|---|
| キーの供給元 | 人が対話で手入力(非表示)→ 0600 一時ファイル経由で登録 | シークレットマネージャ / KMS / CI のシークレット注入から、アプリ起動時に Wallet へ投入 |
| ConfigStore 検証 | `validateDetails=0`(`AI.LLM` の descriptor 登録を省略) | `%ConfigStore.DescriptorManager` で descriptor を登録し `validateDetails=1` で設定形を検証 |
| Wallet の RBAC | Use/Edit リソースは作るが KeyValue 型では未使用。読み取りは `%All`/`%Manager` で通す | 専用ロールに `%Admin_Wallet` を最小付与し、アプリは一時昇格で取得 |

いずれの場合も **Wallet の実体が暗号化 IRISSECURITY にある**(手順2)保護の土台は共通で、
変わるのは「キーの出所」「設定検証の厳密さ」「権限の粒度」である。

## 手順2との接続

`%Wallet.KeyValue` は `IRISSECURITY` の `^WALLET` グローバルにシークレットを保存する。したがって
手順2で `IRISSECURITY.EncryptedDB=1` にしてある限り、Wallet に入れた API キーは**ディスク上で
暗号化**される。手順3は手順2の上にしか成立しない。
