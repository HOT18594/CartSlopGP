# Deploy the staged Cart Slop GP Web release to R2 + a Cloudflare Worker.
#
# Optional alternative to the Cloudflare Pages path (README explains the
# trade-off: Pages is simpler, R2+Worker gives explicit Brotli negotiation and
# object-level control). Like upload_pages.ps1 this is a MANUAL, owner-approved
# action: it refuses to run without a scoped token in the environment, never
# prints it, and always re-stages through stage_release.ps1 so the version
# parity guard runs before anything is uploaded.
#
# One-time owner setup (see README.md "Manual approval steps"):
#   $env:CLOUDFLARE_API_TOKEN  = "<Worker Scripts: Edit + R2: Edit token>"
#   $env:CLOUDFLARE_ACCOUNT_ID = "<account id>"
#   powershell -File scripts\upload_r2.ps1 -CreateBucket      # creates cartslop-web
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\upload_r2.ps1
#   ... -Bucket cartslop-web -BaseUrl https://cartslop-play-r2.<subdomain>.workers.dev
#
# Exit codes: 0 uploaded (+verified when -BaseUrl given), 1 refused/failed.
param(
    [string]$Bucket = "cartslop-web",
    [string]$Config = "wrangler.r2.jsonc",
    [string]$WebDir = "",
    [string]$BaseUrl = "",
    [switch]$CreateBucket,
    [switch]$SkipStage,
    [switch]$SkipWorker,
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$deployRoot = Split-Path -Parent $scriptDir
$dist = Join-Path $deployRoot "dist"

function Fail([string]$Message) {
    Write-Host ("WEB DEPLOY FAILED: " + $Message) -ForegroundColor Red
    exit 1
}

if (-not $env:CLOUDFLARE_API_TOKEN) {
    Fail ("CLOUDFLARE_API_TOKEN is not set. Create a token with 'Workers Scripts: Edit' + 'Workers R2 Storage: Edit' (Account scope), set it in this shell only (`$env:CLOUDFLARE_API_TOKEN='...'`) and re-run.")
}
if (-not $env:CLOUDFLARE_ACCOUNT_ID) {
    Fail "CLOUDFLARE_ACCOUNT_ID is not set. Copy it from the Cloudflare dashboard into this shell only."
}

$wranglerLocal = Join-Path $deployRoot "node_modules\.bin\wrangler.cmd"
if (Test-Path -LiteralPath $wranglerLocal) {
    $wrangler = $wranglerLocal
    $wranglerArgs = @()
} else {
    $npx = (Get-Command "npx.cmd" -ErrorAction SilentlyContinue)
    if ($null -eq $npx) {
        Fail "wrangler is not installed: run 'npm install' in web_deploy\ (Node.js >= 20) or install wrangler globally."
    }
    $wrangler = "npx.cmd"
    $wranglerArgs = @("--yes", "wrangler@4")
}

$powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path -LiteralPath $powershellExe)) { $powershellExe = "powershell" }

# --- 1. Stage with precompression (guard included) -------------------------
if (-not $SkipStage) {
    $stageArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                   (Join-Path $scriptDir "stage_release.ps1"), "-OutDir", $dist,
                   "-Force", "-Precompress")
    if ($WebDir -ne "") { $stageArgs += @("-WebDir", $WebDir) }
    & $powershellExe @stageArgs
    if ($LASTEXITCODE -ne 0) {
        Fail "the release did not pass staging/version verification. Nothing was uploaded."
    }
} elseif (-not (Test-Path -LiteralPath (Join-Path $dist "version.json"))) {
    Fail ("-SkipStage was used but " + $dist + " has no staged release")
}

Push-Location $deployRoot
try {
    # --- 2. Optional bucket creation --------------------------------------
    if ($CreateBucket) {
        Write-Host ("== creating R2 bucket '" + $Bucket + "' (no-op if it exists) ==") -ForegroundColor Cyan
        & $wrangler @wranglerArgs r2 bucket create $Bucket
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   bucket create returned $LASTEXITCODE (it may already exist); continuing" -ForegroundColor Yellow
        }
    }

    # --- 3. Upload objects -------------------------------------------------
    $contentTypes = @{
        ".html" = "text/html; charset=utf-8"
        ".js"   = "text/javascript; charset=utf-8"
        ".wasm" = "application/wasm"
        ".pck"  = "application/octet-stream"
        ".png"  = "image/png"
        ".json" = "application/json"
        ".txt"  = "text/plain; charset=utf-8"
    }
    $immutable = "public, max-age=31536000, immutable"
    $noStore = "no-store, must-revalidate"
    # Pages-only config consumed by Cloudflare itself, not by the Worker.
    $pagesOnly = @("_headers", "_redirects", "robots.txt")
    $files = @(Get-ChildItem -LiteralPath $dist -Recurse -File | Sort-Object FullName)
    Write-Host ("== uploading " + $files.Count + " object(s) to R2 bucket '" + $Bucket + "' ==") -ForegroundColor Cyan
    $failures = 0
    $index = 0
    foreach ($file in $files) {
        $index++
        $relative = $file.FullName.Substring($dist.Length + 1).Replace('\', '/')
        if ($pagesOnly -contains (Split-Path $file.FullName -Leaf)) { continue }
        $key = $Bucket + "/" + $relative
        $encoding = ""
        $contentName = $relative
        if ($relative.EndsWith(".br")) {
            $encoding = "br"
            $contentName = $relative.Substring(0, $relative.Length - 3)
        } elseif ($relative.EndsWith(".gz")) {
            $encoding = "gzip"
            $contentName = $relative.Substring(0, $relative.Length - 3)
        }
        $extension = [System.IO.Path]::GetExtension($contentName).ToLowerInvariant()
        $contentType = "application/octet-stream"
        if ($contentTypes.ContainsKey($extension)) { $contentType = $contentTypes[$extension] }
        if ($relative -eq "version.json" -or $relative -eq "release.json") {
            $cacheControl = $noStore
        } elseif ($contentName -eq "index.html") {
            $cacheControl = $noStore
        } else {
            $cacheControl = $immutable
        }
        $args = @("r2", "object", "put", $key, "--file", $file.FullName,
                  "--content-type", $contentType, "--cache-control", $cacheControl)
        if ($encoding -ne "") { $args += @("--content-encoding", $encoding) }
        Write-Host ("   [" + $index + "/" + $files.Count + "] " + $relative) -ForegroundColor DarkGray
        & $wrangler @wranglerArgs @args
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("   upload failed for " + $relative) -ForegroundColor Red
            $failures++
        }
    }
    if ($failures -gt 0) {
        Fail ($failures + " R2 object(s) failed to upload; the bucket is inconsistent. Re-run after fixing the cause.")
    }

    # --- 4. Deploy the Worker ---------------------------------------------
    if (-not $SkipWorker) {
        Write-Host ("== deploying Worker (" + $Config + ") ==") -ForegroundColor Cyan
        & $wrangler @wranglerArgs deploy --config $Config
        if ($LASTEXITCODE -ne 0) {
            Fail "wrangler deploy failed; the objects are uploaded but the Worker was not updated."
        }
    }
} finally {
    Pop-Location
}

# --- 5. Verify ------------------------------------------------------------
if (-not $SkipVerify -and $BaseUrl -ne "") {
    Write-Host ("== verifying " + $BaseUrl + " ==") -ForegroundColor Cyan
    $verify = Join-Path $scriptDir "verify_deploy.ps1"
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $verify -BaseUrl $BaseUrl -LocalDist $dist
    if ($LASTEXITCODE -ne 0) {
        Fail "the deployed R2/Worker URL did not pass verification."
    }
} elseif (-not $SkipVerify) {
    Write-Host "   (pass -BaseUrl https://... to verify the live Worker; skipped)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "WEB DEPLOY OK: release in R2 bucket '$Bucket' and Worker deployed." -ForegroundColor Green
Write-Host "Manual steps that remain (owner):" -ForegroundColor Yellow
Write-Host "  1. Workers > Settings > Domains & Routes: add a custom domain (uncomment the route in wrangler.r2.jsonc and re-deploy, or use the dashboard)."
Write-Host "  2. On the Pi: set CARTSLOP_WEB_BASE to that hostname and restart cartslop-server; /api/web/version then reports web_base."
Write-Host "  3. Open the URL in a real browser and confirm the game boots."
exit 0
