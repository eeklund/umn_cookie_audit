# UMN Cookie Audit

A containerized headless-browser audit that visits a list of `*.umn.edu` sites
and reports cookies that are incorrectly scoped to `.umn.edu`. The output is a
CSV you can use to prioritize remediation and target communications to site
owners.

## Why this exists

Many `*.umn.edu` sites still set analytics/tracking cookies at the root `.umn.edu`
domain. That means those cookies are sent to unrelated subdomains, inflating
request headers and triggering HTTP 431 “Request Header Fields Too Large” errors.
UMN guidance is to scope cookies to each subdomain. This tool automates detection
at scale so teams can quickly prioritize and verify fixes.

This project grew out of a U of M Tech People Co-working discussion: despite
several communications, mis-scoped cookies persist and users still hit 431s.
The scanner provides a fast, repeatable way to find problems across many sites
and confirm remediation (e.g., GA/GTM `cookie_domain` updates).

## What it does

For each site in `data/sites.txt`, the tool:

1. Launches a clean, headless Chromium session inside Docker.
2. Loads the site and waits briefly for tags to set cookies.
3. Records all cookies and flags those scoped to `umn.edu` or `.umn.edu` using
   the same suspect lists as the [U of M Library's CookieCutter code](https://github.umn.edu/Libraries/cookie-cutter).
4. Optionally checks the CookieCutter page to capture its verdict.
5. Writes results to `data/report.csv`.

## Output columns

- `site`
- `offending?`
- `offending_cookie_count`
- `offending_cookie_names`
- `offending_cookie_sizes`
- `offending_total_size`
- `cookiecutter_ok`
- `cookiecutter_excerpt`
- `remediation`
- `all_cookies_json`

## Console output

The script prints a single line per site as it finishes, plus a start/finish line:

- ✅ **ok** — no offending cookies detected
- ❌ **offending=N** — N offending cookies detected
- 🚫 **error** — navigation or evaluation error for the site

ANSI colors are enabled by default; use `--no-color` to disable.

## Dependencies

- Docker (recent version)
- macOS optional: the `open` command is used to display the CSV automatically

Everything else (Ruby, gems, Chromium) is installed inside the container image.

## Project layout

```
.
├── Dockerfile
├── Gemfile
├── umn_cookie_audit.rb
├── data/
│   └── sites.txt
└── script/
    └── run
```

## Adapting `data/sites.txt`

- Put **one site per line**.
- URLs may be written **with or without** `https://`.
- Lines starting with `#` are treated as comments and ignored.

Example:

```
onestop.umn.edu
https://asr.umn.edu
roomsearch.umn.edu
```

## Quick start

Use the convenience script:

```bash
script/run
```

This will:

1. Move to the project root.
2. Build the Docker image: `docker build -t umn-cookie-audit .`
3. Run the container, mounting `./data`: `docker run --rm -v "$PWD/data:/data" umn-cookie-audit`
4. On macOS, open `data/report.csv` automatically.

If you prefer the raw Docker commands:

```bash
docker build -t umn-cookie-audit .
docker run --rm -v "$PWD/data:/data" umn-cookie-audit
```

## Advanced usage

You can pass flags to the Ruby tool by appending them after the image name:

```bash
docker run --rm -v "$PWD/data:/data" umn-cookie-audit ruby umn_cookie_audit.rb --sites /data/sites.txt --output /data/report.csv --delay 6 --timeout 30 --no-verify-cookiecutter --separator newline --pool 4
```

### Options

- `--sites` Path to the input list (default `/data/sites.txt`).
- `--output` Path to the output CSV (default `/data/report.csv`).
- `--delay` Seconds to wait after navigation to allow tags to set cookies (default `4`).
- `--timeout` Navigation timeout in seconds (default `25`).
- `--no-verify-cookiecutter` Skip the post-visit CookieCutter page check.
- `--separator NAME` Joiner for multi-value CSV cells: `newline` (default), `comma`, or `pipe`.
- `--no-color` Disable ANSI colors in console output.
- `--pool N` Number of parallel workers (default **4**). To run **single-threaded**, set `--pool 1`.

## Tips & troubleshooting

- **Publish your GA/GTM/Drupal changes.** Changes to `cookie_domain` and related
  settings do **not** take effect until published in Google Tag Manager (and in
  Drupal’s admin UI, if applicable). Bust caches (e.g., Varnish) afterward, then
  re-run the scan.
- Some sites set cookies only after interaction or deeper navigation. Increase
  `--delay` and test again if CookieCutter has different results than this scan.
- For very large batches, increase `--pool` to use more CPU, but watch RAM/CPU
  and external rate limits. Research shows that a pool of 6-8 may be better
  performance than higher. Your mileage may vary depending on your
  processor/core count.
