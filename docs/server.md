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

This documentation uses PHP **8.4** as the example. Keep the same PHP major/minor in CI and on the target host.

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
│   ├── access.log
│   ├── error.log
│   ├── artisan.output.log
│   └── octane.log
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

## 4. Reusable systemd template for Laravel Octane

For multiple Laravel applications on one host, use one systemd template instead of one full unit file per application.

Recommended layout:

```text
/etc/systemd/system/octane@.service
/usr/local/bin/octane-runner
/etc/octane/
├── example-app-test.env
└── another-app-prod.env
```

The systemd instance name is logical and does not need to equal the domain:

```text
octane@example-app-test.service
```

Use these example files:

- [`examples/octane@.service`](examples/octane@.service)
- [`examples/octane-runner`](examples/octane-runner)
- [`examples/octane-example-app-test.env`](examples/octane-example-app-test.env)

Install the shared runner and template:

```bash
sudo install -m 755 docs/examples/octane-runner /usr/local/bin/octane-runner
sudo install -m 644 docs/examples/octane@.service /etc/systemd/system/octane@.service
sudo mkdir -p /etc/octane
sudo install -m 600 docs/examples/octane-example-app-test.env /etc/octane/example-app-test.env
```

Prepare the Octane log file so the runtime user can write to it:

```bash
sudo touch /datastore/web/test.example.com/server.logs/octane.log
sudo chown www-data:www-data /datastore/web/test.example.com/server.logs/octane.log
```

Validate and enable:

```bash
sudo systemctl daemon-reload
sudo systemd-analyze verify /etc/systemd/system/octane@.service
sudo systemctl enable octane@example-app-test.service
```

Before the first release, the service may fail because `htdocs` does not exist yet. After a release is active:

```bash
sudo systemctl start octane@example-app-test.service
sudo systemctl status octane@example-app-test.service --no-pager
curl -fsS http://127.0.0.1:8001/up
```

Configure `auto.deploy/.env` with:

```text
SERVICE=octane@example-app-test.service
```

### Migrating an existing dedicated Octane unit

When replacing an old per-application unit, avoid running both services on the same TCP port.

Safe sequence:

```text
1. Install and enable the new template instance.
2. Stop the old service.
3. Start the new template instance.
4. Verify systemd status, listening port and /up.
5. Change auto.deploy/.env SERVICE to the new unit name.
6. Disable and remove the old unit.
7. systemctl daemon-reload.
```

If the new service fails to start, restart the old service before troubleshooting further.

## 5. Octane logs

`octane-runner` redirects Octane stdout/stderr to:

```text
<PROJECT_DIR>/server.logs/octane.log
```

Example:

```bash
tail -f /datastore/web/test.example.com/server.logs/octane.log
```

This keeps process output with the application's other server logs rather than depending only on the journal.

## 6. Artisan output logs

For Laravel deployments, keep a separate persistent file for deployment-time Artisan output:

```text
/datastore/web/test.example.com/server.logs/artisan.output.log
```

`RunArtisan` should mirror stdout/stderr to both the active deployment output (GitLab/SSM) and this file. Typical commands recorded there include:

```text
migrate --force
db:seed --force
optimize:clear
filament:assets
config:cache
route:cache
```

Do not redirect Artisan output only to a file: deployment failures still need to propagate to SSM/GitLab with the original exit code.

## 7. Nginx reverse proxy

Use [`examples/nginx-test.example.com.conf`](examples/nginx-test.example.com.conf) as a baseline.

Important properties:

- the public host is `test.example.com`;
- Nginx proxies application traffic to `127.0.0.1:8001`;
- the application process is not exposed directly on a public interface;
- access/error logs are stored outside release directories;
- when TLS terminates at an upstream ALB, Nginx preserves the ALB `X-Forwarded-Proto` value.

Validate before reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## 8. AWS ALB and Laravel trusted proxies

With HTTPS terminated at an AWS Application Load Balancer, the backend path commonly becomes:

```text
Browser HTTPS -> ALB -> HTTP -> Nginx -> HTTP -> Octane/Laravel
```

Without trusted proxy configuration, Laravel may treat the request as HTTP and generate `http://` asset URLs or redirects.

Nginx should forward the ALB protocol header:

```nginx
proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
```

For current Laravel applications, configure `bootstrap/app.php`:

```php
use Illuminate\Http\Request;

// ...

->withMiddleware(function (Middleware $middleware): void {
    $middleware->trustProxies(
        at: '*',
        headers: Request::HEADER_X_FORWARDED_AWS_ELB,
    );
})
```

Use `at: '*'` only when the application is reachable through the controlled proxy/load-balancer path and the backend is not directly exposed to untrusted clients.

After deployment, verify generated URLs:

```bash
curl -s https://test.example.com/admin/login \
  | grep -oE 'https?://test\.example\.com[^" ]+' \
  | head
```

URLs generated for the public site should use `https://`.

## 9. Load balancer and DNS

If an Application Load Balancer is used:

1. create or reuse a target group for the EC2 instance on the Nginx port;
2. configure the HTTPS listener host rule for `test.example.com`;
3. use ACM for the certificate;
4. point DNS to the ALB;
5. choose health semantics deliberately.

The deployment framework should use an application-aware local health endpoint such as:

```text
http://127.0.0.1:8001/up
```

## 10. Permissions

The framework runs deployment commands through SSM with the permissions available to the SSM Agent process. Application runtime ownership is controlled by `APP_USER`/`APP_GROUP` in `auto.deploy/.env`.

A common Laravel baseline is:

```text
APP_USER=www-data
APP_GROUP=www-data
```

The application `.env` should not be world-readable. Persistent storage, Laravel cache/storage directories, Filament-published assets and runtime logs must be writable where required by the application user.
