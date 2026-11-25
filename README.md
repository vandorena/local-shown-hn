# Local Show HN

Show HN projects tied to one city, town or county (transit trackers, zoning maps, local guides, civic data), shown on a map.

## How it works

1. **Scrape.** `ScrapeJob` runs hourly. It reads Show HN stories from the [Algolia HN API](https://hn.algolia.com/api), walking backwards in time because any one query stops at 1,000 hits. It also refreshes points and comment counts for the last week.
2. **Match.** `PlaceMatcher` looks for town and county names from [GeoNames](https://www.geonames.org/) (towns of 5,000+ people, plus counties) in the title, text and URL.
   - **Strong names** count on their own: names of two or more words, and big cities whose names aren't English words.
   - **Weak names** need more evidence: a qualifier ("Reading, PA") or a local cue word (bus, zoning, residents…). Weak names are smaller places and ones that double as words or first names; the list is generated in `config/gazetteer/common_words.txt`.
   - **Tech names** like Phoenix or Ruby only count with a qualifier.

   About 2.5% of posts come out as candidates.
3. **Confirm.** `LocalClassifier` asks a free local model, running in [Ollama](https://ollama.com), whether each candidate is really about one of its places. It replies with JSON matching a fixed schema.
   - The model picks a place by number, so every location comes from GeoNames.
   - Posts at or above `LOCAL_THRESHOLD` confidence are shown.
4. **Review.** `/admin` lists what the model decided. Corrections made there are permanent.

Countries and states are never places: the site is about things smaller than that.

## Run it locally

```sh
bin/setup --skip-server
bin/rails places:fetch places:load                     # GeoNames, ~20 MB, into storage/geonames
SINCE=2026-10-01 bin/rails hn:backfill hn:match       # one month of posts, matched
brew install ollama && ollama serve &                  # a free local model
ollama pull qwen3:4b
LIMIT=50 bin/rails hn:classify                        # see what the model makes of the newest 50
bin/rails server                                       # http://localhost:3000, admin at /admin (password "dev")
```

## Full backfill

Do the full backfill on a laptop, where the model is much faster than on a CPU-only server, then move the result to the server.

```sh
bin/rails hn:backfill            # every Show HN post, ~505k, about 5 minutes
bin/rails hn:match               # ~2.5% become candidates
bin/rails hn:classify            # the slow part; safe to stop and rerun, it carries on
FILE=posts.jsonl.gz bin/rails hn:export
```

On the server:

```sh
docker compose exec -T web bin/rails hn:import < posts.jsonl.gz
```

The import is safe to run twice. A post you corrected by hand on the server keeps your verdict.

## Tuning

- **Matching is too loose or too strict:**
  1. Edit `config/gazetteer/tech_words.txt` or the cue words in `PlaceMatcher`.
  2. Rerun matching from scratch with `RESET=1 bin/rails hn:match`, then `bin/rails hn:classify`.
- **Model:** set `OLLAMA_MODEL` to any model Ollama can pull. The default, `qwen3:4b`, needs about 3 GB of RAM and takes about 2 s a post on an M-series Mac; the full history's ~12k candidates take about 7 hours. A bigger model may do better, but run the eval first.
- **Threshold:** `LOCAL_THRESHOLD` (default `0.6`) sets how sure the model must be before a post is shown. Check `/admin`'s "Unsure" tab before changing it.
- **Prompt or model changes:** score them first with `bin/rails runner script/eval_classifier.rb`. It reclassifies the hand-labelled posts in `test/fixtures/files/classifier_labels.json` (a month of candidates, from October–November 2026) and prints precision and recall. It changes the development database, and the posts have to be there (`SINCE=2026-10-24 bin/rails hn:backfill hn:match`). The current prompt on `qwen3:4b` scores precision 1.0 and recall 0.75. Longer prompts with more examples scored worse (precision around 0.5), so keep it short.
- **Common words:** run `bin/rails runner script/common_place_words.rb` to rebuild `config/gazetteer/common_words.txt` after a GeoNames update. It needs macOS's `/usr/share/dict`.

## Deploy

The setup is the same as findme: a Coolify "Docker Compose" resource from this repo, using `docker-compose.yml`. It runs two containers:

- **`web`**: Rails, with Solid Queue inside Puma and SQLite on the `storage` volume.
- **`ollama`**: the model, on the `ollama` volume, reachable only by `web`.

Set these variables:

| Variable | |
|---|---|
| `RAILS_MASTER_KEY` | runtime only (see the top of `Dockerfile`) |
| `ADMIN_PASSWORD` | turns on `/admin` |
| `OLLAMA_MODEL` | optional, default `qwen3:4b` |
| `LOCAL_THRESHOLD` | optional, default `0.6` |

On first boot:
- `web` downloads GeoNames; look for `places: loaded` in its log.
- `ollama` pulls the model, which is several GB. The site is up while that happens, and posts wait as candidates until the model is ready.

## Checks

`bin/ci` runs rubocop, bundler-audit, importmap audit, brakeman and the tests.

## Credits

- Posts: [Hacker News](https://news.ycombinator.com/show), via [HN Search by Algolia](https://hn.algolia.com/api).
- Places: [GeoNames](https://www.geonames.org/), CC BY 4.0.
- Common-word list: generated from Webster's Second International (public domain).
- Map tiles: © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors.
- Base app and deployment: findme.
