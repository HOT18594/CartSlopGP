# Cart Slop GP — website

Static marketing site for **Cart Slop GP**. It is published to GitHub Pages via
the repository's classic **`docs/` folder** deployment:
**https://hot18594.github.io/CartSlopGP/**

Everything here is generated/inspectable source — no build step is needed to
serve it. Files:

```
docs/
  index.html            landing page (nav / hero / features / modes / download)
  404.html              themed not-found page
  styles.css, main.js   styling + reveal/parallax interactions
  site.webmanifest      PWA name/icons/theme
  robots.txt            crawler policy
  _headers              Cloudflare/static-host caching+nosniff reference
  .nojekyll             serve assets as-is on GitHub Pages
  assets/               generated brand assets (icons, logo, hero, OG image, fonts)
  tools/                reproducible generators and checks
  README.md             this file
  (repo docs)           ARCHITECTURE.md, MAINTENANCE.md, QOL_RECOMMENDATIONS.md
```

## Brand assets

All icons/logo/OG artwork derive from the official game art (no invented logo):

| Source | Used for |
| --- | --- |
| `assets/ui/cart_icon.png` (512x512 squircle) | logo, every favicon/icon, Pi pages data URI |
| `assets/ui/boot_splash.png` (1280x720) | hero backplate and OpenGraph artwork |
| `assets/ui/fonts/*` | headings / body (copied with their license files) |

Regenerate/verify (run from the repository root):

```bash
python docs/tools/build_brand_assets.py          # writes docs/assets/*
python docs/tools/build_brand_assets.py --check  # validates, writes nothing
python docs/tools/sync_pi_pages.py --write       # refresh console/login brand block
```

## Local preview

```bash
# from the repository root
python -m http.server 8080 --directory docs
# open http://127.0.0.1:8080/
```

`docs/tools/check_static_site.py` validates links/assets/meta when run from this
folder.

## Deployment

- **GitHub Pages (default):** Settings → Pages → Deploy from a branch →
  `main` / `docs`. Pushing to `main` republishes automatically.
- **Cloudflare (optional CDN for the game client, not this site):** see
  `../deploy/web/README.md`.

> Update the `canonical` / `og:url` / `og:image` tags in `index.html` if the site
> moves to a custom domain.
