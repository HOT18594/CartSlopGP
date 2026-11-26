# Verify a deployed Cart Slop GP Web release over HTTPS (read-only, no writes).
#
# Run after `upload_pages.ps1` or `upload_r2.ps1`, or by hand against the live
# URL. It checks the things that actually broke /play before: the served stamp
# matches the staged release, the pointer endpoints are no-store, the immutable
# payload is cacheable, the entry HTML advertises the right version, and the
# cross-origin-isolation headers appear only when the build is threaded.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\verify_deploy.ps1 `
#       -BaseUrl https://cartslop-play.pages.dev `
#       -LocalDist web_deploy\dist
#
# Exit code = number of failed checks (0 = deploy looks correct). Manual browser
# rendering is still a human step - see README "Manual approval and checks".
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [string]$LocalDist = "",
    [switch]$ExpectThreaded,
    [int]$Retries = 1
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$deployRoot = Split-Path -Parent $scriptDir
if ($LocalDist -eq "") { $LocalDist = Join-Path $deployRoot "dist" }
$releasePath = Join-Path $LocalDist "release.json"
if (-not (Test-Path -LiteralPath $releasePath)) {
    Write-Host ("WEB DEPLOY VERIFY FAILED: missing " + $releasePath + " - stage the release first") -ForegroundColor Red
    exit 1
}
$release = Get-Content -LiteralPath $releasePath -Raw | ConvertFrom-Json
$entry = [string]$release.entry
$releaseDir = ([string]$release.release_path).TrimEnd('/')
$expected = [string]$release.game_version
$expectedBuild = [string]$release.build_id
if ($entry -eq "" -or $releaseDir -eq "" -or $expected -eq "") {
    Write-Host "WEB DEPLOY VERIFY FAILED: release.json is incomplete (entry/release_path/game_version)" -ForegroundColor Red
    exit 1
}
$base = $BaseUrl.TrimEnd('/')

$script:fails = 0
$script:checks = 0
function Check([bool]$Condition, [string]$Message) {
    $script:checks++
    if ($Condition) {
        Write-Host ("PASS: " + $Message)
    } else {
        Write-Host ("FAIL: " + $Message) -ForegroundColor Red
        $script:fails++
    }
}

# Use HttpWebRequest rather than HttpClient: Windows PowerShell 5.1 (the
# powershell.exe the deploy cmd runs) does not load System.Net.Http by default,
# and this script must work from both powershell.exe and pwsh.
function FetchFull([string]$Path, [string]$AcceptEncoding) {
    $request = [System.Net.HttpWebRequest]::Create($base + $Path)
    $request.Method = "GET"
    $request.AllowAutoRedirect = $false
    $request.AutomaticDecompression = [System.Net.DecompressionMethods]::None
    $request.Timeout = 120000
    $request.ReadWriteTimeout = 120000
    if ($AcceptEncoding -ne "") {
        $request.Headers.Add("Accept-Encoding", $AcceptEncoding)
    }
    $response = $null
    try {
        $response = $request.GetResponse()
    } catch [System.Net.WebException] {
        if ($null -eq $_.Exception.Response) {
            # DNS/TLS/connection failure is a failed check, not a script crash.
            return [pscustomobject]@{
                Status  = 0
                Headers = @{ "error" = $_.Exception.Message }
                Bytes   = [byte[]]@()
                Body    = ""
            }
        }
        $response = $_.Exception.Response
    }
    $stream = $response.GetResponseStream()
    $buffer = New-Object System.IO.MemoryStream
    try {
        $stream.CopyTo($buffer)
        $bytes = $buffer.ToArray()
    } finally {
        $buffer.Dispose()
        $stream.Dispose()
        $response.Close()
    }
    $headers = @{ }
    foreach ($key in $response.Headers.AllKeys) {
        $headers[$key.ToLowerInvariant()] = $response.Headers[$key]
    }
    return [pscustomobject]@{
        Status  = [int]$response.StatusCode
        Headers = $headers
        Bytes   = $bytes
        Body    = [System.Text.Encoding]::UTF8.GetString($bytes)
    }
}

# --- 1. The release stamp (pointer) ---------------------------------------
$stamp = $null
$attempt = 0
while ($attempt -lt $Retries) {
    $stamp = FetchFull "/version.json" ""
    if ($stamp.Status -eq 200) { break }
    $attempt++
    if ($attempt -lt $Retries) { Start-Sleep -Seconds 10 }
}
Check ($stamp.Status -eq 200) "/version.json is 200 (got $($stamp.Status))"
if ($stamp.Status -eq 200) {
    try { $stampJson = $stamp.Body | ConvertFrom-Json } catch { $stampJson = $null }
    Check ($null -ne $stampJson -and [string]$stampJson.game_version -eq $expected) "/version.json reports game_version $expected"
    Check ($null -ne $stampJson -and [string]$stampJson.build_id -eq $expectedBuild) "/version.json reports the staged build id"
    Check ($stamp.Headers["cache-control"] -match "no-store") "/version.json is no-store"
    Check ($stamp.Headers["content-type"] -match "application/json") "/version.json is application/json"
}

# --- 2. Hosting metadata ---------------------------------------------------
$releaseResponse = FetchFull "/release.json" ""
Check ($releaseResponse.Status -eq 200) "/release.json is 200 (got $($releaseResponse.Status))"
Check ($releaseResponse.Headers["cache-control"] -match "no-store") "/release.json is no-store"

# --- 3. Root entry redirect ------------------------------------------------
$root = FetchFull "/" ""
Check ($root.Status -eq 302 -or $root.Status -eq 301) "root redirects to the release (got $($root.Status))"
if ($root.Status -eq 302 -or $root.Status -eq 301) {
    $location = [string]$root.Headers["location"]
    Check ($location -eq $entry -or $location.EndsWith($entry)) "root Location is the versioned entry ($entry)"
    Check ($root.Headers["cache-control"] -match "no-store") "root redirect is no-store"
}

# --- 4. Entry HTML: no-store + version meta --------------------------------
$html = FetchFull $entry ""
Check ($html.Status -eq 200) "release index.html is 200 (got $($html.Status))"
Check ($html.Headers["cache-control"] -match "no-store") "release index.html is no-store"
Check ($html.Headers["content-type"] -match "text/html") "release index.html is text/html"
Check ($html.Body.Contains('name="cartslop-game-version" content="' + $expected + '"')) "release index.html advertises v$expected"

# --- 5. Immutable payload + cache policy ----------------------------------
$js = FetchFull ($releaseDir + "/index.js") "identity"
Check ($js.Status -eq 200) "index.js is 200 (got $($js.Status))"
Check ($js.Headers["cache-control"] -match "immutable") "index.js is immutable-cached"
Check ($js.Headers["content-type"] -match "javascript") "index.js has a JavaScript content type"

$wasmBr = FetchFull ($releaseDir + "/index.wasm") "br"
Check ($wasmBr.Status -eq 200) "index.wasm (Accept-Encoding: br) is 200 (got $($wasmBr.Status))"
Check ($wasmBr.Headers["content-type"] -match "application/wasm") "index.wasm is application/wasm"
$wasmEncoding = [string]$wasmBr.Headers["content-encoding"]
Check ($wasmEncoding -eq "" -or $wasmEncoding -match "br|gzip") "index.wasm encoding is br/gzip/identity (got '$wasmEncoding')"
if ($wasmEncoding -ne "") {
    Check ($wasmBr.Bytes.Length -lt 20MB) "index.wasm is served compressed ($([math]::Round($wasmBr.Bytes.Length / 1MB, 1)) MB)"
} else {
    Check ($wasmBr.Bytes.Length -gt 30MB) "index.wasm identity size matches the export"
}

$pck = FetchFull ($releaseDir + "/index.pck") "br"
Check ($pck.Status -eq 200) "index.pck is 200 (got $($pck.Status))"
Check ($pck.Headers["content-type"] -match "application/octet-stream") "index.pck is application/octet-stream"

# --- 6. Cross-origin isolation only when threaded -------------------------
$coop = [string]$html.Headers["cross-origin-opener-policy"]
$coep = [string]$html.Headers["cross-origin-embedder-policy"]
if ($ExpectThreaded) {
    Check ($coop -match "same-origin") "threaded build: COOP is enabled"
    Check ($coep -match "require-corp") "threaded build: COEP is enabled"
} else {
    Check ($coop -eq "") "single-threaded build: no COOP header required"
    Check ($coep -eq "") "single-threaded build: no COEP header required"
}

# --- 7. No stale pointer ---------------------------------------------------
Check ($entry.Contains("/" + $expected + "/")) "entry path is versioned by game version"

Write-Host ""
if ($script:fails -gt 0) {
    Write-Host ("WEB DEPLOY VERIFY: " + $script:fails + "/" + $script:checks + " checks FAILED for " + $base) -ForegroundColor Red
    exit $script:fails
}
Write-Host ("WEB DEPLOY VERIFY: " + $script:checks + "/" + $script:checks + " checks passed for " + $base) -ForegroundColor Green
Write-Host "Manual step that remains: open the URL in a real browser (WebGL2) and confirm the game boots." -ForegroundColor Yellow
exit 0
