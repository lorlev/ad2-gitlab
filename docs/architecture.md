# Architecture

## Design goals

The deployment model is intentionally small and composable:

- GitLab owns source control, pipeline state and environment history.
- AWS CodeBuild provides ephemeral runner capacity only when a job runs.
- Amazon S3 is the immutable release hand-off point between CI and the server.
- AWS Systems Manager (SSM) provides remote execution without SSH deployment credentials.
- `ad2-gitlab` owns server-side deployment behavior.
- systemd owns the application process.
- Nginx or another reverse proxy owns local HTTP ingress.

The application build and the server deployment are separate concerns. CI creates a release; the server never clones the application repository.

## Component responsibilities

### GitLab

GitLab stores source code, CI/CD configuration and environment-scoped secrets. The pipeline creates one release per commit SHA and invokes the generic SSM deployment document.

### AWS CodeBuild-hosted GitLab runner

CodeBuild starts an ephemeral runner for each job. The runner:

1. checks out the GitLab commit;
2. selects the required runtime;
3. installs production dependencies;
4. creates `release.tar.gz`;
5. renders the application `.env` from GitLab CI/CD variables;
6. uploads both objects to S3;
7. invokes SSM for deployment.

No long-lived AWS access keys are required because the runner receives AWS permissions through the CodeBuild service role.

### Amazon S3

S3 stores release objects using the commit SHA as the release identity:

```text
s3://<bucket>/<project>/<environment>/<sha>/release.tar.gz
s3://<bucket>/<project>/<environment>/<sha>/.env
```

The bucket must be private. The CodeBuild role writes artifacts; the EC2 role reads them.

### AWS Systems Manager

One generic Command document, `AD2-AutoDeploy`, is reusable across applications. GitLab passes only:

- `AutoDeployDir` — the absolute path to the local framework checkout;
- `CommitSha` — the 40-character Git commit SHA.

The EC2 instance ID is a target of `SendCommand`; it is not a document parameter.

### EC2 and `ad2-gitlab`

A deployment root has this layout:

```text
/datastore/web/test.example.com/
├── auto.deploy/
├── builds/
├── htdocs -> builds/<active-sha>
├── server.logs/
└── static/
```

`htdocs` is an atomic symlink to the active release. `static/` is reserved for persistent application data that must survive release replacement.

## Deployment lifecycle

```text
1. Validate requested SHA
2. Update ad2-gitlab if AUTO_UPDATE=Y
3. Acquire deployment lock
4. Download release.tar.gz and application .env from S3
5. Validate archive and technology requirements
6. Extract into a temporary build directory
7. Prepare persistent directories/permissions
8. Finalize build directory
9. Run pre-switch technology tasks
10. Atomically switch htdocs
11. Restart systemd service
12. Run local health check with retries
13. Clean old builds
14. Report success
```

For Laravel, pre-switch tasks can include `optimize:clear`, `migrate --force` and `config:cache`.

## Failure and rollback model

If a failure happens after `htdocs` has switched, the framework can restore the previous application symlink and restart the service. This protects application code activation.

Database migrations are deliberately **not automatically reversed**. Production database changes must therefore be backward-compatible with the previous application release. See [Security and deployment safety](security.md#database-change-safety).

## Idempotency

If the requested SHA is already active, the framework exits successfully without downloading, migrating or restarting the application again.

## Framework self-update

When `AUTO_UPDATE=Y`, the framework checks its configured Git remote/branch before deployment. The local project-specific `.env` is not committed and remains on the server.

## Technology modules

Current repository layout separates generic deployment behavior from application-specific behavior:

```text
auto.deploy/
├── deploy.sh
├── inc/
│   ├── functions.sh
│   └── notifications.sh
├── notifs/
│   └── telegram.sh
└── tech/
    ├── generic.sh
    └── laravel.sh
```

Use `TECH=generic` for applications that require only release activation/service restart, or `TECH=laravel` for the Laravel lifecycle implemented by the framework.
