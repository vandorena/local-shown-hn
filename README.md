# Local Show HN

Show HN projects tied to one city, town or county (transit trackers, zoning maps, local guides, civic data), on a map and listed in the plain Hacker News style.

## How it works

1. **Scrape.** `ScrapeJob` runs hourly. It reads Show HN stories from the [Algolia HN API](https://hn.algolia.com/api), walking backwards in time because any one query stops at 1,000 hits. It also refreshes points and comment counts for the last week.
2. **Match.** `PlaceMatcher` looks for town and county names from [GeoNames](https://www.geonames.org/) (towns of 5,000+ people, villages, districts like Cherwell, counties, and small states like Vermont) in the title, text and URL.
   - **Strong names** count on their own: names of two or more words, and big cities whose names aren't English words.
   - **Weak names** need more evidence: a qualifier ("Reading, PA") or a local cue word (bus, zoning, residents…). Weak names are smaller places and ones that double as words or first names; the list is generated in `config/gazetteer/common_words.txt`.
   - **Tech names** like Phoenix or Ruby only count with a qualifier.
   - **Villages and districts** are strictest, since nearly every word is a village somewhere: a qualifier, or one word in the title or URL with a local cue, never an ordinary word. "Ordinary" includes words Show HN posts use a lot (demo, startup, FOSS), counted by `script/common_place_words.rb`.

   About 2% of posts (~4,000 of 218k) come out as candidates.
3. **Confirm.** A model decides whether each candidate is really about one of its places, and replies with JSON matching a fixed schema. By default that is Claude Haiku through the Anthropic API (`ClaudeClassifier`); a free local model in [Ollama](https://ollama.com) also works (`LocalClassifier`, `CLASSIFIER=ollama`).
   - The model picks a place by number, so every location comes from GeoNames.
   - A post counts as local only when the model's one-line summary of the project names the place, which drops most posts where the town is just where the maker lives.
   - Posts at or above `LOCAL_THRESHOLD` confidence are shown.
4. **Review.** `/admin` lists what the model decided. Corrections made there are permanent.

Countries and big states are never places: the site is about things smaller than that. A small state (towns adding up to under 2 million people, `GazetteerLoader::SMALL_STATE`) is a place, and its page includes its towns' posts, as a county's does. A name shared with a state or country (Vermont, a Melbourne suburb) counts only with a qualifier.

## Run it locally

```sh
bin/setup --skip-server
bin/rails places:fetch places:load                     # GeoNames into storage/geonames: ~20 MB, plus a 420 MB
                                                       # world dump cut down to villages and districts (GEONAMES_LOCALITIES=0 skips it)
SINCE=2026-10-01 bin/rails hn:backfill hn:match       # one month of posts, matched
export ANTHROPIC_API_KEY=...                           # a key from platform.claude.com/settings/keys
LIMIT=50 bin/rails hn:classify                        # see what the model makes of the newest 50
bin/rails server                                       # http://localhost:3000, admin at /admin (password "dev")
```

To use a free local model instead: `brew install ollama && ollama serve &`, `ollama pull qwen3:4b`, and `CLASSIFIER=ollama` (the default when no API key is set).

## Full backfill

With Claude this can run on the server itself:

```sh
docker compose exec web bin/rails hn:backfill hn:match hn:classify
```

- `hn:backfill`: every Show HN post, ~218k, about 5 minutes.
- `hn:match`: ~4,000 become candidates.
- `hn:classify`: 4 posts at a time (`THREADS`), well under an hour, and under $1 on Haiku. It is safe to stop and rerun; it carries on.

With Ollama, run it on a laptop instead (the model is much faster there than on a CPU-only server: about 4 hours on an M-series Mac), then move the result:

```sh
FILE=posts.jsonl.gz bin/rails hn:export                          # on the laptop
docker compose exec -T web bin/rails hn:import < posts.jsonl.gz  # on the server
```

The import is safe to run twice. A post you corrected by hand on the server keeps your verdict.

## Tuning

- **Matching is too loose or too strict:**
  1. Edit `config/gazetteer/tech_words.txt` or the cue words in `PlaceMatcher`.
  2. Rerun matching from scratch with `RESET=1 bin/rails hn:match`, then `bin/rails hn:classify`.
- **Model:** `CLAUDE_MODEL` (default `claude-haiku-5-5`) picks the Claude model; it runs at low effort with structured outputs. With `CLASSIFIER=ollama`, `OLLAMA_MODEL` picks any model Ollama can pull; `qwen3:4b` needs about 3 GB of RAM and takes about 3.5 s a post on an M-series Mac. Run the eval before switching models.
- **Threshold:** `LOCAL_THRESHOLD` (default `0.6`) sets how sure the model must be before a post is shown. Check `/admin`'s "Unsure" tab before changing it.
- **Prompt or model changes:** score them first with `bin/rails runner script/eval_classifier.rb`. It reclassifies the hand-labelled posts in `test/fixtures/files/classifier_labels.json` (a month of candidates, from October–November 2026) and prints precision and recall. It changes the development database, and the posts have to be there (`SINCE=2026-10-24 bin/rails hn:backfill hn:match`). The prompt was tuned on `qwen3:4b`, where it scores precision 1.0 and recall 1.0; it was tuned on these same labels, so expect worse on the full history.
- **Common words:** run `bin/rails runner script/common_place_words.rb` to rebuild `config/gazetteer/common_words.txt` after a GeoNames update. It needs macOS's `/usr/share/dict`.

## Deploy

The setup is the same as findme: a Coolify "Docker Compose" resource from this repo, using `docker-compose.yml`. It runs one container, **`web`**: Rails, with Solid Queue inside Puma and SQLite on the `storage` volume. It needs about 1 GB of RAM with villages and districts loaded.

To classify with Ollama instead of the API, add `docker-compose.ollama.yml` (`docker compose -f docker-compose.yml -f docker-compose.ollama.yml up`). That adds an **`ollama`** container on its own volume, reachable only by `web`, which pulls the model (several GB) on first start.

Set these variables:

| Variable | |
|---|---|
| `RAILS_MASTER_KEY` | runtime only (see the top of `Dockerfile`) |
| `ADMIN_PASSWORD` | turns on `/admin` |
| `ANTHROPIC_API_KEY` | for the classifier; a key from [platform.claude.com](https://platform.claude.com/settings/keys). Without it, posts wait as candidates |
| `CLAUDE_MODEL` | optional, default `claude-haiku-5-5` |
| `GEONAMES_LOCALITIES` | optional, default `1`; `0` skips villages and districts, saving a 420 MB monthly download and about 400 MB of RAM |
| `LOCAL_THRESHOLD` | optional, default `0.6` |

On first boot:
- `web` downloads GeoNames, including the 420 MB world dump, which it cuts down to villages and districts in about a minute and then deletes; look for `places: loaded` in its log (about 580k places).

## Checks

`bin/ci` runs rubocop, bundler-audit, importmap audit, brakeman and the tests.

## Credits

- Posts: [Hacker News](https://news.ycombinator.com/show), via [HN Search by Algolia](https://hn.algolia.com/api).
- Places: [GeoNames](https://www.geonames.org/), CC BY 4.0.
- Common-word list: generated from Webster's Second International (public domain).
- Map tiles: © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors.
- Base app and deployment: findme.
