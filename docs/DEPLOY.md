# Deploying the web build

## What the browser needs

The web export is **threaded**. Threads need `SharedArrayBuffer`, and a browser
only grants that to a **cross-origin isolated** page. That means the host must
send both of these on every response, over **HTTPS**:

    Cross-Origin-Opener-Policy: same-origin
    Cross-Origin-Embedder-Policy: require-corp

Miss either, or serve over plain HTTP, and the game does not start — it fails
before the first frame with "Cross-Origin Isolation / SharedArrayBuffer
missing". This is the single most common way to break the deploy.

## Building by hand

    python3 tools/build_web.py

That exports, then renames every file whose name the engine derives from the
executable — `.js`, `.wasm`, `.pck` and both audio worklets — to carry a hash of
the build, and rewrites `index.html` to match. A new build is a new set of URLs,
so a stale browser or CDN cache cannot serve the old one. `index.html` keeps its
name and must be served `no-store`; the generated `_headers` file says so.

## Deploying automatically

`.github/workflows/deploy.yml` runs on a push to `main` that touches the game,
or on demand from the Actions tab. It installs Godot, runs all eighteen test
suites, builds, rsyncs, purges Cloudflare, and then checks the live site is
actually serving `text/html` with both isolation headers — so a deploy that
would have produced the broken state above fails loudly instead of quietly.

### Secrets it expects

| Secret | What it is |
|---|---|
| `SSH_HOST` | the server hostname |
| `SSH_USER` | user with write access to the web root |
| `SSH_KEY` | **private** key, whole file including the BEGIN/END lines |
| `DEPLOY_PATH` | the web root on that server |
| `CF_ZONE_ID` | Cloudflare zone id, on the domain's overview page |
| `CF_API_TOKEN` | token with **Zone → Cache Purge → Purge** on that zone only |
| `SITE_URL` | the public URL, for the post-deploy check |

Add them under Settings → Secrets and variables → Actions.

The Cloudflare token should be a scoped token, not the Global API Key: cache
purge on one zone is all this needs, and a global key in a CI secret is a key
that can do anything to every domain on the account.

### The rsync `--delete` is deliberate

Hashed filenames mean every build writes a new set. Without `--delete` the web
root accumulates one full build — about 45 MB — per deploy, forever.

## nginx

`deploy/nginx.conf` is a working example. Two things to
know if you edit it:

- **Do not add a `types { ... }` block.** In nginx `types` replaces the
  inherited MIME map rather than extending it, so declaring one inside `server`
  discards `include mime.types` and every `.html` on the site loses its
  Content-Type. This happened; `index.html` was served as
  `application/octet-stream` and the game would not boot. nginx has mapped
  `application/wasm` since 1.21, so there is nothing to add anyway.
- **`add_header` does not merge across levels.** An `add_header` in any nested
  `location` block discards every header inherited from `server`, silently
  dropping the two above for whatever that block matches.

## Cloudflare

Turn **Rocket Loader** and **JS Auto Minify** off. Both rewrite the loader and
break the engine.
