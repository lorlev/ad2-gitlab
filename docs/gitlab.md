# GitLab CI/CD

## 1. Variable model

Keep **non-sensitive deployment coordinates** in `.gitlab-ci.yml` or project-level variables:

```text
AWS_REGION
DEPLOY_SSM_DOCUMENT
DEPLOY_INSTANCE_ID
DEPLOY_AUTO_DIR
DEPLOY_S3_BUCKET
DEPLOY_S3_PREFIX
DEPLOY_EXTERNAL_HEALTH_URL
```

Keep **application secrets** in GitLab CI/CD Variables:

```text
APP_KEY
DB_PASSWORD
API tokens
SMTP credentials
third-party secrets
```

GitLab recommends using CI/CD variables rather than hard-coding sensitive values in pipeline YAML. When environments are used, scope sensitive variables to the intended environment where your GitLab tier/configuration supports environment scoping.

## 2. Laravel application variables

A minimal example:

| Variable | Example | Sensitive |
|---|---|---|
| `APP_ENV` | `test` | No |
| `APP_DEBUG` | `false` | No |
| `APP_URL` | `https://test.example.com` | No |
| `APP_KEY` | application key | Yes |
| `DB_HOST` | RDS endpoint | Usually no |
| `DB_DATABASE` | `example_test` | No |
| `DB_USERNAME` | database user | Treat as sensitive where required |
| `DB_PASSWORD` | database password | Yes |

Add every project-specific variable explicitly. Do not depend on production defaults for test deployments.

If the application has safety controls for mail, SMS, payments or external side effects, validate those variables in CI before building the release.

## 3. Pipeline structure

Use two stages:

```text
build
  └── build-test-release
        |
        v
deploy
  └── deploy-test
```

The build job:

1. uses the CodeBuild-hosted GitLab runner;
2. selects the required PHP version;
3. validates environment safety;
4. creates application `.env` from GitLab variables;
5. runs `composer install --no-dev`;
6. creates `release.tar.gz`;
7. uploads release and `.env` to S3 using the commit SHA.

The deploy job:

1. calls the reusable `AD2-AutoDeploy` SSM document;
2. passes `AutoDeployDir` and `CI_COMMIT_SHA`;
3. polls `GetCommandInvocation`;
4. prints server stdout/stderr into the GitLab job log;
5. fails when SSM or the deployment script fails;
6. performs a final external HTTPS health check.

Use [`examples/gitlab-ci.yml`](examples/gitlab-ci.yml) as the complete baseline.

## 4. CodeBuild runner tag

For a CodeBuild project named `example-app-runner`:

```yaml
default:
  tags:
    - codebuild-example-app-runner-$CI_PROJECT_ID-$CI_PIPELINE_IID-$CI_JOB_NAME
    - instance-size:small
```

The project name in this tag must match the AWS CodeBuild Runner project.

## 5. PHP runtime selection

The example pipeline uses:

```bash
phpenv global "$PHP_84_VERSION"
hash -r
php -v
```

and then asserts PHP 8.4.

For a newer PHP version, update this block to the version exposed by the selected CodeBuild image and update the EC2 runtime accordingly. Do not allow the CodeBuild image default to choose a different PHP major/minor silently.

## 6. Application `.env` generation

The example starts from `.env.example`:

```bash
cp .env.example /tmp/app.env
```

Then it removes each existing key and appends the GitLab-provided value:

```bash
set_env() {
  KEY="$1"
  VALUE="$2"
  sed -i "/^${KEY}=/d" /tmp/app.env
  printf '%s=%s\n' "$KEY" "$VALUE" >> /tmp/app.env
}
```

Add project-specific keys explicitly:

```bash
set_env API_TOKEN "$API_TOKEN"
```

Do not print secret values into the job log.

If a variable must contain multiline or complex dotenv syntax, use a project-specific rendering strategy or a GitLab file-type variable rather than assuming the simple `KEY=value` renderer is sufficient.

## 7. Build artifact contract

The S3 contract is:

```text
$DEPLOY_S3_PREFIX/$CI_COMMIT_SHA/release.tar.gz
$DEPLOY_S3_PREFIX/$CI_COMMIT_SHA/.env
```

The server-side framework depends on this exact release identity.

CI runs:

```bash
composer install --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader
```

Do not run `composer update` in CI. The committed lock file is the dependency contract.

## 8. Environment handling

The build job uses:

```yaml
environment:
  name: test
  action: prepare
```

This makes the `test` environment context available to the build without representing the build step itself as the deployment action.

The deploy job uses:

```yaml
environment:
  name: test
  url: https://test.example.com
```

For production, use a separate environment, protected branch/tag strategy and approval model.

## 9. First-run commissioning

Before enabling automatic deploys, temporarily make the deploy job manual:

```yaml
when: manual
```

Validate the build artifact and run the SSM document manually once. After successful deployment, idempotency check and external health check, remove `when: manual`.

## 10. Concurrency

The example deploy job uses:

```yaml
resource_group: test
```

This serializes deployments targeting the same GitLab environment. The server framework also uses a local lock; both controls reduce overlapping deployment risk.
