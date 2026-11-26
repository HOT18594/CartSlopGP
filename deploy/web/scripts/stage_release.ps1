# Stage a stamped Godot Web export into a versioned Cloudflare Pages/R2 layout.
#
# Why versioned paths: the Godot exporter always writes index.html/index.js/
# index.wasm/index.pck under fixed names. A flat deployment therefore cannot use
# `Cache-Control: immutable` for the 120 MB pack without serving a stale build to
# returning visitors. This stager copies the release under
#   dist/game/<game version>/<build id prefix>/
# and makes the root a redirect to that directory. Every payload URL now
# contains the content hash (build id) of the release, so it is immutable;
# index.html and version.json stay no-store. See templates/_headers.
#
# The export is ALWAYS verified first with pi_setup/sync_web_release.ps1 -Check:
# version.json must exist, match godot_project\version.txt, and every file hash
# must still be the one stamped at export time. A stale folder fails here (exit
# 1, "WEB STAGE FAILED: ...") and no dist/ is touched.
#
# Usage (from the workspace root):
#   powershell -ExecutionPolicy Bypass -File web_deploy\scripts\stage_release.ps1
#   ... -WebDir builds\v0.8.7\web -OutDir web_deploy\dist -Force
#   ... -Precompress          # also write .gz/.br siblings for the R2 path
#
# Env:
#   CARTSLOP_NO_PAUSE         set by the upload scripts / CI (no prompts anyway)
#
# Exit codes: 0 staged, 1 refused/failed.
param(
    [string]$WebDir = "",
    [string]$OutDir = "",
    [string]$Version = "",
    [string]$ProjectDir = "",
    [switch]$Force,
    [switch]$Precompress,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$deployRoot = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $deployRoot
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    Write-Host ("WEB STAGE FAILED: " + $Message) -ForegroundColor Red
    exit 1
}

function Ok([string]$Message) {
    if (-not $Quiet) { Write-Host ("WEB STAGE OK: " + $Message) -ForegroundColor Green }
}

if ($ProjectDir -ne "") {
    $projectDir = (Resolve-Path -LiteralPath $ProjectDir).Path
} else {
    $projectDir = Join-Path $repoRoot "godot_project"
}
$versionFile = Join-Path $projectDir "version.txt"
$projectFile = Join-Path $projectDir "project.godot"
$syncScript = Join-Path $repoRoot "pi_setup\sync_web_release.ps1"
foreach ($required in @($versionFile, $projectFile)) {
    if (-not (Test-Path -LiteralPath $required)) {
        Fail ("missing " + $required + " - run this from the repository")
    }
}
if (-not (Test-Path -LiteralPath $syncScript)) {
    Fail ("missing " + $syncScript + ", which verifies the export against version.txt")
}

$fileVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
if ($Version -eq "") {
    $Version = $fileVersion
} elseif ($Version -ne $fileVersion) {
    Fail ("-Version " + $Version + " does not match version.txt (" + $fileVersion + ")")
}

if ($WebDir -eq "") {
    $WebDir = Join-Path $repoRoot ("builds\v" + $Version + "\web")
}
$web = Resolve-Path -LiteralPath $WebDir -ErrorAction SilentlyContinue
if ($null -eq $web) {
    Fail ("web export not found: " + $WebDir + " - run pi_setup\build_0_8_7.ps1 (it exports and stamps)")
}
$webPath = $web.Path
foreach ($name in @("index.html", "index.js", "index.wasm", "index.pck")) {
    if (-not (Test-Path -LiteralPath (Join-Path $webPath $name))) {
        Fail ("the web export is missing " + $name + ": " + $webPath)
    }
}

# --- 1. The version-parity guard ------------------------------------------
if (-not $Quiet) {
    Write-Host ("== verifying web build against version.txt (" + $Version + ") ==") -ForegroundColor Cyan
}
$powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path -LiteralPath $powershellExe)) { $powershellExe = "powershell" }
& $powershellExe -NoProfile -ExecutionPolicy Bypass -File $syncScript -WebDir $webPath -Check
if ($LASTEXITCODE -ne 0) {
    Fail ("the export at " + $webPath + " did not pass the version check; refusing to stage a stale/unstamped browser build. Nothing was written.")
}
$stampPath = Join-Path $webPath "version.json"
if (-not (Test-Path -LiteralPath $stampPath)) {
    Fail ("version.json disappeared after the version check: " + $stampPath)
}
try {
    $stamp = Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json
} catch {
    Fail ("version.json is not valid JSON: " + $stampPath)
}
if ($stamp.schema -ne "cartslop.web_release/1") {
    Fail ("version.json schema is '" + $stamp.schema + "', expected 'cartslop.web_release/1'")
}
if ([string]$stamp.game_version -ne $Version) {
    Fail ("version.json is for v" + $stamp.game_version + " but this stage is v" + $Version)
}
if ([string]$stamp.build_id -notmatch '^[0-9a-f]{64}$') {
    Fail ("version.json build_id is not a sha256 hex string: " + $stamp.build_id)
}
$buildShort = ([string]$stamp.build_id).Substring(0, 12)
$releaseRel = "game/" + $Version + "/" + $buildShort
$threaded = $false
if ($null -ne $stamp.variant -and $null -ne $stamp.variant.thread_support) {
    $threaded = [bool]$stamp.variant.thread_support
}

# --- 2. Output directory safety -------------------------------------------
if ($OutDir -eq "") {
    $OutDir = Join-Path $deployRoot "dist"
}
$outFull = [System.IO.Path]::GetFullPath($OutDir)
$distDefault = [System.IO.Path]::GetFullPath((Join-Path $deployRoot "dist"))
if ((Test-Path -LiteralPath $outFull)) {
    $existing = @(Get-ChildItem -LiteralPath $outFull -Force)
    if ($existing.Count -gt 0) {
        if (-not $Force) {
            Fail ("output directory is not empty: " + $outFull + " - pass -Force to replace a previous stage")
        }
        if ($outFull -ne $distDefault) {
            Fail ("refusing -Force on a non-default output directory (" + $outFull + "): delete it manually if that is really intended")
        }
        Remove-Item -LiteralPath $outFull -Recurse -Force
    }
}
New-Item -ItemType Directory -Force -Path $outFull | Out-Null
$releaseDir = Join-Path $outFull ($releaseRel -replace '/', '\')
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

# --- 3. Copy the stamped export (never .gz/.br siblings: regenerated later) --
$skipped = @()
foreach ($item in @(Get-ChildItem -LiteralPath $webPath -File | Sort-Object Name)) {
    if ($item.Name.EndsWith(".gz") -or $item.Name.EndsWith(".br")) {
        $skipped += $item.Name
        continue
    }
    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $releaseDir $item.Name) -Force
}
# The release keeps its own stamp next to index.html (useful for ops and for a
# direct-link build pin); the root copy in dist/version.json is the pointer.
Copy-Item -LiteralPath $stampPath -Destination (Join-Path $releaseDir "version.json") -Force
Copy-Item -LiteralPath $stampPath -Destination (Join-Path $outFull "version.json") -Force
if ($skipped.Count -gt 0 -and -not $Quiet) {
    Write-Host ("   ignored " + $skipped.Count + " compressed sibling(s) from the export; regenerating below") -ForegroundColor DarkGray
}

# --- 4. Hosting metadata + generated config --------------------------------
# Cloudflare Pages refuses any single asset larger than 25 MiB (documented at
# developers.cloudflare.com/pages/platform/limits). Godot Web exports a single
# index.pck + index.wasm, so the real 0.8.7 build cannot use Pages; the R2 +
# Worker path is the deployable one. The flag below is what upload_pages.ps1
# checks so the refusal happens before wrangler talks to Cloudflare.
$pagesLimitBytes = 25 * 1024 * 1024
$largest = @(Get-ChildItem -LiteralPath $releaseDir -File |
             Sort-Object Length -Descending | Select-Object -First 1)
$largestFile = ""
$largestBytes = 0L
if ($largest.Count -gt 0) {
    $largestFile = $largest[0].Name
    $largestBytes = [long]$largest[0].Length
}
$pagesCompatible = ($largestBytes -le $pagesLimitBytes)

$releaseJson = [ordered]@{
    schema         = "cartslop.web_hosting/1"
    product        = "Cart Slop GP"
    provider       = "cloudflare"
    game_version   = $Version
    engine_version = [string]$stamp.engine_version
    build_id       = [string]$stamp.build_id
    built_utc      = [string]$stamp.built_utc
    staged_utc     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    release_path   = "/" + $releaseRel + "/"
    entry          = "/" + $releaseRel + "/index.html"
    threaded       = $threaded
    precompressed  = [bool]$Precompress
    pages_compatible = $pagesCompatible
    pages_limit_bytes = $pagesLimitBytes
    largest_file   = $largestFile
    largest_file_bytes = $largestBytes
    source         = [ordered]@{
        export_dir = [string]$webPath
        version_txt = $fileVersion
    }
}
[System.IO.File]::WriteAllText((Join-Path $outFull "release.json"),
    ((ConvertTo-Json -InputObject $releaseJson -Depth 6) + "`n"), $utf8NoBom)

$mimeMap = [ordered]@{
    ".html" = "text/html; charset=utf-8"
    ".js"   = "text/javascript; charset=utf-8"
    ".wasm" = "application/wasm"
    ".pck"  = "application/octet-stream"
    ".png"  = "image/png"
    ".json" = "application/json"
}
$mimeLines = New-Object System.Collections.Generic.List[string]
$mimeLines.Add("# Explicit Content-Type for the payload files (Cloudflare Pages")
$mimeLines.Add("# already knows these; this keeps a future Pages MIME change from")
$mimeLines.Add("# breaking WebAssembly streaming compilation).")
foreach ($name in @(Get-ChildItem -LiteralPath $releaseDir -File | Sort-Object Name | ForEach-Object { $_.Name })) {
    $extension = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
    if (-not $mimeMap.Contains($extension)) { continue }
    # index.html and version.json already have a specific block above (with
    # their Content-Type); a second rule for the same path would make Pages
    # join the two blocks and is exactly the kind of duplicate the package
    # validator rejects.
    if ($name -eq "index.html" -or $name -eq "version.json") { continue }
    $mimeLines.Add("/" + $releaseRel + "/" + $name)
    $mimeLines.Add("  Content-Type: " + $mimeMap[$extension])
}

$coopCop = New-Object System.Collections.Generic.List[string]
if ($threaded) {
    $coopCop.Add("# Threaded build (version.json variant.thread_support=true): the Web")
    $coopCop.Add("# export uses SharedArrayBuffer, so these headers are REQUIRED and")
    $coopCop.Add("# active. Keep them on every payload file.")
    $coopCop.Add("/" + $releaseRel + "/*")
    $coopCop.Add("  Cross-Origin-Opener-Policy: same-origin")
    $coopCop.Add("  Cross-Origin-Embedder-Policy: require-corp")
    $coopCop.Add("  Cross-Origin-Resource-Policy: same-origin")
} else {
    $coopCop.Add("# NOT enabled: the export is single-threaded")
    $coopCop.Add("# (variant/thread_support=false in export_presets.cfg), so Godot does")
    $coopCop.Add("# not use SharedArrayBuffer. COOP/COEP are only required for a")
    $coopCop.Add("# threaded export; enabling them early would add cross-origin")
    $coopCop.Add("# restrictions the current build does not need. Re-stage with a")
    $coopCop.Add("# threaded export and this block becomes active automatically.")
    foreach ($line in @("Cross-Origin-Opener-Policy: same-origin",
                        "Cross-Origin-Embedder-Policy: require-corp",
                        "Cross-Origin-Resource-Policy: same-origin")) {
        $coopCop.Add("#   " + $line)
    }
}

$headersTemplate = Join-Path $deployRoot "templates\_headers"
$redirectsTemplate = Join-Path $deployRoot "templates\_redirects"
foreach ($template in @($headersTemplate, $redirectsTemplate)) {
    if (-not (Test-Path -LiteralPath $template)) {
        Fail ("missing " + $template + " (part of the web_deploy package)")
    }
}
$headers = [System.IO.File]::ReadAllText($headersTemplate)
$headers = $headers.Replace("%%RELEASE_PATH%%", "/" + $releaseRel)
$headers = $headers.Replace("%%MIME_RULES%%", ($mimeLines -join "`r`n"))
$headers = $headers.Replace("%%COOP_COEP%%", ($coopCop -join "`r`n"))
[System.IO.File]::WriteAllText((Join-Path $outFull "_headers"), $headers, $utf8NoBom)

$flat = New-Object System.Collections.Generic.List[string]
$flat.Add("# Legacy flat URLs from the pre-versioned /play hosting layout.")
foreach ($name in @(Get-ChildItem -LiteralPath $releaseDir -File | Sort-Object Name | ForEach-Object { $_.Name })) {
    # index.html and version.json are handled by explicit rules above: a
    # redirect always wins over a matching asset, so listing them here would
    # shadow the real root version.json pointer.
    if ($name -eq "index.html" -or $name -eq "version.json") { continue }
    $flat.Add("/" + $name + " /" + $releaseRel + "/" + $name + " 301")
}
$redirects = [System.IO.File]::ReadAllText($redirectsTemplate)
$redirects = $redirects.Replace("%%RELEASE_DIR%%", $releaseRel)
$redirects = $redirects.Replace("%%FLAT_REDIRECTS%%", ($flat -join "`r`n"))
[System.IO.File]::WriteAllText((Join-Path $outFull "_redirects"), $redirects, $utf8NoBom)

$robotsTemplate = Join-Path $deployRoot "templates\robots.txt"
if (Test-Path -LiteralPath $robotsTemplate) {
    Copy-Item -LiteralPath $robotsTemplate -Destination (Join-Path $outFull "robots.txt") -Force
}

# --- 5. Optional precompression (R2 + Worker path; Pages compresses itself) --
$precompressReport = ""
if ($Precompress) {
    # Note: no variable may be named $precompress - PowerShell is case
    # insensitive and that would overwrite the [switch]$Precompress parameter.
    $precompressScript = Join-Path $scriptDir "precompress_web.py"
    if (-not (Test-Path -LiteralPath $precompressScript)) {
        Fail ("missing " + $precompressScript)
    }
    $buildDir = Join-Path $deployRoot "build"
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    $precompressReport = Join-Path $buildDir "stage-precompress.json"
    if (-not $Quiet) {
        Write-Host "== precompressing staged release (gzip + brotli, once) ==" -ForegroundColor Cyan
    }
    # Only the game payload needs encoded siblings: the Worker serves the root
    # version.json/release.json pointers as-is (they must be cheap and fresh),
    # so compressing a 3 KB pointer would just add unused objects to the bucket.
    & python $precompressScript (Join-Path $outFull "game") --report $precompressReport --quiet
    if ($LASTEXITCODE -ne 0) {
        Fail ("precompression failed; the staged release is incomplete")
    }
}

# --- 6. Self-check: entry references, stamp parity, release metadata -------
$entry = Join-Path $releaseDir "index.html"
$entryHtml = [System.IO.File]::ReadAllText($entry)
foreach ($reference in @("index.js", "index.wasm", "index.pck")) {
    if (-not $entryHtml.Contains($reference)) {
        Fail ("staged index.html does not reference " + $reference)
    }
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDir $reference))) {
        Fail ("staged release is missing " + $reference)
    }
}
$rootStamp = Get-Content -LiteralPath (Join-Path $outFull "version.json") -Raw | ConvertFrom-Json
if ([string]$rootStamp.game_version -ne $Version) {
    Fail ("staged dist/version.json says " + $rootStamp.game_version + " but this stage is " + $Version)
}
if ([string]$rootStamp.build_id -ne [string]$stamp.build_id) {
    Fail "staged dist/version.json build_id does not match the export stamp"
}
$entryCheck = [System.IO.File]::ReadAllText($entry)
if (-not $entryCheck.Contains('name="cartslop-game-version" content="' + $Version + '"')) {
    Fail ("staged index.html does not advertise v" + $Version + " in its meta tags")
}
$releaseBytes = (Get-ChildItem -LiteralPath $releaseDir -File | Measure-Object -Property Length -Sum).Sum
$distBytes = (Get-ChildItem -LiteralPath $outFull -Recurse -File | Measure-Object -Property Length -Sum).Sum

$manifest = [ordered]@{
    schema         = "cartslop.stage/1"
    game_version   = $Version
    build_id       = [string]$stamp.build_id
    release_path   = "/" + $releaseRel + "/"
    threaded       = $threaded
    precompressed  = [bool]$Precompress
    precompress_report = $precompressReport
    out_dir        = $outFull
    release_bytes  = [long]$releaseBytes
    dist_bytes     = [long]$distBytes
    file_count     = (Get-ChildItem -LiteralPath $releaseDir -File | Measure-Object).Count
    staged_utc     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}
$buildDir = Join-Path $deployRoot "build"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
[System.IO.File]::WriteAllText((Join-Path $buildDir "stage-manifest.json"),
    ((ConvertTo-Json -InputObject $manifest -Depth 6) + "`n"), $utf8NoBom)

Ok ("v" + $Version + " build " + $buildShort + " staged at " + $outFull + " (" + $releaseRel + ", " + [math]::Round($releaseBytes / 1MB, 1) + " MB release, " + $manifest.file_count + " files, threaded=" + $threaded.ToString().ToLower() + ", precompressed=" + $Precompress.ToString().ToLower() + ")")
if (-not $pagesCompatible) {
    Write-Host ("WEB STAGE NOTE: " + $largestFile + " is " + [math]::Round($largestBytes / 1MB, 1) + " MB, above the Cloudflare Pages 25 MiB per-asset limit.") -ForegroundColor Yellow
    Write-Host "                 Deploy this release with web_deploy\scripts\upload_r2.ps1 (R2 + Worker), not upload_pages.ps1." -ForegroundColor Yellow
}
exit 0
