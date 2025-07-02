推奨階層構造
/aws-accounts/{account-id}/
├── credentials/
│   ├── access-key
│   └── secret-access-key
├── ec2/
│   └── {instance-id}/
│       ├── keypair/
│       │   ├── private-key
│       │   └── public-key
│       └── users/
│           └── {user-identifier}  # JSON形式で保存
├── rds/
│   └── {db-instance-id}/
│       └── users/
│           └── {user-identifier}  # JSON形式で保存
└── misc/
    └── {category}/
        └── {item-name}



具体的な命名例
# AWSアカウントの認証情報
/aws-accounts/inf3/credentials/access-key
/aws-accounts/inf3/credentials/secret-access-key

# EC2インスタンスのキーペア
/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/keypair/private-key
/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/keypair/public-key

# EC2インスタンスのユーザー認証情報
/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/users/admin/password
/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/users/developer1/password

# RDSの認証情報
/aws-accounts/inf3/rds/mydb-instance/users/root/password
/aws-accounts/inf3/rds/mydb-instance/users/app_user/password

# その他の秘匿情報
/aws-accounts/inf3/misc/api-keys/external-service-key
/aws-accounts/inf3/misc/certificates/ssl-cert


設計のポイント
1. アカウント識別子を最上位に配置

/aws-accounts/{account-id}/ を起点とすることで、アカウント単位での管理が容易
権限制御もアカウント単位で設定しやすい

2. リソースタイプで分類

ec2/、rds/、misc/ でリソースの種類を明確に分離
新しいリソースタイプの追加も容易

3. インスタンス識別子の使用

EC2は instance-id、RDSは db-instance-id を使用
AWSの標準的な識別子を使うことで一意性を確保

4. 用途別のサブパス

credentials/：アカウントレベルの認証情報
keypair/：SSH接続用の鍵
users/：ユーザー認証情報
misc/：その他の柔軟な秘匿情報

