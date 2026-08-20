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
CODEBUILD_ROLE=codebuild-shared-runner-role-01
S3_BUCKET=example-deploy-artifacts
S3_PREFIX=example-app/test
SSM_DOCUMENT=AD2-AutoDeploy
SERVICE=octane@example-app-test.service
OCTANE_INSTANCE=example-app-test
LOCAL_PORT=8001
LOCAL_HEALTH_URL=http://127.0.0.1:8001/up
EXTERNAL_HEALTH_URL=https://test.example.com/up
PHP_VERSION=8.4
```

Keep the same values across AWS, GitLab and the server.

## 2. Validate the prepared infrastructure

Before CI/CD work:

- EC2 is running and reachable through your normal administration method.
- EC2 can reach required database/service endpoints.
- Nginx and systemd are available.
- The application can run with the chosen PHP/runtime version.
- The DNS/load-balancer path is known or can be configured later.

Do not make databases public for deployment convenience.

## 3. Create the AWS deployment plane

Complete [AWS setup](aws.md):

1. Create a private S3 artifact bucket.
2. Attach `AmazonSSMManagedInstanceCore` to the EC2 instance role.
3. Give the EC2 role read-only access to the deployment S3 prefix.
4. Confirm the instance appears as an SSM managed node.
5. Create a CodeBuild **Runner project** connected to the GitLab repository.
6. Create/reuse an appropriate CodeBuild service role. Use a shared role when the projects belong to the same trust boundary.
7. Give the CodeBuild role write/read access to the required S3 prefix(es).
8. Create the reusable `AD2-AutoDeploy` SSM Command document.
9. Give the CodeBuild role permission to invoke that document on the intended instance and read command results.

For existing CodeBuild projects, migrate one non-production runner to the shared role first, run a real build/deploy test, then move other runners and remove unused old roles/policies.

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
chmod 600 .env

find . -maxdepth 2 -type f -name '*.sh' -exec bash -n {} \;
```

Configure `auto.deploy/.env` using [Configuration reference](configuration.md) and [`examples/auto-deploy.env.example`](examples/auto-deploy.env.example).

Do not commit the server `.env`.

## 6. Install the reusable Octane service

Install:

- [`examples/octane@.service`](examples/octane@.service)
- [`examples/octane-runner`](examples/octane-runner)
- [`examples/octane-example-app-test.env`](examples/octane-example-app-test.env)

```bash
sudo install -m 755 docs/examples/octane-runner /usr/local/bin/octane-runner
sudo install -m 644 docs/examples/octane@.service /etc/systemd/system/octane@.service
sudo mkdir -p /etc/octane
sudo install -m 600 docs/examples/octane-example-app-test.env /etc/octane/example-app-test.env

sudo touch /datastore/web/test.example.com/server.logs/octane.log
sudo chown www-data:www-data /datastore/web/test.example.com/server.logs/octane.log

sudo systemctl daemon-reload
sudo systemd-analyze verify /etc/systemd/system/octane@.service
sudo systemctl enable octane@example-app-test.service
```

The service does not need to be started before the first release exists.

Set:

```text
SERVICE=octane@example-app-test.service
```

in `auto.deploy/.env`.

## 7. Configure Nginx and proxy trust

Install [`examples/nginx-test.example.com.conf`](examples/nginx-test.example.com.conf), validate and reload Nginx.

When HTTPS terminates at AWS ALB, configure Laravel's trusted proxies in `bootstrap/app.php`:

```php
use Illuminate\Http\Request;

$middleware->trustProxies(
    at: '*',
    headers: Request::HEADER_X_FORWARDED_AWS_ELB,
);
```

This allows Laravel to preserve the original public HTTPS scheme when Nginx/Octane receive HTTP from the load balancer path.

## 8. Configure GitLab variables

Create application secrets in **Settings -> CI/CD -> Variables** and scope them to the intended environment.

At minimum for a Laravel example:

```text
APP_ENV=test
APP_DEBUG=false
APP_URL=https://test.example.com
APP_KEY=<secret>
DB_HOST=<database-endpoint>
DB_DATABASE=<database-name>
DB_USERNAME=<secret-or-config>
DB_PASSWORD=<secret>
```

Add all application-specific API credentials explicitly. Sensitive values belong in GitLab variables, not in `.gitlab-ci.yml`.

See [GitLab CI/CD](gitlab.md).

## 9. Add the pipeline

Use [`examples/gitlab-ci.yml`](examples/gitlab-ci.yml) as the starting point and update its deployment coordinates.

The example selects PHP 8.4 explicitly. Do not rely on the CodeBuild image's default PHP version.

## 10. Commission the first deployment safely

For the first run, make the deploy job manual if desired. Push a commit to `test` and confirm the build job uploads:

```text
s3://example-deploy-artifacts/example-app/test/<sha>/release.tar.gz
s3://example-deploy-artifacts/example-app/test/<sha>/.env
```

Before enabling unattended deployment, test the generic SSM document manually:

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

Required result:

```text
Status: Success
ResponseCode: 0
Deployment SUCCEEDED
```

## 11. Verify the deployed system

On EC2:

```bash
readlink -f /datastore/web/test.example.com/htdocs
systemctl --no-pager --full status octane@example-app-test.service
ss -lntp | grep ':8001'
curl -fsS http://127.0.0.1:8001/up
tail -30 /datastore/web/test.example.com/server.logs/octane.log
```

Externally:

```bash
curl -fsS https://test.example.com/up
```

If the application generates absolute URLs, verify they use HTTPS behind the load balancer.

Repeat the same SSM command with the already-active SHA. It should exit successfully with `Commit already deployed` and must not repeat migrations, seeders or restart the service.

## 12. Enable application-specific lifecycle options

Example Laravel settings:

```text
LARAVEL_PERSIST_STORAGE=Y
LARAVEL_MIGRATE=Y
LARAVEL_SEED=N
LARAVEL_FILAMENT_ASSETS=N
LARAVEL_CONFIG_CACHE=Y
LARAVEL_ROUTE_CACHE=N
```

Enable `LARAVEL_SEED=Y` only after the application team confirms the default seeder is safe and idempotent on every deployment.

Enable `LARAVEL_FILAMENT_ASSETS=Y` for applications that require Filament asset publication.

## 13. Enable automatic deployment

After commissioning succeeds:

1. remove any temporary manual deployment gate;
2. push another harmless application change;
3. confirm build and deploy both succeed;
4. confirm local and external health checks succeed;
5. confirm the systemd template instance is restarted by `ad2-gitlab`.

The installation is complete when all [acceptance checks](operations.md#acceptance-checklist) pass.
