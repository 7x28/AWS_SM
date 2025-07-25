# Github Enterprise & AWS SSM パラメータストア 運用設計書

## 1. 概要

本運用設計書は、Github EnterpriseにおけるSecrets管理およびAWS Systems Manager Parameter Store（以下SSM）を利用した機密情報管理に関する定常的および例外的な運用フローを規定することを目的とする。

## 2. 運用対象

- Github Enterprise オーガナイゼーション Secrets
  - SSH秘密鍵（pem形式）
- AWS SSM パラメータストア
  - EC2接続用ID/PW
  - EC2の秘密鍵（pem）および公開鍵（pub）
  - RDS接続用ID/PW
  - その他アプリケーションで使用される機密情報

## 3. 権限

| 運用対象 | 権限保有者 |
|----------|------------|
| Github Secretsの登録・削除 | オーガナイゼーションのAdmin以上 |
| SSM パラメータストアの登録・削除 | チームメンバー全員（IAMポリシーに基づく） |

## 4. 運用フロー

### 4.1 登録時の運用

#### Github Secrets 登録手順（SSH秘密鍵）

1. Admin権限を持つユーザーがオーガナイゼーションのSettings > Secrets > Actions にアクセス。
2. 対象リポジトリまたはオーガナイゼーション全体に対して、以下を追加：
   - `PRIVATE_SSH_KEY`：pem形式の秘密鍵
3. 必要に応じて、Secretsが参照されるCI/CDのワークフローの実行確認を行う。

#### SSM パラメータストア 登録手順

1. AWS マネジメントコンソールまたはAWS CLIから、以下を`SecureString`として登録：
   - `/env/ec2/<host>/id`
   - `/env/ec2/<host>/password`
   - `/env/ec2/<host>/pem`
   - `/env/ec2/<host>/pub`
   - `/env/rds/<instance>/username`
   - `/env/rds/<instance>/password`
   - `/env/app/secret/<用途>`
2. IAM Roleにより必要最小限のアクセス制御を設定。
3. バージョニング設定を有効にし、変更履歴を確認可能とする。

### 4.2 削除時の運用

#### Github Secrets 削除

- 対象リポジトリまたはオーガナイゼーション全体から該当Secretsを削除。
- 削除理由と日時を運用ログに記録。

#### SSM パラメータストア 削除

- 以下のいずれかの条件を満たした場合に削除を行う：
  - 該当EC2/RDSが廃止された場合
  - 秘密情報の用途が完全に廃止された場合
- AWS CLIまたはマネジメントコンソールにて削除実施。
- 削除ログを記録し、必要に応じてCodeCommitやWiki等に記録。

### 4.3 年次棚卸し（メンテナンス）

- 年に1回、以下の作業を実施：

#### Github Secrets 棚卸し

- 現在登録されているSecretsの一覧を取得。
- 利用実績のないまたは参照されていないSecretsを棚卸候補として抽出。
- チーム内レビュー後に不要なSecretsを削除。

#### SSM パラメータストア 棚卸し

- AWS Config またはカスタムスクリプトにより未使用のパラメータを抽出。
- 作成日や最終更新日が古いものに対して棚卸候補フラグを設定。
- 対象情報の利用可否をチームで確認し、不要なものは削除。

## 5. ログ・記録管理

- 登録・削除・棚卸し作業はすべてログとして残すこと。
  - GitHub Enterprise: WikiまたはIssuesに記録。
  - AWS: CloudTrail、運用用のCodeCommitなどに記録。

## 6. セキュリティ考慮事項

- SecretsおよびSSMのパラメータは必ず暗号化（SecureString, GPGなど）で保存。
- 閲覧・登録可能な権限を最小限に制限。
- 万が一の漏洩に備え、鍵情報は定期的にローテーションを実施。
  - 推奨：半年に一度のローテーション

## 7. 運用改善ポイント（将来的検討）

- TerraformやAWS CDK等によるSecrets/SSMのコード管理化
- 自動棚卸しスクリプトの導入（スケジュール実行）
- 秘密情報のタグ管理（用途・期限・責任者）

---

