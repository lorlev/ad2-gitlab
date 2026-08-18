# Installation

This is the recommended end-to-end commissioning sequence. Detailed implementation notes are linked from each phase.

## 1. Define deployment values

Choose all names before creating resources:

```text
AWS_REGION=eu-central-1
AWS_ACCOUNT_ID=<account-id>
PROJECT=example-app
ENVIRONMENT=TEST
GIT_BRANCH=test
HOST=test.example.com
SERVER_ROOT=/datastore/web/test.example.com
AUTO_DEPLOY_DIR=/datastore/web/test.example.com/auto.deploy
INSTANCE_ID=i-0123456789abcdef0
CODEBUILD_PROJECT=example-app-runner
S3_BUCKET=example-deploy-artifacts
S3_PREFIX=example-app/test
SSM_DOCUMENT=AD2-AutoDeploy
SERVICE=example-app-test.service
LOCAL_PORT=8001
LOCAL_HEALTH_URL=http://127.0.0.1:8001/up
EXTERNAL_HEALTH_URL=https://test.example.com/up
DB_DATABASE=example_test
PHP_VERSION=8.4
```

Keep the same values across AWS, GitLab and the server.

## 2. Validate the prepared infrastructure

Before CI/CD work:

- EC2 is running and reachable through your normal administration method.
- EC2 can reach the RDS endpoint and database port.
- RDS accepts the intended database user from the EC2 security group.
- Nginx and systemd are available.
- The application can run with the chosen PHP/runtime version.
- The DNS/load-balancer path is known or can be configured later.

For MySQL connectivity:

```bash
nc -vz <rds-endpoint> 3306
```

Do not make RDS public for deployment convenience.

## 3. Create the AWS deployment plane

Complete [AWS setup](aws.md):

1. Create a private S3 artifact bucket.
2. Attach `AmazonSSMManagedInstanceCore` to the EC2 instance role.
3. Give the EC2 role read-only access to the deployment S3 prefix.
4. Confirm the instance appears as an SSM managed node.
5. Create a CodeBuild **Runner project** connected to the GitLab repository.
6. Give the CodeBuild service role write/read access to the S3 prefix.
7. Create the reusable `AD2-AutoDeploy` SSM Command document.
8. Give the CodeBuild role permission to invoke that document on the intended instance and read command results.

## 4. Prepare the application runtime on EC2

Follow [Server setup](server.md).

For the Laravel/PHP example verify:

```bash
php -v
php -m | grep -i '^swoole$'
aws --version
git --version
curl --version
tar --version
nginx -v
```

The example uses PHP 8.4. PHP 8.4+ is supported by the framework when the selected version is compatible with the application and exists in both CI and EC2.

## 5. Install `ad2-gitlab`

```bash
ROOT="/datastore/web/test.example.com"

mkdir -p \
  "$ROOT/builds" \
  "$ROOT/static" \
  "$ROOT/server.logs"

git clone \
  https://github.com/lorlev/ad2-gitlab.git \
  "$ROOT/auto.deploy"

cd "$ROOT/auto.deploy"
cp .env.example .env
chmod 750 deploy.sh
chmod 600 .env

find . -maxdepth 2 -type f -name '*.sh' -exec bash -n {} \;
```

Configure `auto.deploy/.env` using [Configuration reference](configuration.md) and [`examples/auto-deploy.env.example`](examples/auto-deploy.env.example).

Do not commit the server `.env`.

## 6. Create the application service and proxy

Install the systemd unit and Nginx virtual host from [Server setup](server.md). Example files:

- [`examples/example-app-test.service`](examples/example-app-test.service)
- [`examples/nginx-test.example.com.conf`](examples/nginx-test.example.com.conf)

The service may be stopped or failing before the first release because `htdocs` does not exist yet. That is expected during initial commissioning.

## 7. Configure GitLab variables

Create application secrets in **Settings → CI/CD → Variables** and scope them to `test` when environment scoping is available.

At minimum for the Laravel example:

```text
APP_ENV=test
APP_DEBUG=false
APP_URL=https://test.example.com
APP_KEY=<secret>
DB_HOST=<rds-endpoint>
DB_DATABASE=example_test
DB_USERNAME=<secret-or-config>
DB_PASSWORD=<secret>
```

Add all application-specific API credentials explicitly. Sensitive values belong in GitLab variables, not in `.gitlab-ci.yml`.

See [GitLab CI/CD](gitlab.md).

## 8. Add the pipeline

Use [`examples/gitlab-ci.yml`](examples/gitlab-ci.yml) as the starting point. Update the configuration block at the top:

```yaml
variables:
  AWS_REGION: "eu-central-1"
  DEPLOY_SSM_DOCUMENT: "AD2-AutoDeploy"
  DEPLOY_INSTANCE_ID: "i-0123456789abcdef0"
  DEPLOY_AUTO_DIR: "/datastore/web/test.example.com/auto.deploy"
  DEPLOY_S3_BUCKET: "example-deploy-artifacts"
  DEPLOY_S3_PREFIX: "example-app/test"
  DEPLOY_EXTERNAL_HEALTH_URL: "https://test.example.com/up"
```

Update the runner tag to match the CodeBuild project:

```text
codebuild-example-app-runner-$CI_PROJECT_ID-$CI_PIPELINE_IID-$CI_JOB_NAME
```

The provided example selects PHP 8.4 with CodeBuild's installed PHP runtime. For another PHP 8.4+ version, adjust the selection line and ensure the server uses the same major/minor.

## 9. Commission the first deployment safely

For the first run, set the deploy job to manual:

```yaml
when: manual
```

Push a commit to `test`. Confirm the build job uploads:

```text
s3://example-deploy-artifacts/example-app/test/<sha>/release.tar.gz
s3://example-deploy-artifacts/example-app/test/<sha>/.env
```

Before clicking the GitLab deploy job, test the generic SSM document manually:

```bash
aws ssm send-command \
  --instance-ids "i-0123456789abcdef0" \
  --document-name "AD2-AutoDeploy" \
  --parameters \
    'AutoDeployDir=["/datastore/web/test.example.com/auto.deploy"],CommitSha=["<40-char-sha>"]' \
  --region eu-central-1 \
  --query 'Command.CommandId' \
  --output text
```

Then inspect the result:

```bash
aws ssm get-command-invocation \
  --command-id "<command-id>" \
  --instance-id "i-0123456789abcdef0" \
  --region eu-central-1 \
  --query '{Status:Status,ResponseCode:ResponseCode,Output:StandardOutputContent,Error:StandardErrorContent}' \
  --output json
```

Required result:

```text
Status: Success
ResponseCode: 0
Deployment SUCCEEDED
```

## 10. Verify the deployed system

On EC2:

```bash
readlink -f /datastore/web/test.example.com/htdocs
systemctl --no-pager --full status example-app-test.service
curl -fsS http://127.0.0.1:8001/up
```

Externally:

```bash
curl -fsS https://test.example.com/up
```

Repeat the same SSM command with the already-active SHA. It should exit successfully with `Commit already deployed` and must not repeat migrations or restart the service.

## 11. Enable automatic deployment

After the commissioning run succeeds:

1. remove `when: manual` from the deploy job;
2. commit the change to `test`;
3. push another harmless application change;
4. confirm `build-test-release` and `deploy-test` both succeed;
5. confirm the external health check succeeds.

The installation is complete when all [acceptance checks](operations.md#acceptance-checklist) pass.
