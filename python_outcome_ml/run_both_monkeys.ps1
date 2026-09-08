param(
    [int]$Jobs = -1,
    [int]$SearchVerbose = 2
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $scriptDir
$python = Join-Path $scriptDir '.venv\Scripts\python.exe'
$logDir = Join-Path $scriptDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = Join-Path $logDir "windows_both_$stamp.log"

if (-not (Test-Path -LiteralPath $python)) {
    throw "Missing virtual environment. See README.md for setup."
}

$env:PYTHONUNBUFFERED = '1'
$env:OMP_NUM_THREADS = '1'
$env:MKL_NUM_THREADS = '1'
$env:OPENBLAS_NUM_THREADS = '1'
$env:NUMEXPR_NUM_THREADS = '1'

Write-Host "Progress log: $logFile"
& $python -u (Join-Path $scriptDir 'run_outcome_ml.py') `
    (Join-Path $projectDir 'respFocusSaccRa\respFeaturesRa.mat') `
    --variable respFeaturesRa --monkey Ra `
    --n-jobs $Jobs --search-verbose $SearchVerbose `
    --use-existing-cache 2>&1 | Tee-Object -FilePath $logFile -Append
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $python -u (Join-Path $scriptDir 'run_outcome_ml.py') `
    (Join-Path $projectDir 'respFocusSaccAb\respFeaturesAb.mat') `
    --variable respFeaturesAb --monkey Ab `
    --n-jobs $Jobs --search-verbose $SearchVerbose `
    --use-existing-cache 2>&1 | Tee-Object -FilePath $logFile -Append
exit $LASTEXITCODE
