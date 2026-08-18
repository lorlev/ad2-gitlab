# ad2-gitlab Documentation

`ad2-gitlab` is a lightweight server-side deployment framework designed to receive immutable application releases from CI/CD, activate them atomically, restart the application service, validate health, and roll back the application symlink when a deployment fails.

Framework repository: <https://github.com/lorlev/ad2-gitlab.git>

## Documentation map

| Document | Purpose |
|---|---|
| [Architecture](architecture.md) | Components, data flow, deployment lifecycle, rollback model |
| [Installation](installation.md) | End-to-end installation runbook from a prepared GitLab project and EC2/RDS environment |
| [AWS setup](aws.md) | S3, IAM, CodeBuild-hosted GitLab runner, Systems Manager |
| [Server setup](server.md) | Runtime, filesystem, framework installation, systemd, Nginx and load balancer integration |
| [GitLab CI/CD](gitlab.md) | Variables, build/release job, SSM deployment job and commissioning |
| [Configuration reference](configuration.md) | `auto.deploy/.env` options and Laravel-specific settings |
| [Operations](operations.md) | Normal deployment, verification, rollback, framework updates and maintenance |
| [Security](security.md) | Trust boundaries, secrets, IAM least privilege and production controls |
| [Troubleshooting](troubleshooting.md) | Common failure modes and diagnostic commands |
| [References](references.md) | Upstream AWS and GitLab documentation |

Reusable files are under [`docs/examples/`](examples/).

## Reference architecture

```text
GitLab repository
      |
      v
GitLab CI/CD
      |
      v
AWS CodeBuild-hosted GitLab runner
      |
      +-- build dependencies
      +-- create release.tar.gz
      +-- create application .env
      |
      v
Private Amazon S3 release store
      |
      v
AWS Systems Manager Run Command
      |
      v
AD2-AutoDeploy SSM document
      |
      v
EC2: /datastore/web/test.example.com/auto.deploy/deploy.sh <commit-sha>
      |
      +-- self-update deployment framework
      +-- download and validate release
      +-- prepare application
      +-- run migrations/cache tasks
      +-- atomically switch htdocs symlink
      +-- restart systemd service
      +-- health check
      +-- rollback application symlink on failure
```

The design does not require SSH-based deployment, a permanently running GitLab runner, AWS CodePipeline, or AWS CodeDeploy.

## Supported application runtime

The core framework is Bash-based and is not tied to PHP. Technology-specific behavior is implemented by modules under `tech/`.

The Laravel example in this documentation uses **PHP 8.4**. The framework does not impose an upper PHP version limit: PHP **8.4 or newer** can be used when that version is available in both the CI build environment and the target server and is supported by the application, Composer dependencies, PHP extensions and application server. Keep the build and server on the same PHP major/minor version.

## Example values used throughout the documentation

All public examples are intentionally generic:

```text
Project:          example-app
Environment:      TEST
Branch:           test
Hostname:         test.example.com
Server root:      /datastore/web/test.example.com
CodeBuild project: example-app-runner
SSM document:     AD2-AutoDeploy
S3 bucket:        example-deploy-artifacts
S3 prefix:        example-app/test
EC2 instance:     i-0123456789abcdef0
Database:         example_test
PHP:              8.4
```

Replace these values for each real deployment.
