$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

python -m pip install -U pip
python -m pip install ".[build]"
python -m PyInstaller --noconfirm --clean packaging/pfc.spec

Write-Host "产物目录: $Root\dist\PFC"
