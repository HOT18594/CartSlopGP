# Deploy the staged Cart Slop GP Web release to Cloudflare Pages.
#
# This is a MANUAL, owner-approved action. It refuses to run without a scoped
# API token in the environment and never prints it. It always re-stages through
# scripts/stage_release.ps1, so the version-parity guard (export version.json vs
# godot_project/version.txt, file hashes, index.html meta tags) runs before a
# single byte is uploaded. Nothing is pushed to git or published anywhere else.
#
# One-time owner setup (see README.md "Manual approval steps"):
#   $env:CLOUDFLARE_API_TOKEN  = "<token with Cloudflare Pages: Edit>"
#   $env:CLOUDFLARE_ACCOUNT_ID = "<account id>"
#   npx wrangler pages project create cartslop-play --production-branch main
#
# Usage (from anywhere; paths resolve from this file):
#   powershell -ExecutionPolicy Bypass -File web_deploy\scripts\upload_pages.ps1
#   ... -BaseUrl https://play.example.com -ProjectName cartslop-play -Branch main
#
# Exit codes: 0 deployed + verified, 1 refused/failed.
param(
    [string]$ProjectName = "cartslop-play",
    [string]$Branch = "main",
    [string]$WebDir = "",
    [string]$BaseUrl = "",
    [switch]$SkipStage,
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
    Fail ("CLOUDFLARE_API_TOKEN is not set. Create a token with 'Cloudflare Pages: Edit' (Account scope) in the Cloudflare dashboard, set it in this shell (`$env:CLOUDFLARE_API_TOKEN='...'`) and re-run. The token is never written to disk by this package.")
}
if (-not $env:CLOUDFLARE_ACCOUNT_ID) {
    Fail ("CLOUDFLARE_ACCOUNT_ID is not set. Copy it from the Cloudflare dashboard (Workers & Pages > Account ID) into this shell only; it is not secret but is required for unattended deploys.")
}

# Prefer a locally installed wrangler (npm install in web_deploy/); fall back to
# npx so the first run works without a separate install step. npx.cmd avoids the
# PowerShell execution-policy block on npx.ps1.
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

# --- 1. Stage (guard included, loud failure) -------------------------------
if (-not $SkipStage) {
    $stageArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                   (Join-Path $scriptDir "stage_release.ps1"), "-OutDir", $dist, "-Force")
    if ($WebDir -ne "") { $stageArgs += @("-WebDir", $WebDir) }
    & $powershellExe @stageArgs
    if ($LASTEXITCODE -ne 0) {
        Fail "the release did not pass staging/version verification. Nothing was uploaded."
    }
} elseif (-not (Test-Path -LiteralPath (Join-Path $dist "version.json"))) {
    Fail ("-SkipStage was used but " + $dist + " has no staged release")
}

# Cloudflare Pages rejects any single asset larger than 25 MiB. Check the staged
# release's own metadata BEFORE calling wrangler: the Godot Web export is a
# single 120 MB index.pck + 37 MB wasm, so the real game client must deploy to
# R2 + Worker (scripts/upload_r2.ps1). This is a hard Cloudflare limit, not a
# choice; see README "Why R2 + Worker, not Pages, for the game client".
$releaseMeta = Get-Content -LiteralPath (Join-Path $dist "release.json") -Raw | ConvertFrom-Json
if ($null -ne $releaseMeta.pages_compatible -and -not [bool]$releaseMeta.pages_compatible) {
    Fail ("Cloudflare Pages limits one asset to 25 MiB; this release's largest file is " + $releaseMeta.largest_file + " at " + [math]::Round([double]$releaseMeta.largest_file_bytes / 1MB, 1) + " MB. Pages cannot host the Godot export. Use: powershell -ExecutionPolicy Bypass -File web_deploy\scripts\upload_r2.ps1")
}

# --- 2. Deploy -------------------------------------------------------------
Write-Host ("== upload " + $dist + " to Cloudflare Pages project '" + $ProjectName + "' (branch " + $Branch + ") ==") -ForegroundColor Cyan
Write-Host ("   " + $wrangler + " " + ($wranglerArgs -join " ") + " pages deploy " + $dist + " --project-name " + $ProjectName + " --branch " + $Branch + " --commit-dirty=true") -ForegroundColor DarkGray
& $wrangler @wranglerArgs pages deploy $dist --project-name $ProjectName --branch $Branch --commit-dirty=true
if ($LASTEXITCODE -ne 0) {
    Fail ("wrangler pages deploy failed (exit " + $LASTEXITCODE + "). If this is the first deploy, run: npx wrangler pages project create " + $ProjectName + " --production-branch " + $Branch)
}

# --- 3. Verify the live result --------------------------------------------
if (-not $SkipVerify) {
    if ($BaseUrl -eq "") { $BaseUrl = "https://" + $ProjectName + ".pages.dev" }
    Write-Host ("== verifying " + $BaseUrl + " ==") -ForegroundColor Cyan
    $verify = Join-Path $scriptDir "verify_deploy.ps1"
    $failed = $true
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $verify -BaseUrl $BaseUrl -LocalDist $dist -Retries 1
        if ($LASTEXITCODE -eq 0) { $failed = $false; break }
        if ($attempt -lt 3) {
            Write-Host "   deploy not visible yet (attempt $attempt/3), waiting 10 s for propagation..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
    }
    if ($failed) {
        Fail ("the deployed URL did not pass verification. The upload itself succeeded; inspect " + $BaseUrl + " and re-run verify_deploy.ps1.")
    }
}

Write-Host ""
Write-Host "WEB DEPLOY OK: $ProjectName deployed and verified." -ForegroundColor Green
Write-Host "Manual steps that remain (owner):" -ForegroundColor Yellow
Write-Host "  1. Pages > Custom domains: add the public hostname and let Cloudflare create DNS."
Write-Host "  2. On the Pi: set CARTSLOP_WEB_BASE to the custom domain in /etc/systemd/system/cartslop-server.service (or the service Environment=), restart cartslop-server, then check /api/web/version reports web_base."
Write-Host "  3. Open the URL in a real browser and confirm the game boots (this package cannot automate WebGL)."
exit 0
