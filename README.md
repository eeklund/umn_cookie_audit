# UMN Cookie Audit

A containerized headless-browser audit that visits a list of `*.umn.edu` sites
and reports cookies that are incorrectly scoped to `.umn.edu`. The output is a
CSV you can use to prioritize remediation and target communications to site
owners.

## Why this exists

UMN guidance recommends scoping analytics cookies to each subdomain rather than
the parent `.umn.edu` domain to avoid issues like inflated headers and 431
errors. This tool automates detection across many sites at once.

## What it does

For each site in `data/sites.txt`, the tool:

1. Launches a clean, headless Chromium session inside Docker.
2. Loads the site and waits briefly for tags to set cookies.
3. Records all cookies and flags those scoped to `umn.edu` or `.umn.edu`.
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
docker run --rm -v "$PWD/data:/data" umn-cookie-audit ruby umn_cookie_audit.rb --sites /data/sites.txt --output /data/report.csv --delay 6 --timeout 30 --no-verify-cookiecutter
```

Options:

- `--sites` Path to the input list (default `/data/sites.txt`).
- `--output` Path to the output CSV (default `/data/report.csv`).
- `--delay` Seconds to wait after navigation to allow tags to set cookies (default `4`).
- `--timeout` Navigation timeout in seconds (default `25`).
- `--headful` Run with a visible browser window (useful for debugging; requires a host with a display).
- `--no-verify-cookiecutter` Skip the post-visit CookieCutter page check.

## Notes & tips

- The container uses Chromium at `/usr/bin/chromium`. To override, set
  `BROWSER_PATH` at build/runtime if needed.
- Some sites set cookies only after interaction or deeper navigation. Increase
  `--delay` or test interactively with `--headful`.
- The `remediation` column suggests concrete next actions, typically updating
  GA/gtag to set `cookie_domain` to the site’s exact hostname and removing
  legacy UA tags that force `.umn.edu`.
