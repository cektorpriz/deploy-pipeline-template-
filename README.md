# GitHub Actions deploy pipeline template (SSH + port knocking)

A reusable CI/CD reference for deploying an application to a remote Linux host
over SSH, hardened with **port knocking**, **smoke tests** and **Telegram
notifications**. The pattern is framework-agnostic: the example is a PHP/Yii
project, but the deploy logic is just `git` + `ssh` + `curl`.

## What it demonstrates

- CI on pull requests (lint + static analysis + tests)
- Branch protection as code (`master` accepts changes only from `staging`)
- Auto-deploy on push to `staging` / `master`
- SSH access hidden behind **port knocking** (sequence lives in GitHub Secrets)
- Deploy = `git fetch` + `git reset --hard origin/<branch>` + cache clear
- **Smoke test** that verifies the *correct* environment answered (a marker in
  the `/health` response) — important when prod & staging share one host
- Retry logic that retries only **connection failures** (ssh exit code 255),
  never application errors
- Manual **rollback** workflow
- Telegram notifications

## Workflows

| File                   | Trigger                | Purpose                            |
|------------------------|------------------------|------------------------------------|
| `ci.yml`               | PR → staging/master    | lint, static analysis, tests       |
| `branch-guard.yml`     | PR → master            | enforce `staging` → `master`       |
| `deploy-staging.yml`   | push → `staging`       | deploy to staging                  |
| `deploy-production.yml`| push → `master` / manual | deploy to production (manual confirm) |
| `rollback.yml`         | manual                 | rollback staging/prod to a commit  |

## How a deploy works

1. Load SSH + port-knock sequence from GitHub Secrets.
2. `knock` the ports (temporarily opens the SSH port).
3. `ssh … bash -s` runs a remote script: `git fetch` + `git reset --hard origin/<branch>` + clear cache.
4. Smoke test on the server: curl `/site/health` until it responds with the
   environment marker (`[staging]` / `[production]`).
5. Telegram notification (success/failure).

## Setup

1. On the server: configure `knockd` (port knocking) and SSH key auth.
2. Add these **Secrets** (Settings → Secrets and variables → Actions):
   - `STAGING_SSH_HOST`, `STAGING_SSH_PORT`, `STAGING_SSH_USERNAME`, `STAGING_SSH_PRIVATE_KEY`
   - `PROD_SSH_HOST`, `PROD_SSH_PORT`, `PROD_SSH_USERNAME`, `PROD_SSH_PRIVATE_KEY`
   - `KNOCK_SEQUENCE` (e.g. `7000 8000 9000`)
   - `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` (optional)
3. Adjust `APP_PATH`, `BRANCH`, `HEALTH_PORTS`, `EXPECTED_MARKER` at the top of
   each deploy workflow to match your server layout.
4. Push. Done.

## Security notes

- Secrets live only in GitHub Secrets — never committed.
- Port knocking hides the SSH port from casual scans.
- The smoke-test marker prevents a "green" deploy against the wrong environment
  when prod & staging share a host.
- `concurrency.group` prevents two deploys to the same environment racing.

## License

MIT
