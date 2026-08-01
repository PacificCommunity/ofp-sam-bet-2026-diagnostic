$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunDir = if ($env:RUN_DIR) { $env:RUN_DIR } else { Join-Path $Root "run" }
if (-not [System.IO.Path]::IsPathRooted($RunDir)) { $RunDir = Join-Path $Root $RunDir }
if ((Test-Path $RunDir) -and (Get-ChildItem -Force $RunDir | Select-Object -First 1)) {
  throw "Run directory is not empty: $RunDir. Set RUN_DIR to a fresh directory."
}
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$Image = "ghcr.io/pacificcommunity/tuna-flow:v2.5@sha256:c87f1f6d9d4f62dc447844b58afe35f96af175bf933cb6cffbbbe39a59172360"
docker run --rm --entrypoint /bin/bash `
  --mount "type=bind,src=$Root,dst=/repo,readonly" `
  --mount "type=bind,src=$RunDir,dst=/work" `
  --workdir /work -e REPO_ROOT=/repo -e RUN_DIR=/work `
  -e PROGRAM_PATH=/home/mfcl/mfclo64 `
  $Image /repo/scripts/container-run fit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
