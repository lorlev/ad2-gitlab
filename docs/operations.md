# Operations

## Normal deployment

After installation, normal TEST deployment is intentionally simple:

```text
push/merge to test
      |
      v
build-test-release
      |
      v
S3 release objects
      |
      v
deploy-test
      |
      v
AD2-AutoDeploy -> EC2 -> ad2-gitlab
```

A successful deploy ends with:

```text
Status: Success
Response code: 0
Deployment SUCCEEDED
```

## Verify the active release

```bash
readlink -f /datastore/web/test.example.com/htdocs
```

The result should be:

```text
/datastore/web/test.example.com/builds/<active-sha>
```

Check service and local application health:

```bash
systemctl --no-pager --full status octane@example-app-test.service
curl -fsS http://127.0.0.1:8001/up
```

Check the public path:

```bash
curl -fsS https://test.example.com/up
```

## Repeat deployment of the same SHA

Re-running deployment for the currently active commit is safe. Expected output:

```text
Commit already deployed: <sha>
```

The framework should not download the artifact, rerun migrations/seeders or restart the service in this case.

## Laravel seeding policy

`LARAVEL_SEED` is opt-in.

Default:

```text
LARAVEL_SEED=N
```

Enable:

```text
LARAVEL_SEED=Y
```

only when the application's `DatabaseSeeder` is deliberately safe to run repeatedly. Seeders used on every deployment should be idempotent, for example by using `updateOrCreate`, `firstOrCreate`, `upsert`, or equivalent application logic.

With seeding enabled, the framework runs:

```bash
php artisan db:seed --force
```

immediately after successful migrations and before cache/asset preparation.

Do not put demo/test-only data or destructive reset logic in a seeder that is enabled for production deployment.

One-time bootstrap operations such as creating the first privileged account are better treated as explicit operational actions unless the project intentionally includes them in an idempotent deployment seeder.

## Roll back application code

The release identity is the Git commit SHA. To redeploy a previous release, invoke the pipeline/manual SSM document with a previous SHA whose S3 objects still exist.

Example:

```bash
aws ssm send-command \
  --instance-ids "i-0123456789abcdef0" \
  --document-name "AD2-AutoDeploy" \
  --parameters \
    'AutoDeployDir=["/datastore/web/test.example.com/auto.deploy"],CommitSha=["<previous-sha>"]' \
  --region eu-central-1
```

### Database warning

Application rollback does **not** undo database migrations or seeding. A previous application release must remain compatible with all database changes already applied. See [Security](security.md#database-change-safety).

## Framework update behavior

With:

```text
AUTO_UPDATE=Y
AUTO_UPDATE_REMOTE=origin
AUTO_UPDATE_BRANCH=main
```

`ad2-gitlab` checks the configured framework branch before deployment. Keep framework changes backward-compatible with existing server `.env` files and deployment layouts.

Before publishing a framework change:

1. run `bash -n` over all shell files;
2. test on a non-production environment;
3. test both successful and failed deployment paths;
4. verify an existing installation can self-update without changing its local `.env`.

New lifecycle options should default to disabled when enabling them automatically could change existing application behavior. `LARAVEL_SEED=N` and `LARAVEL_FILAMENT_ASSETS=N` follow this rule.

## Build retention

`BUILDS_COUNT` controls local build retention. S3 retention is independent; use S3 lifecycle/versioning policy when required.

Keep enough previous releases to support operational rollback while avoiding unlimited disk growth.

## Logs and diagnostics

Recommended application deployment log layout:

```text
/datastore/web/test.example.com/server.logs/
├── access.log
├── error.log
├── artisan.output.log
└── octane.log
```

Use:

```bash
tail -f /datastore/web/test.example.com/server.logs/octane.log
tail -f /datastore/web/test.example.com/server.logs/artisan.output.log
systemctl status octane@example-app-test.service --no-pager
readlink -f /datastore/web/test.example.com/htdocs
ls -lah /datastore/web/test.example.com/builds
nginx -t
```

SSM stdout/stderr and the GitLab job log remain the primary deployment result. Persistent server logs provide historical runtime and Artisan details.

Configure log rotation for `octane.log`, `artisan.output.log`, and Nginx logs so long-running applications do not grow files without limit.

## Manage all Octane instances

List template instances:

```bash
systemctl list-units 'octane@*' --no-pager
```

Check a specific application:

```bash
systemctl status octane@example-app-test.service --no-pager
```

Restart only one application:

```bash
systemctl restart octane@example-app-test.service
```

Each application's project directory, port and worker counts are stored in its `/etc/octane/<instance>.env` file.

## Acceptance checklist

The environment is considered commissioned when all items pass:

- [ ] EC2 can reach its database without public database exposure.
- [ ] EC2 is an active SSM managed node.
- [ ] S3 bucket is private and encrypted.
- [ ] EC2 role can read only required deployment artifacts.
- [ ] CodeBuild role can write/verify required artifacts.
- [ ] Shared CodeBuild roles are used only inside an intentional trust boundary.
- [ ] CodeBuild role can invoke only the intended deployment document/instance.
- [ ] CodeBuild runner starts from GitLab with the configured tag.
- [ ] Build and server use the same PHP major/minor.
- [ ] `release.tar.gz` and `.env` are uploaded under the commit SHA.
- [ ] `AD2-AutoDeploy` succeeds manually.
- [ ] `htdocs` points to the requested build.
- [ ] `octane@<instance>.service` is active.
- [ ] local `/up` returns success.
- [ ] external HTTPS health returns success.
- [ ] Laravel generates HTTPS URLs correctly behind the ALB.
- [ ] same-SHA deployment exits as already deployed.
- [ ] automatic GitLab build -> SSM deploy succeeds.
- [ ] no static AWS access keys exist in GitLab or `auto.deploy/.env`.
- [ ] notification and application secrets are not present in source control or logs.
