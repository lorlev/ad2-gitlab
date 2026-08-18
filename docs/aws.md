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

On Linux, useful checks are:

```bash
systemctl status amazon-ssm-agent --no-pager
amazon-ssm-agent -version
```

The generic document in this guide uses SSM environment-variable parameter interpolation. Use a current SSM Agent; AWS documents this feature for Agent 3.3.2746.0 and later.

## 3. CodeBuild-hosted GitLab runner

In AWS CodeBuild create a **Runner project**:

```text
Project name: example-app-runner
Runner provider: GitLab
Runner location: Repository
Repository: <gitlab-namespace>/<project>
```

Connect the GitLab account/repository through the CodeBuild/CodeConnections flow. CodeBuild creates the integration required to start an ephemeral self-managed GitLab runner when a matching GitLab job is queued.

The GitLab job tag must start with:

```text
codebuild-example-app-runner-$CI_PROJECT_ID-$CI_PIPELINE_IID-$CI_JOB_NAME
```

The example pipeline also uses:

```text
instance-size:small
```

Choose a larger CodeBuild compute size if the application build requires it.

## 4. CodeBuild S3 permissions

Add an inline policy to the CodeBuild service role:

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

The CI example uses `head-object` after upload, so `s3:GetObject` is required for verification.

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

Add an inline policy to the CodeBuild service role. Replace account ID and instance ID:

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

Do **not** grant the pipeline permission to use the generic `AWS-RunShellScript` document if it does not need arbitrary remote shell execution. Restricting the role to `AD2-AutoDeploy` narrows what CI can execute on the instance.

## 7. Network requirements

The target EC2 instance needs outbound connectivity to:

- AWS Systems Manager endpoints;
- the S3 bucket endpoint;
- the framework Git remote when `AUTO_UPDATE=Y`;
- application dependencies/services required during runtime.

This can be provided through public/NAT egress or private VPC endpoints according to the network design.
