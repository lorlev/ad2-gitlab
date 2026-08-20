# References

The project documentation is intentionally self-contained. These upstream references are useful when AWS, Laravel, systemd or GitLab behavior changes.

## AWS CodeBuild

- [Self-managed GitLab runners in AWS CodeBuild](https://docs.aws.amazon.com/codebuild/latest/userguide/gitlab-runner.html)
- [Configure a CodeBuild-hosted GitLab runner](https://docs.aws.amazon.com/codebuild/latest/userguide/sample-gitlab-runners.html)
- [Create a CodeBuild project / existing service role](https://docs.aws.amazon.com/codebuild/latest/userguide/create-project.html)
- [Change CodeBuild project settings](https://docs.aws.amazon.com/codebuild/latest/userguide/change-project.html)
- [CodeBuild service role guidance](https://docs.aws.amazon.com/codebuild/latest/userguide/setting-up-service-role.html)
- [Available CodeBuild runtimes](https://docs.aws.amazon.com/codebuild/latest/userguide/available-runtimes.html)

## AWS Systems Manager

- [Systems Manager documents](https://docs.aws.amazon.com/systems-manager/latest/userguide/documents.html)
- [SSM document schemas and features](https://docs.aws.amazon.com/systems-manager/latest/userguide/documents-schemas-features.html)
- [Creating SSM document content](https://docs.aws.amazon.com/systems-manager/latest/userguide/documents-creating-content.html)
- [SSM document parameters](https://docs.aws.amazon.com/systems-manager/latest/userguide/documents-syntax-data-elements-parameters.html)
- [`aws ssm send-command`](https://docs.aws.amazon.com/cli/latest/reference/ssm/send-command.html)
- [Configure instance permissions for Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-permissions.html)

## AWS IAM

- [Policies and permissions](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html)
- [IAM security best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

## Laravel

- [HTTP requests: trusted proxies](https://laravel.com/docs/master/requests#configuring-trusted-proxies)
- [Database seeding](https://laravel.com/docs/master/seeding)
- [Deployment / optimization](https://laravel.com/docs/master/deployment)

## systemd

- [systemd unit templates and specifiers](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html)
- [systemd services](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)
- [systemd execution environment](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html)

## GitLab

- [CI/CD YAML syntax](https://docs.gitlab.com/ci/yaml/)
- [CI/CD variables](https://docs.gitlab.com/ci/variables/)
- [Environments](https://docs.gitlab.com/ci/environments/)
- [Deployments](https://docs.gitlab.com/ci/environments/deployments/)

## Framework

- [`ad2-gitlab`](https://github.com/lorlev/ad2-gitlab.git)

## Maintenance note

AWS runner images, service-role limits, runtime availability, Laravel behavior, GitLab features and AWS APIs evolve. Before changing the reference pipeline or IAM model, verify current upstream documentation and test changes in a non-production environment.
