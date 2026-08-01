$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = if ($args.Count -gt 0) { $args[0] } else { Join-Path $Root "final-run" }
if (-not [System.IO.Path]::IsPathRooted($Target)) { $Target = Join-Path $Root $Target }
$Reference = Join-Path $Root "results/reference"
$Expected = "6a7a4489ec40fa8223c9c3aac831a46c4eaa810654a35af0a537cf6b04fb2eed"
$Par = Join-Path $Target "final.par"
if (-not (Test-Path $Par)) { throw "Missing fitted PAR: $Par" }
$Observed = (Get-FileHash -Algorithm SHA256 $Par).Hash.ToLowerInvariant()
if ($Observed -ne $Expected) {
  throw "The archived Hessian belongs to another final PAR. Expected $Expected; observed $Observed"
}
$TargetHessian = Join-Path $Target "hessian"
if ((Test-Path $TargetHessian) -and (Get-ChildItem -Force $TargetHessian | Select-Object -First 1)) {
  throw "Hessian directory is not empty: $TargetHessian"
}
New-Item -ItemType Directory -Force -Path $TargetHessian | Out-Null
Copy-Item -Recurse -Force (Join-Path $Reference "hessian/*") $TargetHessian
Copy-Item -Force (Join-Path $Reference "model_payload.rds") $Target
Copy-Item -Force (Join-Path $Reference "model_payload_manifest.csv") $Target
Copy-Item -Force (Join-Path $Reference "model_payload_manifest.json") $Target
Write-Host "Archived full Hessian and compact diagnostic payload restored to: $Target"
