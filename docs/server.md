# Server Setup

## 1. Runtime requirements

The generic deployment layer expects a Linux environment with:

```text
bash
git
curl
tar
flock
AWS CLI v2
systemd
```

A Laravel deployment additionally requires:

```text
PHP CLI
Composer-built vendor/ directory in the release
required PHP extensions
an application server/runtime such as Swoole for Octane
```

### PHP version policy

This documentation uses PHP **8.4** as the example. `ad2-gitlab` itself does not pin PHP and can deploy applications using PHP **8.4 or newer** when:

- that version exists on the EC2 host;
- the same major/minor version is selected in the CI build;
- the application's `composer.json` / lock file supports it;
- required extensions support it.

Patch versions can differ. For example, a build on PHP 8.4.x and a server on another PHP 8.4.x patch are acceptable when application dependencies allow it.

Verify:

```bash
php -v
php -m
aws --version
git --version
curl --version
tar --version
```

For Laravel Octane/Swoole:

```bash
php -m | grep -i '^swoole$'
```

Package names vary by Linux distribution; keep OS package installation outside the deployment framework.

## 2. Filesystem layout

Create the deployment root:

```bash
ROOT="/datastore/web/test.example.com"

mkdir -p \
  "$ROOT/builds" \
  "$ROOT/static" \
  "$ROOT/server.logs"
```

After the first deployment:

```text
/datastore/web/test.example.com/
├── auto.deploy/
├── builds/
│   └── <sha>/
├── htdocs -> builds/<sha>
├── server.logs/
└── static/
```

Do not deploy application files directly into `htdocs`; it is managed as the active-release symlink.

## 3. Install the framework

```bash
ROOT="/datastore/web/test.example.com"
AUTO_DEPLOY="$ROOT/auto.deploy"

git clone \
  https://github.com/lorlev/ad2-gitlab.git \
  "$AUTO_DEPLOY"

cd "$AUTO_DEPLOY"
cp .env.example .env
chmod 750 deploy.sh
chmod 600 .env

find . -maxdepth 2 -type f -name '*.sh' -print -exec bash -n {} \;
```

Review Git state:

```bash
git remote -v
git branch --show-current
git log -1 --oneline
```

The checkout must remain a Git repository when framework auto-update is enabled.

Configure `.env` using [Configuration reference](configuration.md).

## 4. systemd service example

For Laravel Octane, use [`examples/example-app-test.service`](examples/example-app-test.service).

Install it:

```bash
sudo cp docs/examples/example-app-test.service \
  /etc/systemd/system/example-app-test.service

sudo systemctl daemon-reload
sudo systemctl enable example-app-test.service
```

Do not require the service to start successfully before the first release: its `WorkingDirectory` points at `htdocs`, which is created by the first deployment.

After a release is active:

```bash
sudo systemctl restart example-app-test.service
sudo systemctl status example-app-test.service --no-pager
curl -fsS http://127.0.0.1:8001/up
```

## 5. Nginx reverse proxy

Use [`examples/nginx-test.example.com.conf`](examples/nginx-test.example.com.conf) as a baseline.

The important properties are:

- the public host is `test.example.com`;
- Nginx proxies application traffic to `127.0.0.1:8001`;
- the application process is not exposed directly on a public interface;
- access/error logs are stored outside release directories.

Validate before reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## 6. Load balancer and DNS

If an Application Load Balancer is used:

1. create or reuse a target group for the EC2 instance on the Nginx port;
2. configure the HTTPS listener host rule for `test.example.com`;
3. use ACM for the certificate;
4. point DNS to the ALB;
5. choose health semantics deliberately.

Two common health-check choices are:

- `/up` — application-aware; target becomes unhealthy if Laravel is unavailable;
- `/status` — web-tier-only; verifies Nginx/host reachability but not application readiness.

The deployment framework should still use an application-aware local health endpoint such as:

```text
http://127.0.0.1:8001/up
```

GitLab should perform a final external health check after SSM succeeds.

## 7. Permissions

The framework runs deployment commands through SSM with the permissions available to the SSM Agent process. Application runtime ownership is controlled by `APP_USER`/`APP_GROUP` in `auto.deploy/.env`.

For the Laravel module, a common baseline is:

```text
APP_USER=www-data
APP_GROUP=www-data
```

The application `.env` should not be world-readable. Persistent storage and Laravel cache/storage directories must be writable by the runtime user.
