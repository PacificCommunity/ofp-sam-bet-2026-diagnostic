$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = if ($args.Count -gt 0) { $args[0] } else { Join-Path $Root "final-run" }
if (-not [System.IO.Path]::IsPathRooted($Target)) { $Target = Join-Path $Root $Target }
$Reference = Join-Path $Root "results/reference"
$Expected = "21dcaea9db8c89ddc8c29fa3c3a5e514b50bef6e26587c168c00c05f35fbebc3"
$Par = Join-Path $Target "final.par"
if (-not (Test-Path $Par)) { throw "Missing fitted PAR: $Par" }
$Observed = (Get-FileHash -Algorithm SHA256 $Par).Hash.ToLowerInvariant()
if ($Observed -ne $Expected) {
  throw "The archived Hessian diagnostics belong to another final PAR. Expected $Expected; observed $Observed"
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
Write-Host "Archived Hessian diagnostics and compact diagnostic payload restored to: $Target"
