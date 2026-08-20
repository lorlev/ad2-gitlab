# ad2-gitlab Documentation

`ad2-gitlab` is a lightweight server-side deployment framework designed to receive immutable application releases from CI/CD, activate them atomically, restart the application service, validate health, and roll back the application symlink when a deployment fails.

Framework repository: <https://github.com/lorlev/ad2-gitlab.git>

## Documentation map

| Document | Purpose |
|---|---|
| [Architecture](architecture.md) | Components, data flow, deployment lifecycle, rollback model |
| [Installation](installation.md) | End-to-end installation runbook |
| [AWS setup](aws.md) | S3, IAM, shared CodeBuild roles, CodeBuild-hosted GitLab runner, Systems Manager |
| [Server setup](server.md) | Runtime, filesystem, reusable Octane systemd template, Nginx and ALB integration |
| [GitLab CI/CD](gitlab.md) | Variables, build/release job, SSM deployment job and commissioning |
| [Configuration reference](configuration.md) | `auto.deploy/.env` options and Laravel lifecycle switches |
| [Operations](operations.md) | Normal deployment, verification, seeding policy, logs, rollback and maintenance |
| [Security](security.md) | Trust boundaries, secrets, IAM least privilege, proxy trust and database safety |
| [Troubleshooting](troubleshooting.md) | Common failure modes and diagnostic commands |
| [References](references.md) | Upstream AWS, Laravel, systemd and GitLab documentation |

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
      +-- migrate / optional seed / cache and asset tasks
      +-- atomically switch htdocs symlink
      +-- restart Octane systemd template instance
      +-- health check
      +-- rollback application symlink on failure
```

The design does not require SSH-based deployment, a permanently running GitLab runner, AWS CodePipeline, or AWS CodeDeploy.

## Supported application runtime

The core framework is Bash-based and is not tied to PHP. Technology-specific behavior is implemented by modules under `tech/`.

The Laravel examples use PHP **8.4**. Keep the CI build and server on the same PHP major/minor version and ensure the selected version is supported by the application, Composer dependencies and required PHP extensions.

## Example values used throughout the documentation

All public examples are intentionally generic:

```text
Project:           example-app
Environment:       TEST
Branch:            test
Hostname:          test.example.com
Server root:       /datastore/web/test.example.com
CodeBuild project: example-app-runner
Shared IAM role:   codebuild-shared-runner-role
SSM document:      AD2-AutoDeploy
S3 bucket:         example-deploy-artifacts
S3 prefix:         example-app/test
EC2 instance:      i-0123456789abcdef0
Octane service:    octane@example-app-test.service
Octane config:     /etc/octane/example-app-test.env
Local port:        8001
PHP:               8.4
```

Replace these values for each real deployment.
