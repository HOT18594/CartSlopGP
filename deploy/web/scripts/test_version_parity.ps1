# End-to-end version-parity demonstration for the Cart Slop GP Web release.
#
# Runs without network access and without touching the live Pi. It builds small
# fixtures from a real stamped export (hardlinks, so no gigabytes are copied),
# then proves that:
#
#   * the stamped export PASSES pi_setup/sync_web_release.ps1 -Check;
#   * an unstamped, version-mismatched, payload-modified, re-exported or
#     truncated folder FAILS with the loud "WEB RELEASE CHECK FAILED" message;
#   * pi_setup/deploy_server.ps1 refuses a stale folder BEFORE it opens an SSH
#     connection (no network side effect, only a few hundred ms);
#   * pi_setup/Deploy-Server.cmd refuses a stale folder, prints
#     "Nothing was deployed" and exits 1;
#   * web_deploy/scripts/stage_release.ps1 refuses the same stale folder and
#     never creates dist/, while staging the good export succeeds and writes
#     _headers/_redirects/release.json/version.json with the versioned layout.
#
# Usage (from the workspace root):
#   powershell -ExecutionPolicy Bypass -File web_deploy\scripts\test_version_parity.ps1
#   ... -WebDir builds\_ws1_web\export\web -Clean      # remove fixtures afterwards
#
# Exit code = number of failed checks.
param(
    [string]$WebDir = "",
    [string]$ScratchRoot = "",
    [string]$LogPath = "",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$deployRoot = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $deployRoot
$syncScript = Join-Path $repoRoot "pi_setup\sync_web_release.ps1"
$deployServer = Join-Path $repoRoot "pi_setup\deploy_server.ps1"
$deployCmd = Join-Path $repoRoot "pi_setup\Deploy-Server.cmd"
$stageScript = Join-Path $scriptDir "stage_release.ps1"

if ($WebDir -eq "") {
    $candidate = Join-Path $repoRoot "builds\_ws1_web\export\web"
    if (Test-Path -LiteralPath (Join-Path $candidate "version.json")) {
        $WebDir = $candidate
    } else {
        $WebDir = Join-Path $repoRoot "builds\v0.8.7\web"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $WebDir "version.json"))) {
    Write-Host ("PARITY DEMO FAILED: " + $WebDir + " is not a stamped Web export. Run pi_setup\build_0_8_7.ps1 or stamp a scratch export first.") -ForegroundColor Red
    exit 1
}
$WebDir = (Resolve-Path -LiteralPath $WebDir).Path
if ($ScratchRoot -eq "") { $ScratchRoot = Join-Path $repoRoot "builds\_ws1_web\parity" }
$ScratchRoot = [System.IO.Path]::GetFullPath($ScratchRoot)
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null
if ($LogPath -eq "") { $LogPath = Join-Path $repoRoot "builds\_ws1_web\parity-demo.log" }

$powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path -LiteralPath $powershellExe)) { $powershellExe = "powershell" }

# Native commands write expected error text to stderr (the refusal messages this
# demo is looking for). With $ErrorActionPreference = "Stop" that text becomes a
# terminating NativeCommandError, so every capture runs with "Continue" and the
# exit code is what the check looks at.
function Invoke-Captured([scriptblock]$Command) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = (& $Command 2>&1 | Out-String)
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
    } finally {
        $ErrorActionPreference = $previous
    }
}

$script:results = New-Object System.Collections.Generic.List[object]
$script:log = New-Object System.Collections.Generic.List[string]

function Record([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:results.Add([pscustomobject]@{ Name = $Name; Passed = $Passed; Detail = $Detail })
    $script:log.Add("[" + $(if ($Passed) { "PASS" } else { "FAIL" }) + "] " + $Name + " :: " + $Detail)
    if ($Passed) {
        Write-Host ("PASS: " + $Name) -ForegroundColor Green
    } else {
        Write-Host ("FAIL: " + $Name + " :: " + $Detail) -ForegroundColor Red
    }
}

function New-Fixture([string]$Name) {
    $destination = Join-Path $ScratchRoot $Name
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $WebDir -File)) {
        if ($item.Name -eq "version.json") {
            # The stamp is the one file the fixtures deliberately rewrite, so it
            # must be a private copy: a hardlink would make a fixture edit the
            # real exported stamp in place.
            Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $destination $item.Name) -Force
        } else {
            New-Item -ItemType HardLink -Path (Join-Path $destination $item.Name) -Target $item.FullName | Out-Null
        }
    }
    return $destination
}

function Replace-FixtureFile([string]$Fixture, [string]$Name) {
    $target = Join-Path $Fixture $Name
    $source = Join-Path $WebDir $Name
    Remove-Item -LiteralPath $target -Force
    Copy-Item -LiteralPath $source -Destination $target -Force
    return $target
}

function Invoke-SyncCheck([string]$Folder) {
    return Invoke-Captured({
        & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $syncScript -WebDir $Folder -Check
    })
}

Write-Host ""
Write-Host ("== version parity demo (export: " + $WebDir + ") ==") -ForegroundColor Cyan
$stamp = Get-Content -LiteralPath (Join-Path $WebDir "version.json") -Raw | ConvertFrom-Json
Write-Host ("   stamp: v" + $stamp.game_version + " engine " + $stamp.engine_version + " build " + ([string]$stamp.build_id).Substring(0, 12)) -ForegroundColor DarkGray

# --- Good fixture: passes the check --------------------------------------
$good = New-Fixture "ok"
$result = Invoke-SyncCheck $good
Record "stamped export passes -Check" ($result.Code -eq 0 -and $result.Output -match "WEB RELEASE CHECK OK") $result.Output.Trim()

# --- Unstamped folder -----------------------------------------------------
$unstamped = New-Fixture "unstamped"
Remove-Item -LiteralPath (Join-Path $unstamped "version.json") -Force
$result = Invoke-SyncCheck $unstamped
Record "unstamped export is refused" ($result.Code -ne 0 -and $result.Output -match "no version\.json") $result.Output.Trim()

# --- Stale version in the stamp ------------------------------------------
$stale = New-Fixture "stale-version"
$staleJson = Join-Path $stale "version.json"
$staleText = (Get-Content -LiteralPath $staleJson -Raw) -replace ('"game_version":\s*"' + [regex]::Escape([string]$stamp.game_version) + '"'), '"game_version":  "0.8.6"'
[System.IO.File]::WriteAllText($staleJson, $staleText, (New-Object System.Text.UTF8Encoding($false)))
$result = Invoke-SyncCheck $stale
Record "stale version (0.8.6 stamp on a 0.8.7 project) is refused loudly" ($result.Code -ne 0 -and $result.Output -match "STALE WEB BUILD") $result.Output.Trim()

# --- Payload modified after the stamp ------------------------------------
$mixed = New-Fixture "mixed-payload"
$wasm = Replace-FixtureFile $mixed "index.wasm"
$stream = [System.IO.File]::Open($wasm, [System.IO.FileMode]::Append)
$stream.WriteByte(0)
$stream.Dispose()
$result = Invoke-SyncCheck $mixed
Record "payload modified after the stamp is refused" ($result.Code -ne 0 -and $result.Output -match "version\.json says") $result.Output.Trim()

# --- File re-exported after the stamp ------------------------------------
$reexported = New-Fixture "reexported-after-stamp"
$js = Replace-FixtureFile $reexported "index.js"
[System.IO.File]::SetLastWriteTimeUtc($js, [DateTime]::UtcNow.AddSeconds(60))
$result = Invoke-SyncCheck $reexported
Record "folder re-exported after the stamp is refused" ($result.Code -ne 0 -and $result.Output -match "newer than version\.json") $result.Output.Trim()

# --- Missing file ---------------------------------------------------------
$missing = New-Fixture "missing-file"
Remove-Item -LiteralPath (Join-Path $missing "index.png") -Force
$result = Invoke-SyncCheck $missing
Record "export with a removed file is refused" ($result.Code -ne 0 -and $result.Output -match "version\.json stamps") $result.Output.Trim()

# --- Wrong schema ---------------------------------------------------------
$schema = New-Fixture "wrong-schema"
$schemaJson = Join-Path $schema "version.json"
$schemaText = (Get-Content -LiteralPath $schemaJson -Raw) -replace '"cartslop\.web_release/1"', '"cartslop.web_release/999"'
[System.IO.File]::WriteAllText($schemaJson, $schemaText, (New-Object System.Text.UTF8Encoding($false)))
$result = Invoke-SyncCheck $schema
Record "unknown version.json schema is refused" ($result.Code -ne 0 -and $result.Output -match "schema is") $result.Output.Trim()

# --- Deploy path: deploy_server.ps1 refuses before any SSH ----------------
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$deploy = Invoke-Captured({
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $deployServer -WebDir $stale -PiHost "192.0.2.1" -Version ([string]$stamp.game_version)
})
$stopwatch.Stop()
$deployCode = $deploy.Code
$deployOutput = $deploy.Output
$fastFail = $stopwatch.Elapsed.TotalSeconds -lt 15
Record "deploy_server.ps1 refuses a stale web folder before SSH" ($deployCode -ne 0 -and $deployOutput -match "web build version check failed" -and $fastFail) ("exit " + $deployCode + ", " + [math]::Round($stopwatch.Elapsed.TotalSeconds, 2) + " s, no SSH attempted: " + ($deployOutput.Trim() -replace "`r?`n", " | "))

# --- Deploy path: Deploy-Server.cmd refuses and does not deploy -----------
$env:CARTSLOP_WEB_DIR = $stale
$env:CARTSLOP_NO_PAUSE = "1"
try {
    $cmd = Invoke-Captured({ & cmd.exe /c "`"$deployCmd`"" })
    $cmdCode = $cmd.Code
    $cmdOutput = $cmd.Output
} finally {
    Remove-Item Env:\CARTSLOP_WEB_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:\CARTSLOP_NO_PAUSE -ErrorAction SilentlyContinue
}
Record "Deploy-Server.cmd refuses a stale web folder (exit 1, nothing deployed)" ($cmdCode -eq 1 -and $cmdOutput -match "WEB VERSION CHECK FAILED" -and $cmdOutput -match "Nothing was deployed") ("exit " + $cmdCode + ": " + ($cmdOutput.Trim() -replace "`r?`n", " | "))

# --- Stager refuses the stale folder and writes nothing -------------------
$stageOut = Join-Path $ScratchRoot "dist-refused"
if (Test-Path -LiteralPath $stageOut) { Remove-Item -LiteralPath $stageOut -Recurse -Force }
$stageOutput = Invoke-Captured({
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $stageScript -WebDir $stale -OutDir $stageOut
})
$stageCode = $stageOutput.Code
$stageText = $stageOutput.Output
Record "stage_release.ps1 refuses a stale folder and creates no dist" ($stageCode -ne 0 -and $stageText -match "did not pass the version check" -and -not (Test-Path -LiteralPath $stageOut)) ("exit " + $stageCode + ": " + ($stageText.Trim() -replace "`r?`n", " | "))

# --- Stager stages the good export with the versioned layout --------------
$stageGood = Join-Path $ScratchRoot "dist-staged"
if (Test-Path -LiteralPath $stageGood) { Remove-Item -LiteralPath $stageGood -Recurse -Force }
$stageGoodResult = Invoke-Captured({
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $stageScript -WebDir $good -OutDir $stageGood -Force
})
$stageGoodCode = $stageGoodResult.Code
$stageGoodOutput = $stageGoodResult.Output
$buildShort = ([string]$stamp.build_id).Substring(0, 12)
$releaseDir = Join-Path $stageGood ("game\" + $stamp.game_version + "\" + $buildShort)
$headersPath = Join-Path $stageGood "_headers"
$redirectsPath = Join-Path $stageGood "_redirects"
$goodStaged = ($stageGoodCode -eq 0)
if ($goodStaged) {
    $goodStaged = (Test-Path -LiteralPath (Join-Path $releaseDir "index.html")) -and
                  (Test-Path -LiteralPath (Join-Path $stageGood "version.json")) -and
                  (Test-Path -LiteralPath (Join-Path $stageGood "release.json")) -and
                  (Test-Path -LiteralPath $headersPath) -and
                  (Test-Path -LiteralPath $redirectsPath)
}
if ($goodStaged) {
    $headersText = Get-Content -LiteralPath $headersPath -Raw
    $redirectsText = Get-Content -LiteralPath $redirectsPath -Raw
    $releaseJson = Get-Content -LiteralPath (Join-Path $stageGood "release.json") -Raw | ConvertFrom-Json
    $goodStaged = ($headersText -match "immutable") -and
                  ($headersText -match "no-store") -and
                  ($headersText -match [regex]::Escape("/game/" + $stamp.game_version + "/" + $buildShort)) -and
                  ($redirectsText -match [regex]::Escape("/game/" + $stamp.game_version + "/" + $buildShort + "/index.html")) -and
                  ([string]$releaseJson.build_id -eq [string]$stamp.build_id)
}
Record "stage_release.ps1 stages the current export into /game/<version>/<build>/" ($goodStaged -and $stageGoodCode -eq 0) (($stageGoodOutput.Trim() -replace "`r?`n", " | ") + " [headers immutable+no-store, redirects to versioned entry, release.json build_id matches]")

$script:log.Add("")
foreach ($result in $script:results) {
    $script:log.Add(("RESULT " + $(if ($result.Passed) { "PASS" } else { "FAIL" }) + " " + $result.Name))
}
$failures = @($script:results | Where-Object { -not $_.Passed }).Count
$script:log.Add("PARITY DEMO: " + ($script:results.Count - $failures) + "/" + $script:results.Count + " checks passed")
[System.IO.File]::WriteAllText($LogPath, ($script:log -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host ""
Write-Host ("PARITY DEMO: " + ($script:results.Count - $failures) + "/" + $script:results.Count + " checks passed (log: " + $LogPath + ")") -ForegroundColor $(if ($failures -gt 0) { "Red" } else { "Green" })
if ($Clean) {
    foreach ($name in @("ok", "unstamped", "stale-version", "mixed-payload", "reexported-after-stamp", "missing-file", "wrong-schema", "dist-refused", "dist-staged")) {
        $path = Join-Path $ScratchRoot $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    }
}
exit $failures
