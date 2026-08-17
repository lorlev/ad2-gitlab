# Auto Deploy 2 for GitLab

Reusable server-side deployment framework.

The CI system builds application artifacts and uploads them to S3.
Auto Deploy downloads an existing build and deploys it atomically.

It does not clone or build application repositories.

## Deployment flow

GitLab / CodeBuild
    |
    | release.tar.gz
    | .env
    v
S3
    |
    v
auto.deploy
    |
    +-- download
    +-- validate
    +-- prepare
    +-- migrations
    +-- atomic htdocs switch
    +-- systemd restart
    +-- health check
    +-- rollback on failure

## Layout

auto.deploy/
├── deploy.sh
├── inc/
│   ├── functions.sh
│   └── notifications.sh
├── notifs/
│   └── telegram.sh
├── tech/
│   ├── generic.sh
│   └── laravel.sh
├── .env
└── .env.example

Application directories:

project/
├── auto.deploy/
├── builds/
├── htdocs -> builds/<commit>
├── static/
└── server.logs/

## Artifact contract

For commit:

    abcdef123...

Auto Deploy expects:

    s3://<bucket>/<prefix>/<commit>/release.tar.gz
    s3://<bucket>/<prefix>/<commit>/.env

Example:

    s3://example-deploy-artifacts/example.com/test/<sha>/release.tar.gz
    s3://example-deploy-artifacts/example.com/test/<sha>/.env

## Usage

    ./deploy.sh <40-character-git-sha>

Example:

    ./deploy.sh a50e77cd0cd17fb5972766e404ce19a5c5d0611f

## Installation

Clone the repository:

    git clone <auto-deploy-repository> /datastore/web/example.com/auto.deploy

Create local configuration:

    cd /datastore/web/example.com/auto.deploy
    cp .env.example .env

Set permissions:

    chmod 750 deploy.sh
    chmod 600 .env

Configure .env for the service.

## Auto Update

When AUTO_UPDATE=Y, every deployment checks:

    AUTO_UPDATE_REMOTE
    AUTO_UPDATE_BRANCH

If a new version exists, Auto Deploy:

1. Fetches the remote branch.
2. Updates the local framework.
3. Runs Bash syntax validation.
4. Restores the previous version if validation fails.
5. Re-executes deploy.sh using the new version.

The local `.env` file is not stored in Git.

Private repositories require read-only Git access for the Auto Deploy
repository.

Application repositories do not need Git access from the server.

## Rollback

If the health check fails after htdocs is switched:

1. htdocs is switched back to the previous build.
2. The configured systemd service is restarted.
3. The health check runs against the previous release.

Database migrations are not automatically rolled back.

Application migrations therefore need to be backward-compatible with the
previous application release.

## Technology modules

Technology-specific deployment logic is stored under:

    tech/

Current modules:

    generic
    laravel

New technologies can implement:

    TechValidate
    TechPrepare
    TechBeforeSwitch
    TechAfterSwitch
    TechRollback

without changing deploy.sh.

## Notifications

Notification formatting is stored in:

    inc/notifications.sh

Notification transports are stored in:

    notifs/

Currently supported:

    telegram

Notification failures do not fail an application deployment.