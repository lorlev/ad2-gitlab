# Troubleshooting

## GitLab job does not start in CodeBuild

Check:

- CodeBuild project type is **Runner project**.
- GitLab repository connection is authorized.
- runner tag contains the exact CodeBuild project name.
- webhook/integration exists and is enabled.

Expected tag pattern:

```text
codebuild-example-app-runner-$CI_PROJECT_ID-$CI_PIPELINE_IID-$CI_JOB_NAME
```

## `hostname: command not found` in the runner startup log

Some CodeBuild runner images can emit this during runner environment preparation. If the GitLab shell executor proceeds and the job succeeds, this warning is not a deployment failure.

Investigate only if your job itself requires `hostname`.

## Wrong PHP version in CodeBuild

Symptom:

```text
PHP 8.x expected, another version is active
```

Do not rely on the image's default runtime. Explicitly select and verify the required version before Composer:

```bash
phpenv global "$PHP_84_VERSION"
hash -r
php -v
```

For a newer PHP 8.4+ version, use the corresponding runtime available in the selected CodeBuild image and update the server to the same major/minor.

## Composer says the lock file is out of date

Example:

```text
The lock file is not up to date with the latest changes in composer.json
```

Fix this in development and commit the correct `composer.lock`. Do not solve it with `composer update` inside CI.

## S3 upload fails with `AccessDenied`

Check the **CodeBuild service role**, not the EC2 role.

It needs:

```text
s3:PutObject
s3:GetObject
s3:GetBucketLocation
```

for the configured bucket/prefix.

Confirm `.gitlab-ci.yml` uses the same bucket and prefix as the IAM policy.

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

## First local health check fails, second succeeds

Immediately after `systemctl restart`, the application server may need a short startup interval. A first connection-refused followed by a successful retry is acceptable when `HEALTH_RETRIES` is configured.

Persistent failure is not acceptable; inspect:

```bash
systemctl status example-app-test.service --no-pager
journalctl -u example-app-test.service -n 200 --no-pager
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
