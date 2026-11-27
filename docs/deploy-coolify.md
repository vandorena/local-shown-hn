# Deploying Nearby Hacker News on Coolify

Written for an agent doing the deploy. Follow the steps in order and run each check before moving on. If a check fails, use the troubleshooting section; do not improvise around it.

## What gets deployed

- **One container, `web`**, built from the `Dockerfile` in this repo. It runs Rails under Puma on port 3000, with Solid Queue (the job runner) inside Puma.
- **SQLite on a named volume, `storage`**, mounted at `/rails/storage`. It holds the posts, the places, the job queue and the GeoNames files. **This volume is the site's data. Never delete it.**
- **Hourly jobs, no extra service needed:** `ScrapeJob` at minute 5 fetches new Show HN posts, matches them to places and classifies them.
- **Optional second container, `ollama`**, only when classifying with a local model instead of the Anthropic API. See "Using Ollama instead of the API".

The Coolify resource type is **Docker Compose**, using `docker-compose.yml`.

## Before you start: ask the human for these

Do not guess or generate any of these. Do not commit them, write them into files, or echo them into logs or chat.

| Item | Required | Notes |
|---|---|---|
| Coolify access | yes | The dashboard URL, and which server and project to deploy into. |
| Domain | yes | e.g. `nhn.example.com`, with DNS (an A or AAAA record) already pointing at the Coolify server. |
| `RAILS_MASTER_KEY` | yes | The contents of `config/master.key` on the human's machine. That file is gitignored and never in the repo. |
| `ADMIN_PASSWORD` | recommended | Turns on `/admin`, the review pages. Without it `/admin` is switched off. |
| `ANTHROPIC_API_KEY` | recommended | For the classifier. It can also live in the encrypted credentials (`anthropic.api_key`); ask the human whether it's there. With neither (and no Ollama), new posts wait as candidates and never appear. |

Optional settings with safe defaults (only set them if the human asks):

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_MODEL` | `claude-haiku-5-5` | Which Claude model classifies posts. |
| `LOCAL_THRESHOLD` | `0.6` | How sure the model must be before a post is shown. |
| `GEONAMES_LOCALITIES` | `1` | `0` skips villages and districts: saves a 420 MB monthly download and about 400 MB of RAM, but fewer small places match. |

## Server requirements

- About **1 GB of free RAM** for `web` with the default settings, about 600 MB with `GEONAMES_LOCALITIES=0`.
- About 3 GB more if you add Ollama.
- Outbound HTTPS to `hn.algolia.com`, `download.geonames.org` and `api.anthropic.com`.

## Steps

### 1. Create the resource

1. In Coolify, open the target project and environment, then **+ New → Resource**.
2. Choose **Public Repository** (the repo is public):
   - Repository URL: `https://github.com/vandorena/local-shown-hn`
   - Branch: `main`
3. Set the **Build Pack** to **Docker Compose**.
4. Set the **Docker Compose location** to `/docker-compose.yml`.
5. Pick the server, then save. Coolify reads the compose file and lists one service, `web`.

### 2. Set the domain

1. In the resource, open the `web` service's settings.
2. Set its **Domain** to `https://<the domain>:3000`.
   - The `:3000` tells Coolify's proxy which container port to forward to. Visitors still use plain `https://<the domain>`.
3. Use `https://`, not `http://`. The app sets `force_ssl`, so it redirects plain HTTP and relies on Coolify's proxy to terminate TLS.

### 3. Set the environment variables

Open the resource's **Environment Variables** and add:

```
RAILS_MASTER_KEY=<from the human>
ADMIN_PASSWORD=<from the human>
ANTHROPIC_API_KEY=<from the human>
```

For **every** variable, leave **"Is Build Variable?" / "Available at Buildtime" off**.
- They are needed only when the app runs. The build precompiles assets with a dummy secret instead.
- Build-time values are readable from the image with `docker history`.
- The top of `Dockerfile` explains this further.

The other variables in `docker-compose.yml` have defaults there, so you don't need to add them.

### 4. Check the persistent volume

Coolify creates the named volume `storage` from `docker-compose.yml`. In the resource's **Persistent Storage** tab, confirm there is a volume mounted at `/rails/storage`. Don't add or remove anything there.

### 5. Deploy

1. Click **Deploy** and watch the build log.
   - The first build takes several minutes, mostly compiling gems.
   - It should end with the image built and the `web` container started.
2. On first boot, the container's entrypoint (`bin/docker-entrypoint`) runs two steps before Puma starts:
   1. `db:prepare` creates the SQLite databases on the volume.
   2. `places:refresh` downloads GeoNames, including a 420 MB world dump that it trims down and then deletes.
3. Expect the first boot to take **2–5 minutes**. It's done when the container log shows a line like `places: loaded 580123 places`, then Puma's `Listening on http://0.0.0.0:3000`.
4. Later boots skip the download until the GeoNames files are a month old.

The image's health check calls `/up` every 30 seconds, starting after 60 seconds. Coolify may show the container as "starting" or "unhealthy" until the GeoNames load finishes. That's normal on the first boot only.

### 6. Verify

Run these checks from your own machine, not from inside the container:

```sh
curl -fsS -o /dev/null -w "%{http_code}\n" https://<domain>/up          # expect 200
curl -fsS -o /dev/null -w "%{http_code}\n" https://<domain>/            # expect 200
curl -sI http://<domain>/ | head -1                                     # expect a 301 to https
curl -fsS https://<domain>/feed | head -c 200                           # expect Atom XML
```

Then open `https://<domain>/admin`. It should ask for a password: any username, plus `ADMIN_PASSWORD`. If it returns 404 instead, `ADMIN_PASSWORD` isn't set.

A fresh deploy has **no posts yet**, so the front page says "No local posts yet". That's expected. Go to step 7.

### 7. Fill the database (first deploy only)

The hourly scrape only fetches recent posts. For the full history, open a terminal in the `web` container (Coolify: the resource → **Terminal**, pick `web`) and run:

```sh
bin/rails hn:backfill hn:match hn:classify
```

What each part does:
- **`hn:backfill`** fetches all ~218k Show HN posts, in about 5 minutes.
- **`hn:match`** finds the ~4,000 that name a place.
- **`hn:classify`** asks Claude which of those are really about a place. It takes well under an hour and costs under $1 on Haiku. You can stop and rerun it; it picks up where it left off.

Check it worked: the front page lists posts, the map shows orange squares, and `/places` shows continents.

Skip this step on later deploys: the data is already on the volume.

## Redeploying

- **After code changes:** push to `main`, then click **Redeploy** in Coolify, or turn on automatic deploys from the GitHub webhook if the human wants that.
- **What survives a redeploy:** the data stays on the `storage` volume and migrations run automatically on boot through `db:prepare`. No extra steps.
- **Don't** change the volume or compose file names: renaming the `storage` volume creates a new, empty volume.

## Using Ollama instead of the API

Only do this if the human asks. It's free but slow on a CPU-only server and needs about 3 GB more RAM.

1. Coolify's Compose build pack takes one compose file, so it can't apply the `docker-compose.ollama.yml` override on its own. In the resource, edit the compose file Coolify uses:
   - Add the `ollama` service and the `ollama` volume from `docker-compose.ollama.yml`.
   - Add the extra `web` environment variables from it (`CLASSIFIER=ollama`, `OLLAMA_URL=http://ollama:11434`, `OLLAMA_MODEL`).
2. Leave `ANTHROPIC_API_KEY` unset, or set `CLASSIFIER=ollama` explicitly.
3. Deploy. On its first start, `ollama` pulls `qwen3:4b` (several GB). Posts wait as candidates until the model is ready and are classified on the next hourly run.

For a full backfill with Ollama, run it on a laptop and import the result. The README's "Full backfill" section shows how.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Build fails at `SecretsUsedInArgOrEnv` | A secret is marked as a build variable. | Turn off "Is Build Variable?" for it and redeploy. |
| Container restarts with `ActiveSupport::MessageEncryptor::InvalidMessage` or a missing `secret_key_base` | `RAILS_MASTER_KEY` is wrong or missing. | Ask the human for `config/master.key` again. Don't generate a new key: it can't decrypt the existing credentials. |
| Site loops between http and https, or returns 502 | The domain was set without `https://` or without `:3000`. | Set the domain to `https://<domain>:3000` and redeploy. |
| `places: GeoNames refresh failed` in the log | The server can't reach `download.geonames.org`. | The site still serves what it has. Fix outbound network, then restart the container. |
| Container killed during the first boot | Out of memory while loading GeoNames. | Free up RAM on the server, or set `GEONAMES_LOCALITIES=0`. |
| `/admin` returns 404 | `ADMIN_PASSWORD` isn't set. | Add it and redeploy. |
| Posts never appear after the scrape | No classifier is available. | Set `ANTHROPIC_API_KEY`, or add Ollama. Check the log for errors from `ClassifyJob`. |
| Favicon or logo looks out of date | Files in `public/` are cached for a year. | Hard-refresh the browser. If a file in `public/` changes, bump the `?v=` on its link in `app/views/layouts/application.html.erb`. |

## Never

- Delete the `storage` volume, or run `db:reset`, `db:drop` or `db:schema:load` in production. They wipe the site's data.
- Put secrets in the repo, in `docker-compose.yml`, or in build variables.
- Generate a new `RAILS_MASTER_KEY`, or edit `config/credentials.yml.enc`.
- Run `RESET=1 bin/rails hn:match` unless the human asks. It throws away every model verdict except hand corrections.
