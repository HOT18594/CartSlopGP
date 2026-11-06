# Platform builds

All four exports use the same project and the same export preset file
(`export_presets.cfg`). Requires Godot 4.7.2 with the matching export templates
installed (`%APPDATA%\Godot\export_templates\4.7.2.stable\`).

## Commands (from `godot_project/`)

```bash
# Windows (exe + pck)
godot --headless --export-release "Windows Desktop" ../builds/v0.6.2/windows/CartSlopGP.exe

# macOS (universal .app, ad-hoc signed, zipped)
godot --headless --export-release "macOS" ../builds/v0.6.2/mac/CartSlopGP.zip

# Linux (x86_64 binary + pck)
godot --headless --export-release "Linux" ../builds/v0.6.2/linux/CartSlopGP.x86_64

# Web (nothreads variant)
godot --headless --export-release "Web" ../builds/v0.6.2/web/index.html
```

Notes:

- macOS needs `textures/vram_compression/import_etc2_astc=true` in Project
  Settings (already enabled) because the build is universal (x86_64 + arm64).
- Run `godot --headless --import` after changing textures before exporting.

## Packages

| Platform | File | Run |
| --- | --- | --- |
| Windows | `CartSlopGP_v0.6.2_windows.zip` | unzip, `CartSlopGP.exe` |
| macOS | `CartSlopGP_v0.6.2_macos.zip` | unzip, open `Cart Slop GP.app` |
| Linux | `CartSlopGP_v0.6.2_linux.zip` | `chmod +x CartSlopGP.x86_64`, run it |
| Web | `CartSlopGP_v0.6.2_web.zip` | serve the folder over HTTP(S), open `index.html` |

## Signing / warnings

- **Windows**: unsigned. SmartScreen will warn on first run ("More info" ->
  "Run anyway"). A code-signing certificate removes this; none is free.
- **macOS**: ad-hoc signed, not notarized. First launch: right-click the app ->
  **Open** (or `xattr -dr com.apple.quarantine "Cart Slop GP.app"`). Without an
  Apple Developer ID ($99/yr) Gatekeeper cannot be fully satisfied.
- **Linux**: no signing needed; the binary is a standard ELF executable.
- **Web**: Godot's Web export uses the *nothreads* variant, so it does not need
  COOP/COEP headers. It must be served over HTTP(S) - opening `index.html`
  from `file://` will not load the WASM. Multiplayer is unavailable on Web.

## Verified

- Windows exe launches headless and exits cleanly (`--quit-after`).
- macOS zip contains `Cart Slop GP.app/Contents/MacOS/Cart Slop GP`, a
  universal Mach-O (`cafebabe` header) plus the pck and `_CodeSignature`.
- Linux binary is ELF x86_64 with the pck next to it.
- Web export produced `index.html`, `.js`, `.wasm`, `.pck` and icon files.
- Every package includes `version.txt` (0.6.2), so the update checker and the
  menu label read the right version.
- The GitHub release exposes all four zips; the updater picks the matching platform build
  (`status=up_to_date`, local 0.6.2, latest 0.6.2).
