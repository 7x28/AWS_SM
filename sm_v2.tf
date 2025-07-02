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
具体的な命名例と格納データ
AWSアカウントの認証情報
# パラメータ名
/aws-accounts/inf3/credentials/access-key
/aws-accounts/inf3/credentials/secret-access-key

# 値（文字列）
AKIAIOSFODNN7EXAMPLE
wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EC2インスタンスのキーペア
# パラメータ名
/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/keypair/private-key
/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/keypair/public-key

# 値（文字列）
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA...
-----END RSA PRIVATE KEY-----
EC2インスタンスのユーザー認証情報
# パラメータ名
/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/users/user1
/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/users/user2

# 値（JSON形式）
{
  "username": "admin",
  "password": "SecurePassword123"
}
RDSの認証情報
# パラメータ名
/aws-accounts/inf3/rds/mydb-instance/users/master
/aws-accounts/inf3/rds/mydb-instance/users/app

# 値（JSON形式）
{
  "username": "root",
  "password": "DbPassword456"
}
その他の秘匿情報
# パラメータ名
/aws-accounts/inf3/misc/api-keys/external-service
/aws-accounts/inf3/misc/certificates/ssl-cert

# 値（用途に応じて文字列またはJSON）
設計のポイント
1. アカウント識別子を最上位に配置

/aws-accounts/{account-id}/ を起点とすることで、アカウント単位での管理が容易
IAMポリシーでアカウント単位のアクセス制御を実装しやすい

2. リソースタイプで分類

ec2/、rds/、misc/ でリソースの種類を明確に分離
新しいリソースタイプの追加も容易

3. ユーザー情報のJSON形式保存

ユーザー名とパスワードを1つのパラメータで管理
将来的な拡張（有効期限、権限レベルなど）が容易
1回のAPI呼び出しで必要な情報を全て取得可能

4. 識別子の統一

EC2は instance-id、RDSは db-instance-id を使用
ユーザーは user1、user2 などの識別子で管理

実装例
Terraformでの使用例
hcl# EC2ユーザー情報の取得
data "aws_ssm_parameter" "ec2_user" {
  name = "/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/users/user1"
}

# JSONをデコード
locals {
  user_creds = jsondecode(data.aws_ssm_parameter.ec2_user.value)
}

# SSH接続での使用
resource "null_resource" "configure_instance" {
  connection {
    type     = "ssh"
    host     = aws_instance.example.public_ip
    user     = local.user_creds.username
    password = local.user_creds.password
  }
  
  provisioner "remote-exec" {
    inline = [
      "echo 'Connected successfully'"
    ]
  }
}
シェルスクリプトでの使用例
bash#!/bin/bash

# EC2ユーザー情報を取得
get_ec2_credentials() {
    local account_id=$1
    local instance_id=$2
    local user_id=$3
    
    CREDS=$(aws ssm get-parameter \
        --name "/aws-accounts/${account_id}/ec2/${instance_id}/users/${user_id}" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text)
    
    USERNAME=$(echo $CREDS | jq -r '.username')
    PASSWORD=$(echo $CREDS | jq -r '.password')
    
    echo "Username: $USERNAME"
    echo "Password: $PASSWORD"
}

# 使用例
get_ec2_credentials "inf3" "i-0a1b2c3d4e5f6" "user1"
AWS CLIでのアクセス例
bash# 特定アカウントのアクセスキーを取得
aws ssm get-parameter \
    --name "/aws-accounts/inf3/credentials/access-key" \
    --with-decryption

# 特定EC2インスタンスの全ユーザー情報を一覧
aws ssm get-parameters-by-path \
    --path "/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/users/" \
    --recursive \
    --with-decryption

# JSON形式のユーザー情報を取得してパース
aws ssm get-parameter \
    --name "/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/users/user1" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text | jq '.'
パラメータ作成例
bash# EC2ユーザー情報の登録
aws ssm put-parameter \
    --name "/aws-accounts/inf3/ec2/i-0a1b2c3d4e5f6/users/user1" \
    --value '{"username": "admin", "password": "SecurePassword123"}' \
    --type "SecureString" \
    --overwrite

# RDSユーザー情報の登録
aws ssm put-parameter \
    --name "/aws-accounts/inf3/rds/mydb-instance/users/master" \
    --value '{"username": "root", "password": "DbPassword456"}' \
    --type "SecureString" \
    --overwrite
セキュリティ推奨事項

暗号化: すべてのパラメータをSecureString型で保存
IAMポリシー: 最小権限の原則に基づいたアクセス制御
json{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["ssm:GetParameter", "ssm:GetParametersByPath"],
    "Resource": "arn:aws:ssm:*:*:parameter/aws-accounts/inf3/*"
  }]
}

監査: CloudTrailでパラメータへのアクセスを記録
タグ付け: 環境や用途別のタグを追加して管理を容易に

この構造により、直感的で管理しやすく、プログラムからも利用しやすいParameter Store設計が実現できます。
