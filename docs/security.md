# Security and Deployment Safety

## Trust boundaries

The system has four distinct trust zones:

1. **GitLab** — source code and application CI/CD secrets.
2. **CodeBuild** — ephemeral build/deploy execution with an IAM service role.
3. **S3** — private release and application configuration storage.
4. **EC2** — runtime and server-local deployment configuration.

Keep permissions directional and minimal:

```text
CodeBuild -> S3 write/read verification
CodeBuild -> SSM SendCommand
EC2       -> S3 read
EC2       -> SSM managed-node control channel
```

## Do not use static AWS access keys

Use IAM roles:

- CodeBuild service role for CI AWS access;
- EC2 instance role for server AWS access.

Do not store `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` in GitLab variables or server `.env` files for this architecture.

## Shared CodeBuild role boundary

A shared CodeBuild service role reduces IAM duplication but increases the blast radius of that role. Every build project using it receives the same AWS permissions.

Use a shared role only when the grouped projects intentionally share the same operational trust boundary. Separate roles are appropriate when applications must not be able to access each other's S3 prefixes, deployment instances or other AWS resources.

AWS currently documents a maximum of 10 CodeBuild projects per service role. Use additional shared roles when the project count exceeds that limit.

## Least-privilege SSM execution

Prefer the custom document:

```text
AD2-AutoDeploy
```

over permission to invoke `AWS-RunShellScript` from CI.

Recommended IAM restriction:

- `ssm:SendCommand` on the `AD2-AutoDeploy` document ARN;
- the intended EC2 instance ARN(s);
- `ssm:GetCommandInvocation` for result polling.

## Validate SSM parameters

The provided document uses:

```yaml
interpolationType: ENV_VAR
```

and restrictive patterns:

```text
AutoDeployDir -> /datastore/web/<safe-host>/auto.deploy
CommitSha     -> exactly 40 lowercase hexadecimal characters
```

This reduces command-injection risk and prevents CI from selecting arbitrary filesystem paths.

## S3 release security

The artifact bucket contains application code and a generated application `.env`.

Required controls:

- Block public access.
- Use server-side encryption.
- Give CodeBuild access only to the project/environment prefixes it is trusted to write, or to a shared bucket only when projects intentionally share that boundary.
- Give EC2 read access only to prefixes it deploys.
- Do not log `.env` contents.
- Do not expose the artifact bucket through a public website endpoint.

For environments with stricter compliance requirements, use KMS-backed encryption and tighter key policies.

## GitLab secret handling

Store secrets in GitLab CI/CD Variables, not repository YAML.

Use:

- masked/hidden values where supported;
- environment scope for environment-specific secrets;
- protected variables/branches for production;
- separate production credentials from test credentials.

Do not print variable values during debugging.

## Server-local secrets

The framework's local `.env` can contain notification credentials and other operational secrets.

Protect it:

```bash
chown root:root /datastore/web/test.example.com/auto.deploy/.env
chmod 600 /datastore/web/test.example.com/auto.deploy/.env
```

If a token or password is exposed in chat, logs, screenshots or source control, rotate it instead of relying on deletion of the copied text.

## Application-side safety controls

A test environment may still be connected to real external providers. Applications that can send email/SMS, charge payments, modify production integrations or trigger irreversible external actions should implement explicit non-production safety controls.

Validate those controls before producing a deployable artifact.

## Database change safety

`ad2-gitlab` can roll back the application symlink after a failed activation, but it does not automatically reverse migrations or seed operations.

Therefore schema/data changes should remain compatible with the previous application release whenever rollback is required.

For schema changes, use expand/contract or another backward-compatible migration strategy:

1. add new nullable/compatible schema first;
2. deploy code that can work with old and new schema;
3. backfill data if required;
4. remove old schema only after all running/rollback versions no longer depend on it.

Do not rely on automatic `migrate:rollback` during deployment failure.

## Seeding safety

`LARAVEL_SEED` defaults to `N`.

Enable it only for applications whose normal `DatabaseSeeder` is explicitly designed to be repeat-safe and idempotent on every deployment. Avoid plain duplicate-producing inserts, destructive resets, demo data and environment-specific test fixtures in a seeder enabled for production.

A safe deployment seeder should converge the database toward the required state rather than assuming an empty database.

## Trusted proxy safety

When Laravel is behind AWS ALB and Nginx, it can trust `Request::HEADER_X_FORWARDED_AWS_ELB` so generated URLs preserve the original HTTPS scheme.

If the application uses `at: '*'`, ensure the backend is reachable only through the intended proxy/load-balancer path. Octane should bind to loopback/private interfaces rather than a public listener.

## Production separation

Production should use its own:

- GitLab environment and protected deployment controls;
- environment-scoped secrets;
- server root;
- S3 prefix;
- framework `.env`;
- Octane instance configuration;
- health URL;
- database/schema/credentials;
- approval policy as required.

Do not point a TEST pipeline at production paths or credentials.

## Framework update safety

`AUTO_UPDATE=Y` is powerful because every deployment can consume the newest framework version. Framework maintainers should preserve backward compatibility and test updates in non-production environments first.

For stricter production change control, pin `AUTO_UPDATE_BRANCH` to a controlled release branch or disable auto-update and update the framework through a separate approved process.
