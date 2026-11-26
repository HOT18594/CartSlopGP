# Web deployment tooling (reference copy)

This folder is a snapshot of the workspace-level `web_deploy/` package used to
host the Godot Web client on Cloudflare **R2 + a CDN Worker** (Cloudflare Pages
cannot host this game: 25 MiB per-asset limit vs the ~121 MB `index.pck`).

In the normal development layout these scripts live **one level above this git
repository**, next to `godot_project/`, `pi_setup/` and `builds/`, because they
resolve `$repoRoot` as the parent of the `web_deploy` directory. If you use this
copy directly, keep that layout (or adjust the `$repoRoot` lines):

```
<workspace>/
  godot_project/     <- this git repo
  pi_setup/          (sync_web_release.ps1, deploy_server.ps1, build_0_8_7.ps1)
  builds/v0.8.7/web/ <- stamped Web export produced by pi_setup/build_0_8_7.ps1
  web_deploy/        <- this package (or symlink/copy of it)
```

See `README.md` for the full architecture, exact commands, manual Cloudflare
steps (account, scoped API token, R2 bucket, Worker route/custom domain, DNS,
rollback) and the version-parity model. The marketing website now lives in the
git repo under `docs/` and is published by the GitHub Pages classic `docs/`
folder deployment (https://hot18594.github.io/CartSlopGP/).
