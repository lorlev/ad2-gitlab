# AWS Setup

This document describes the AWS resources required by the deployment system. Replace all placeholders before use.

## 1. Private S3 release bucket

Create a dedicated artifact bucket, for example:

```text
example-deploy-artifacts
```

Baseline controls:

- Block all public access.
- Disable public ACL-based access; bucket-owner-enforced ownership is recommended.
- Enable default server-side encryption.
- Do not expose the bucket through a public website endpoint.
- Optionally enable versioning and/or lifecycle rules according to retention requirements.

Release layout:

```text
example-app/test/<40-char-sha>/release.tar.gz
example-app/test/<40-char-sha>/.env
```

The application `.env` contains secrets. Treat the bucket as sensitive deployment infrastructure.

## 2. EC2 IAM role

The application instance needs two capabilities:

1. Systems Manager managed-node permissions;
2. read-only access to its release objects.

Attach the AWS managed policy:

```text
AmazonSSMManagedInstanceCore
```

Add a least-privilege inline S3 policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadDeployBucketLocation",
      "Effect": "Allow",
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::example-deploy-artifacts"
    },
    {
      "Sid": "ReadApplicationArtifacts",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::example-deploy-artifacts/example-app/test/*"
    }
  ]
}
```

If one server hosts several applications, expand the object resources only to the prefixes that server is allowed to deploy.

### Verify SSM registration

Confirm SSM Agent is installed/running and that the instance appears in Systems Manager managed nodes.

```bash
systemctl status amazon-ssm-agent --no-pager
amazon-ssm-agent -version
```

The generic document in this guide uses SSM environment-variable parameter interpolation. Use a current SSM Agent.

## 3. CodeBuild-hosted GitLab runner

In AWS CodeBuild create a **Runner project**:

```text
Project name: example-app-runner
Runner provider: GitLab
Runner location: Repository
Repository: <gitlab-namespace>/<project>
```

Connect the GitLab account/repository through the CodeBuild/CodeConnections flow. CodeBuild starts an ephemeral self-managed GitLab runner when a matching GitLab job is queued.

The GitLab job tag must start with:

```text
codebuild-example-app-runner-$CI_PROJECT_ID-$CI_PIPELINE_IID-$CI_JOB_NAME
```

The example pipeline also uses:

```text
instance-size:small
```

Choose a larger CodeBuild compute size only when the build actually needs it.

## Shared CodeBuild service role

Do not create a different IAM service role for every runner project unless separate trust boundaries require it. CodeBuild supports selecting an **Existing service role**, and AWS currently documents that one CodeBuild service role can work with up to **10 build projects**.

A practical layout for 15 similar projects is therefore:

```text
codebuild-shared-runner-role-01  -> projects 1-10
codebuild-shared-runner-role-02  -> projects 11-15
```

Projects sharing a role also share every AWS permission on that role. Only group projects that are operated by the same trusted team and are allowed to access the same deployment infrastructure.

### Shared role trust policy

Example trust policy for runner projects in one AWS account/region:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "<aws-account-id>"
        },
        "ArnLike": {
          "aws:SourceArn": "arn:aws:codebuild:eu-central-1:<aws-account-id>:project/*-runner"
        }
      }
    }
  ]
}
```

### Shared role baseline permissions

A shared runner role usually needs:

- CloudWatch Logs for the runner projects;
- CodeBuild report-group permissions when reports are used;
- the exact GitLab CodeConnection ARN(s);
- S3 access to deployment artifacts;
- `ssm:SendCommand` for `AD2-AutoDeploy` and intended EC2 instance(s);
- `ssm:GetCommandInvocation` for result polling.

Do not copy unrelated generated permissions such as CodePipeline artifact access when CodePipeline is not part of the architecture.

For a group of projects intentionally sharing one deployment bucket, the deployment portion can look like:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DeploymentArtifacts",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::example-deploy-artifacts/*"
    },
    {
      "Sid": "DeploymentBucketLocation",
      "Effect": "Allow",
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::example-deploy-artifacts"
    },
    {
      "Sid": "RunAutoDeploy",
      "Effect": "Allow",
      "Action": "ssm:SendCommand",
      "Resource": [
        "arn:aws:ssm:eu-central-1:<aws-account-id>:document/AD2-AutoDeploy",
        "arn:aws:ec2:eu-central-1:<aws-account-id>:instance/i-0123456789abcdef0"
      ]
    },
    {
      "Sid": "ReadDeploymentResult",
      "Effect": "Allow",
      "Action": "ssm:GetCommandInvocation",
      "Resource": "*"
    }
  ]
}
```

Narrow the S3 prefixes and instance ARNs further when projects do not need a shared deployment boundary.

### Migrating existing CodeBuild projects to a shared role

Change one non-production runner first, test it, then move already-working runners.

```bash
aws codebuild update-project \
  --name "example-app-runner" \
  --service-role "arn:aws:iam::<aws-account-id>:role/codebuild-shared-runner-role-01" \
  --region eu-central-1
```

Verify all migrated projects:

```bash
aws codebuild batch-get-projects \
  --names example-app-runner another-app-runner \
  --region eu-central-1 \
  --query 'projects[*].[name,serviceRole]' \
  --output table
```

Run a real pipeline that covers GitLab checkout, S3 upload and SSM deployment before deleting old roles.

After the migration, old CodeBuild-generated customer-managed policies may remain in IAM with `AttachmentCount=0`. Verify they have no attached users/groups/roles before deleting them.

## 4. CodeBuild S3 permissions

If a project uses a dedicated role instead of a shared role, add an inline policy such as:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadDeployBucketLocation",
      "Effect": "Allow",
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::example-deploy-artifacts"
    },
    {
      "Sid": "WriteAndVerifyApplicationArtifacts",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::example-deploy-artifacts/example-app/test/*"
    }
  ]
}
```

The CI example uses `head-object` after upload, so the role must be able to read/verify the uploaded object metadata.

## 5. Create the generic SSM document

Create this document **once per AWS account/region** and reuse it across projects.

Name:

```text
AD2-AutoDeploy
```

Use [`examples/ssm-ad2-autodeploy.yml`](examples/ssm-ad2-autodeploy.yml).

Create it:

```bash
aws ssm create-document \
  --name "AD2-AutoDeploy" \
  --document-type "Command" \
  --document-format "YAML" \
  --target-type "/AWS::EC2::Instance" \
  --content file://docs/examples/ssm-ad2-autodeploy.yml \
  --region eu-central-1
```

Check status:

```bash
aws ssm describe-document \
  --name "AD2-AutoDeploy" \
  --region eu-central-1 \
  --query 'Document.{Status:Status,Version:DocumentVersion,LatestVersion:LatestVersion,DefaultVersion:DefaultVersion}' \
  --output table
```

Wait for:

```text
Status: Active
```

### Why the document is generic

The document accepts only:

```text
AutoDeployDir
CommitSha
```

`AutoDeployDir` is constrained to `/datastore/web/<host>/auto.deploy`, and `CommitSha` must be exactly 40 lowercase hexadecimal characters. The document uses SSM `ENV_VAR` interpolation rather than embedding user input directly into shell source.

## 6. Allow CodeBuild to invoke the document

For a dedicated role, or as part of the shared role, grant:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RunAutoDeploy",
      "Effect": "Allow",
      "Action": "ssm:SendCommand",
      "Resource": [
        "arn:aws:ssm:eu-central-1:<aws-account-id>:document/AD2-AutoDeploy",
        "arn:aws:ec2:eu-central-1:<aws-account-id>:instance/i-0123456789abcdef0"
      ]
    },
    {
      "Sid": "ReadAutoDeployResult",
      "Effect": "Allow",
      "Action": "ssm:GetCommandInvocation",
      "Resource": "*"
    }
  ]
}
```

Do **not** grant the pipeline permission to use the generic `AWS-RunShellScript` document if it does not need arbitrary remote shell execution.

## 7. Network requirements

The target EC2 instance needs outbound connectivity to:

- AWS Systems Manager endpoints;
- the S3 bucket endpoint;
- the framework Git remote when `AUTO_UPDATE=Y`;
- application dependencies/services required during runtime.

This can be provided through public/NAT egress or private VPC endpoints according to the network design.
