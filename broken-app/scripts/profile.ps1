# profile.ps1 — flamegraph + massif for slow and optimized variants.
# Runs inside Docker (perf + valgrind not available on Windows).
#
# Usage:
#   .\scripts\profile.ps1 [-Variant slow|optimized|both]   (default: both)
#
# Output: broken-app\artifacts\
#   flamegraph_<variant>.svg
#   massif_<variant>.out
#   massif_<variant>.txt   (ms_print summary)

param(
    [ValidateSet('slow', 'optimized', 'both')]
    [string]$Variant = 'both'
)

$ErrorActionPreference = 'Stop'

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir  = Split-Path -Parent $ScriptDir
$ArtifactsDir = Join-Path $ProjectDir 'artifacts'
$Image  = 'broken-app-profile'
$Volume = 'broken-app-profile-vol'

New-Item -ItemType Directory -Force -Path $ArtifactsDir | Out-Null

# ── helpers ────────────────────────────────────────────────────────────────────

function Build-Image {
    Write-Host "==> Building Docker image: $Image"
    docker build -t $Image $ProjectDir
    if ($LASTEXITCODE -ne 0) { throw "docker build failed" }
}

function Ensure-Volume {
    $exists = docker volume inspect $Volume 2>$null
    if ($LASTEXITCODE -ne 0) {
        docker volume create $Volume | Out-Null
    }
}

function Run-Profile {
    param(
        [string]$Features,   # "" or "--features optimized"
        [string]$Label       # "slow" or "optimized"
    )

    Write-Host ""
    Write-Host "══════════════════════════════════════════"
    Write-Host "  Profiling variant: $Label"
    Write-Host "══════════════════════════════════════════"

    # ── build release binary ────────────────────────────────────────────────
    Write-Host "--> cargo build --release $Features"
    docker run --rm `
        --privileged `
        -v "${Volume}:/app/target" `
        $Image `
        bash -c "set -euo pipefail && cargo build --release $Features"
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed for $Label" }

    # ── flamegraph ──────────────────────────────────────────────────────────
    Write-Host "--> flamegraph ($Label)"
    docker run --rm `
        --privileged `
        -v "${Volume}:/app/target" `
        $Image `
        bash -c @"
set -euo pipefail
echo -1 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true
cargo flamegraph --release $Features --bin demo --output /tmp/flamegraph_${Label}.svg
cp /tmp/flamegraph_${Label}.svg /app/target/flamegraph_${Label}.svg
"@
    if ($LASTEXITCODE -ne 0) { throw "flamegraph failed for $Label" }

    # ── massif ──────────────────────────────────────────────────────────────
    Write-Host "--> massif ($Label)"
    docker run --rm `
        --privileged `
        -v "${Volume}:/app/target" `
        $Image `
        bash -c @"
set -euo pipefail
valgrind --tool=massif \
    --massif-out-file=/app/target/massif_${Label}.out \
    ./target/release/demo
ms_print /app/target/massif_${Label}.out > /app/target/massif_${Label}.txt
"@
    if ($LASTEXITCODE -ne 0) { throw "massif failed for $Label" }

    # ── extract artifacts ───────────────────────────────────────────────────
    Write-Host "--> extracting artifacts"
    $TmpCtr = (docker create -v "${Volume}:/app/target" $Image true).Trim()
    try {
        docker cp "${TmpCtr}:/app/target/flamegraph_${Label}.svg" "$ArtifactsDir\flamegraph_${Label}.svg"
        docker cp "${TmpCtr}:/app/target/massif_${Label}.out"     "$ArtifactsDir\massif_${Label}.out"
        docker cp "${TmpCtr}:/app/target/massif_${Label}.txt"     "$ArtifactsDir\massif_${Label}.txt"
    } finally {
        docker rm $TmpCtr | Out-Null
    }

    Write-Host "    flamegraph -> artifacts\flamegraph_${Label}.svg"
    Write-Host "    massif     -> artifacts\massif_${Label}.out"
    Write-Host "    ms_print   -> artifacts\massif_${Label}.txt"
}

# ── main ───────────────────────────────────────────────────────────────────────

Build-Image
Ensure-Volume

switch ($Variant) {
    'slow'      { Run-Profile -Features ''                    -Label 'slow'      }
    'optimized' { Run-Profile -Features '--features optimized' -Label 'optimized' }
    'both'      {
        Run-Profile -Features ''                    -Label 'slow'
        Run-Profile -Features '--features optimized' -Label 'optimized'
    }
}

Write-Host ""
Write-Host "==> Done. Artifacts in: $ArtifactsDir"
Get-ChildItem -Path $ArtifactsDir -Include 'flamegraph_*.svg','massif_*.txt' -File |
    Select-Object Name, @{N='Size';E={'{0:N0} bytes' -f $_.Length}} |
    Format-Table -AutoSize
