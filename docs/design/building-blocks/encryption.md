# 設計: 手順2 IRISSECURITY 暗号化

## ねらい

`IRISSECURITY` データベースを暗号化し、そこに格納される認証情報・**Wallet のシークレット(手順3の API キー)を保存時(at-rest)で保護**する。手順3で Wallet に入れる API キーが暗号化される前提を作る。

> **注意**: 参照元(`ai-hub-dev-template` / `aihub-demo`)には IRISSECURITY / DB 暗号化の実装は**存在しない**。本手順は IRIS 標準の暗号化 API に基づく**新規設計**であり、実機ドキュメント(`iris-agentic-dev tool iris_doc`)と実機挙動で裏付けたものである。

## 採用した機構(実機で確認済み)

`%SYSTEM.Encryption` の **無人起動時アクティベーション**専用 API を使う:

| API | 役割 |
|---|---|
| `CreateAutoEncryptionKeyOnly(file, bitlength, Desc, .Username, .Password)` | 「無人起動時アクティベーション専用」の Auto キーを生成。**username/password は IRIS が自動生成して返す**(=解錠資格情報を人が管理せず、`.env` にも置かない) |
| `ActivateAutoEncryptionKey(file, Username, Password, iristemp, journal, audit, irissecurity=1)` | キーを起動時アクティベーションとして構成。`irissecurity=1` で IRISSECURITY を暗号化対象にする |
| `SYS.Database` の `EncryptedDB` / `EncryptionKeyID` | 暗号化状態の検証に使用 |

### 重要な挙動:暗号化には1回の再起動が必要

`ActivateAutoEncryptionKey(...,irissecurity=1)` を呼んだ**直後は `EncryptedDB=0` のまま**である。IRISSECURITY は稼働中マウント済みのため、その場では暗号化できない。**次回起動の初期段階(mount 前)にキーがアクティベートされ、IRISSECURITY が暗号化される**(messages.log に `Encrypting IRISSECURITY database with key ...`)。

→ 「稼働中のセキュリティ DB は生きたまま暗号化できない」という制約そのものが、記事の教材になる。本デモでは first-boot 内で**制御された `iris stop`/`iris start` を1回だけ**行い、**単一の `docker compose up` で暗号化完了まで到達**させる。

## 主要な設計判断

| 論点 | 採用 | 理由 |
|---|---|---|
| 実行タイミング | 初回起動(first-boot) | 暗号化は Durable %SYS(実行時マウント)に対して行う必要があり、ビルド時は durable 未初期化。参照リポジトリ `aihub-demo` の `start.sh`+`first-boot.sh` idiom を踏襲 |
| 起動機構 | `entrypoint: docker/start.sh` → IRIS 起動待ち → `docker/first-boot-encrypt.sh` → 前景で `exec /tini -- /iris-main "$@"` | ベース image の既定 ENTRYPOINT が `/tini -- /iris-main` のため、**tini を保持**して PID1 のシグナル処理・ゾンビ回収を維持 |
| キー方式 | Auto キー(`CreateAutoEncryptionKeyOnly`) | IRIS が解錠資格情報を生成・内部保存 → **暗号化パスワードを `.env` に置かず無人起動**できる |
| 暗号化対象 | **IRISSECURITY のみ**(`irissecurity=1`、他は 0) | 目的(Wallet シークレット保護)に対する最小構成。journal/audit/iristemp も個別に暗号化可能だが本デモでは対象外 |
| 冪等性 | センチネル `/durable/.demo-irissecurity-encrypted` | 2回目以降の起動では再実行しない |
| 安全ガード | 冒頭で `EncryptedDB` を確認し、**既に暗号化済みなら鍵に一切触れずセンチネルのみ作成** | センチネル欠落状態での鍵再生成は、既存の暗号化 IRISSECURITY を復号不能にして**起動不能**を招くため(landmine 回避) |

## デモとしての簡易的措置 と 本番運用

本デモは無人起動を優先して以下を簡易的措置にしている:

1. **鍵ファイルをデータと同じ永続ボリューム(`/durable`)に置く**
2. **解錠資格情報を IRIS インスタンス内部に保存**(Auto キー)

本番でこれが問題なのは、**ボリューム(またはインスタンス)を丸ごと奪われると暗号文と復号手段が同居**してしまい、at-rest 暗号化の意味が薄れるため。「鍵は守る対象と別に保管する」が原則。

本 IRIS で選べる本番向けの鍵管理(実機で存在を確認):

| 方式 | 概要 | 無人起動 | 向き |
|---|---|---|---|
| **KMIP サーバ**(`Security.KMIPServer`) | 鍵を KMIP 準拠の外部鍵管理サーバが保持。起動時に TLS 認証経由で取得。鍵はデータと同居しない | ○ | 本番の第一候補 |
| **クラウド KMS**(`%SYSTEM.Encryption.KMSCreateEncryptionKey`、`Server`/`Region` 指定) | DB 鍵を AWS KMS / Azure Key Vault / GCP KMS の鍵でラップ。解錠権限は IAM で管理 | ○ | クラウド運用 |
| **対話的な起動時アクティベーション** | 起動のたびに運用者が鍵管理者パスワードを入力 | ✕ | 鍵秘匿は最強だが自動再起動・オートスケール不可 |
| **分離したローカル鍵ファイル** | 鍵をデータと別ストレージに置き OS 権限を厳格化。資格情報はシークレットマネージャから注入 | △ | オンプレ簡易構成 |

併せて本番では、**職務分掌**(暗号化キー管理者とシステム管理者の分離)、**鍵ローテーション/再暗号化**、**鍵操作の監査**、**鍵の安全な別媒体バックアップ**が必須。

移行イメージ:本番では first-boot の「Auto キー生成+内部保存」を、**起動時に KMIP/KMS 参照経由で鍵をアクティベートする構成**に置き換える。暗号化対象 DB や活性化の流れは同じで、**鍵の出所だけが「同居ファイル」→「外部鍵管理」に変わる**。
