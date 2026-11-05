# Release workflow

Repo: https://github.com/HOT18594/CartSlopGP
Builds live **outside** the repo at `CartSlopGP/builds/<version>/`.

The in-game updater reads `version.txt`, asks GitHub for
`releases/latest`, and compares the tag. Two rules keep it working:

- Tags are `vX.Y.Z` (`v0.2.0`, `v0.2.1`, ...). A missing `v` is tolerated but be consistent.
- The release asset must be a `.zip` whose name contains `windows`
  (`CartSlopGP_v0.2.0_windows.zip`). The updater ignores other assets.

---

## 1. Bump the version

Edit `version.txt`:

```
0.2.0
```

## 2. Update `CHANGELOG.md`

Add a section at the top:

```md
## [0.2.0] - 2026-11-10

### Added
- ...
```

## 3. Commit and tag

```bash
git add -A
git commit -m "Release v0.2.0"
git tag -a v0.2.0 -m "Cart Slop GP v0.2.0"
```

## 4. Push

```bash
git push origin main
git push origin v0.2.0
```

First time only (empty repo already created on GitHub):

```bash
git remote add origin https://github.com/HOT18594/CartSlopGP.git
git branch -M main
git push -u origin main
```

## 5. Export and zip

From `godot_project/`:

```bash
godot --headless --export-release "Windows Desktop" "../builds/v0.2.0/CartSlopGP.exe"
```

Then zip the **contents** of that folder (exe + pck at the zip root):

```bash
cd ../builds
powershell Compress-Archive -Path "v0.2.0/*" -DestinationPath "CartSlopGP_v0.2.0_windows.zip" -Force
```

## 6. Publish the GitHub Release

**With `gh` (installed, needs `gh auth login` once):**

```bash
gh release create v0.2.0 "builds/CartSlopGP_v0.2.0_windows.zip" \
  --repo HOT18594/CartSlopGP \
  --title "Cart Slop GP v0.2.0" \
  --notes "What changed in v0.2.0"
```

**Without `gh`:**

1. Open https://github.com/HOT18594/CartSlopGP/releases/new
2. Tag: `v0.2.0` (create it from the pushed tag)
3. Title: `Cart Slop GP v0.2.0`
4. Upload `CartSlopGP_v0.2.0_windows.zip`
5. **Publish release** (not draft — drafts are invisible to the API the game uses)

## 7. Players get notified automatically

Next time a player opens the main menu, `UpdateChecker` sees the newer tag and
shows an **UPDATE AVAILABLE v0.2.0** button:

1. click → downloads the zip to `user://updates/` (tier 2),
2. the button becomes **RESTART TO INSTALL**,
3. click → the game unpacks to `user://updates/staging`, writes
   `update_install.bat` next to the .exe, launches it and quits. The .bat waits
   for the process to exit, copies the files over, relaunches the game and
   deletes itself.

If the download fails (offline, asset renamed) the button falls back to opening
the release page.

---

## Quick checklist

- [ ] `version.txt` bumped
- [ ] `CHANGELOG.md` updated
- [ ] commit + tag pushed
- [ ] build exported and launches
- [ ] zip named `CartSlopGP_vX.Y.Z_windows.zip`
- [ ] release published (not draft) with the zip attached
- [ ] old build opened once to confirm the update badge appears
