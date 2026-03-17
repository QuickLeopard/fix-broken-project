# compare.ps1 — run baseline bench for slow and optimized variants, save results.
#
# Usage:
#   .\scripts\compare.ps1 [-Variant slow|optimized|both]   (default: both)
#
# Output: broken-app\artifacts\
#   baseline_slow.txt
#   baseline_optimized.txt

param(
    [ValidateSet('slow', 'optimized', 'both')]
    [string]$Variant = 'both'
)

$ErrorActionPreference = 'Stop'

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir   = Split-Path -Parent $ScriptDir
$ArtifactsDir = Join-Path $ProjectDir 'artifacts'

New-Item -ItemType Directory -Force -Path $ArtifactsDir | Out-Null

function Run-Bench {
    param(
        [string]$Features,
        [string]$Label
    )

    $OutFile = Join-Path $ArtifactsDir "baseline_${Label}.txt"
    Write-Host "--> cargo bench --bench baseline $Features"

    Push-Location $ProjectDir
    try {
        $result = cargo bench --bench baseline $Features.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) 2>&1
        if ($LASTEXITCODE -ne 0) { throw "cargo bench failed for $Label" }
        $result | Tee-Object -FilePath $OutFile
    } finally {
        Pop-Location
    }

    Write-Host "    saved -> artifacts\baseline_${Label}.txt"
}

switch ($Variant) {
    'slow'      { Run-Bench -Features ''                    -Label 'slow'      }
    'optimized' { Run-Bench -Features '--features optimized' -Label 'optimized' }
    'both'      {
        Run-Bench -Features ''                    -Label 'slow'
        Run-Bench -Features '--features optimized' -Label 'optimized'
    }
}

# ── side-by-side diff if both files exist ──────────────────────────────────────
$slowFile = Join-Path $ArtifactsDir 'baseline_slow.txt'
$optFile  = Join-Path $ArtifactsDir 'baseline_optimized.txt'

if ((Test-Path $slowFile) -and (Test-Path $optFile)) {
    Write-Host ""
    Write-Host "==> Comparison (slow vs optimized):"

    $slow = Get-Content $slowFile | Where-Object { $_ -match '(slow|optimized|sum|dedup|fib)' }
    $opt  = Get-Content $optFile  | Where-Object { $_ -match '(slow|optimized|sum|dedup|fib)' }

    $maxLen = [Math]::Max($slow.Count, $opt.Count)
    $col    = 55

    Write-Host ("{0,-$col}  {1}" -f 'SLOW', 'OPTIMIZED')
    Write-Host ("{0,-$col}  {1}" -f ('─' * $col), ('─' * $col))

    for ($i = 0; $i -lt $maxLen; $i++) {
        $l = if ($i -lt $slow.Count) { $slow[$i] } else { '' }
        $r = if ($i -lt $opt.Count)  { $opt[$i]  } else { '' }
        Write-Host ("{0,-$col}  {1}" -f $l, $r)
    }
}

Write-Host ""
Write-Host "==> Done. Artifacts in: $ArtifactsDir"
