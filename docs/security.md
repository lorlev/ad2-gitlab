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

## Least-privilege SSM execution

Prefer the custom document:

```text
AD2-AutoDeploy
```

over permission to invoke `AWS-RunShellScript` from CI.

The custom document constrains inputs and exposes only the deployment operation required by the pipeline.

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

Use a current SSM Agent that supports environment-variable interpolation.

## S3 release security

The artifact bucket contains application code and a generated application `.env`.

Required controls:

- Block public access.
- Use server-side encryption.
- Give CodeBuild access only to the project/environment prefix it writes.
- Give EC2 read access only to prefixes it deploys.
- Do not log `.env` contents.
- Do not expose S3 object URLs publicly.

For environments with stricter compliance requirements, use KMS-backed encryption and tighter key policies.

## GitLab secret handling

Store secrets in GitLab CI/CD Variables, not repository YAML.

Use:

- masked/hidden values where supported;
- environment scope for environment-specific secrets;
- protected variables/branches for production;
- separate production credentials from test credentials.

Do not print variable values during `set -x` debugging.

## Application-side safety controls

A test environment may still be connected to real external providers. Applications that can send email/SMS, charge payments, modify production integrations or trigger irreversible external actions should implement explicit non-production safety controls.

Validate those controls in the build job before producing a deployable artifact.

## Database change safety

`ad2-gitlab` can roll back the application symlink after a failed activation, but it does not automatically reverse migrations.

Therefore schema changes should follow expand/contract or another backward-compatible migration strategy:

1. add new nullable/compatible schema first;
2. deploy code that can work with old and new schema;
3. backfill data if required;
4. remove old schema only after all running/rollback versions no longer depend on it.

Do not rely on automatic `migrate:rollback` during deployment failure.

## Never auto-seed production data

The Laravel deployment module does not run `db:seed` automatically. Keep it that way unless a specific application has an explicitly reviewed, idempotent seed procedure.

## Production separation

Production should use its own:

- GitLab environment and protected deployment controls;
- environment-scoped secrets;
- server root;
- S3 prefix;
- framework `.env`;
- systemd unit;
- health URL;
- database/schema/credentials;
- approval policy as required.

Do not point a TEST pipeline at production paths or credentials.

## Framework update safety

`AUTO_UPDATE=Y` is powerful because every deployment can consume the newest framework version. Framework maintainers should preserve backward compatibility and test updates in non-production environments first.

For stricter production change control, pin `AUTO_UPDATE_BRANCH` to a controlled release branch or disable auto-update and update the framework through a separate approved process.
