# Install Git first: https://git-scm.com/download/win
# First time only, set your name (once):
#   git config --global user.email "you@example.com"
#   git config --global user.name "Your Name"
# Run from this folder:
#   powershell -ExecutionPolicy Bypass -File push-to-github.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$remote = "https://github.com/martingamedev8/Pixel-game.git"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Install Git for Windows: https://git-scm.com/download/win" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path ".git")) {
    git init
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

git add .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$pending = git status --porcelain
if ([string]::IsNullOrWhiteSpace($pending)) {
    Write-Host "Nothing new to commit."
} else {
    git commit -m "Pixel game project"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

git branch -M main
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$originUrl = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($originUrl)) {
    git remote add origin $remote
} else {
    git remote set-url origin $remote
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Pushing to $remote ..." -ForegroundColor Cyan
git push -u origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "If GitHub created a README, run:" -ForegroundColor Yellow
    Write-Host "  git pull origin main --rebase --allow-unrelated-histories" -ForegroundColor Yellow
    Write-Host "  git push -u origin main" -ForegroundColor Yellow
    exit $LASTEXITCODE
}

Write-Host "Done." -ForegroundColor Green
