# Troubleshooting

## CodeBuild runner job does not start

Check that the GitLab job tag exactly matches the CodeBuild runner project:

```text
codebuild-example-app-runner-$CI_PROJECT_ID-$CI_PIPELINE_IID-$CI_JOB_NAME
```

## `hostname: command not found` in the runner startup log

Some CodeBuild runner images can emit this during runner environment preparation. If the GitLab shell executor proceeds and the job succeeds, this warning is not a deployment failure.

Investigate only if your job itself requires `hostname`.

## Wrong PHP version in CodeBuild

Do not rely on the image's default runtime. Explicitly select and verify the required version before Composer:

```bash
phpenv global "$PHP_84_VERSION"
hash -r
php -v
```

Keep CI and EC2 on the same PHP major/minor.

## Composer says the lock file is out of date

Fix the lock file in development and commit it. Do not solve this with `composer update` inside CI.

## S3 upload fails with `AccessDenied`

Check the **CodeBuild service role**, not the EC2 role.

It needs the S3 actions required by the pipeline for the configured bucket/prefix. If multiple runner projects use a shared role, verify that the shared role contains the deployment permissions and that the project actually references that role.

Confirm the caller when necessary:

```bash
aws sts get-caller-identity
```

For a shared role, the returned ARN should contain:

```text
assumed-role/codebuild-shared-runner-role/
```

## EC2 cannot download release artifacts

Check:

```bash
aws sts get-caller-identity
aws s3 cp s3://example-deploy-artifacts/example-app/test/<sha>/release.tar.gz /tmp/release.tar.gz
```

Verify the EC2 instance role has `s3:GetObject` on the correct prefix and outbound connectivity to S3.

## SSM `send-command` is denied in GitLab

Check the CodeBuild role policy includes both:

```text
arn:aws:ssm:<region>:<account-id>:document/AD2-AutoDeploy
arn:aws:ec2:<region>:<account-id>:instance/<instance-id>
```

Do not accidentally edit the EC2 instance role when the denied caller is CodeBuild.

## Old CodeBuild roles are deleted but generated policies remain

CodeBuild-created customer-managed policies can remain after an old service role is removed.

List likely policies and attachment counts:

```bash
aws iam list-policies \
  --scope Local \
  --query "Policies[?contains(PolicyName, 'runner')].[PolicyName,Arn,AttachmentCount]" \
  --output table
```

Before deletion, confirm there are no attached identities:

```bash
aws iam list-entities-for-policy --policy-arn <policy-arn>
```

Delete only policies that are no longer used.

## `AD2-AutoDeploy` is `Creating`

Wait until the document is active:

```bash
aws ssm describe-document \
  --name AD2-AutoDeploy \
  --region eu-central-1 \
  --query 'Document.Status' \
  --output text
```

Expected:

```text
Active
```

## SSM parameter validation fails

Check:

- commit is the full 40-character lowercase SHA;
- deployment directory matches `/datastore/web/<host>/auto.deploy`;
- the path contains only characters allowed by the document pattern.

Do not weaken the SSM input pattern just to bypass a typo.

## EC2 is not visible in Systems Manager

Check:

```bash
systemctl status amazon-ssm-agent --no-pager
amazon-ssm-agent -version
```

Verify the instance role has `AmazonSSMManagedInstanceCore` and the instance has network connectivity to the required Systems Manager endpoints.

## `deploy.sh` cannot download from S3

Compare server `.env`:

```text
AWS_REGION
S3_BUCKET
S3_PREFIX
```

with the GitLab build output. They must describe the same release location.

## Laravel validation fails

Confirm the release contains:

```text
artisan
vendor/autoload.php
```

and that the application `.env` required by the project was generated correctly in CI.

## Fresh database fails during `optimize:clear`: cache table missing

Typical error:

```text
SQLSTATE[42S02]: Base table or view not found ... cache ... doesn't exist
```

This happens when the application uses Laravel's database cache store and `optimize:clear` runs before the migration that creates the cache table.

The framework order should be:

```text
migrate --force
optional db:seed --force
optimize:clear
```

Confirm the release contains the cache-table migration before retrying deployment.

## `filament:assets` fails with `Permission denied`

Filament writes published assets under the release `public/` directory. The runtime user executing Artisan must be able to write there.

Check:

```bash
ls -ld /datastore/web/test.example.com/builds/<sha>/public
```

The framework should prepare the `public/` ownership for `APP_USER:APP_GROUP` before running `filament:assets`.

## Filament/CSS/JS URLs are generated with `http://` behind an HTTPS ALB

Symptom: the browser reaches the application over HTTPS, but generated assets contain:

```text
http://test.example.com/...
```

Check Nginx preserves the ALB header:

```nginx
proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
```

Then configure Laravel trusted proxies in `bootstrap/app.php`:

```php
$middleware->trustProxies(
    at: '*',
    headers: Request::HEADER_X_FORWARDED_AWS_ELB,
);
```

Redeploy so configuration/cache is rebuilt, then inspect generated URLs again.

## Permission errors in `storage` or `bootstrap/cache`

Check server configuration:

```text
APP_USER
APP_GROUP
LARAVEL_PERSIST_STORAGE
```

Then inspect ownership:

```bash
ls -ld \
  /datastore/web/test.example.com/static \
  /datastore/web/test.example.com/htdocs/storage \
  /datastore/web/test.example.com/htdocs/bootstrap/cache
```

The application runtime user must be able to write required Laravel directories.

## Octane template service does not start

Check the instance configuration:

```bash
cat /etc/octane/example-app-test.env
```

Expected fields:

```text
PROJECT_DIR=/datastore/web/test.example.com
OCTANE_PORT=8001
OCTANE_WORKERS=1
OCTANE_TASK_WORKERS=1
```

Validate runner/template:

```bash
test -x /usr/local/bin/octane-runner
bash -n /usr/local/bin/octane-runner
systemd-analyze verify /etc/systemd/system/octane@.service
systemctl status octane@example-app-test.service --no-pager
```

Check whether the port is already occupied by an old service:

```bash
ss -lntp | grep ':8001'
```

When migrating from a dedicated unit, stop the old service before starting the new template instance.

## Octane log is not writable

The template runner writes to:

```text
/datastore/web/test.example.com/server.logs/octane.log
```

Prepare it for the runtime user:

```bash
touch /datastore/web/test.example.com/server.logs/octane.log
chown www-data:www-data /datastore/web/test.example.com/server.logs/octane.log
```

## First local health check fails, second succeeds

Immediately after `systemctl restart`, Octane may need a short startup interval. A first connection-refused followed by a successful retry is acceptable when `HEALTH_RETRIES` is configured.

Persistent failure is not acceptable; inspect:

```bash
systemctl status octane@example-app-test.service --no-pager
tail -100 /datastore/web/test.example.com/server.logs/octane.log
curl -v http://127.0.0.1:8001/up
```

## Local `/up` is healthy but external URL fails

The application process is likely healthy; inspect the ingress path:

```text
Nginx -> target group -> ALB listener/rule -> TLS -> DNS
```

Useful checks:

```bash
nginx -t
curl -v http://127.0.0.1/up -H 'Host: test.example.com'
curl -v https://test.example.com/up
```

## Same SHA deploys again instead of reporting already deployed

Inspect:

```bash
ROOT=/datastore/web/test.example.com
SHA=<sha>

readlink -f "$ROOT/htdocs"
echo "$ROOT/builds/$SHA"
```

The resolved `htdocs` target must exactly match the expected build directory.

## Framework auto-update fails

Check:

```bash
cd /datastore/web/test.example.com/auto.deploy
git remote -v
git status
git fetch origin main
bash -n deploy.sh
find . -maxdepth 2 -type f -name '*.sh' -exec bash -n {} \;
```

The framework checkout needs network access to its Git remote and must not contain local edits to tracked framework files.
