param(
  [string]$OutDir = "release"
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptRoot '..')
Set-Location $projectRoot

$addon = "GuildRecruiter"
$tocPath = Join-Path $addon "GuildRecruiter.toc"
if (-not (Test-Path $tocPath)) { throw "TOC file not found: $tocPath" }

$versionLine = (Get-Content $tocPath | Where-Object { $_ -match '##\s*Version:' } | Select-Object -First 1)
$version = if ($versionLine) { ($versionLine -replace '.*Version:\s*','').Trim() } else { '0.0.0' }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zip = Join-Path $OutDir ("$addon-v$version.zip")
if (Test-Path $zip) { Remove-Item $zip -Force }

$excludePatterns = @(
  'Collections/Examples.lua',
  'Showcase.lua',
  '*.bak', '*.tmp', '*.log', '*.zip',
  'release',
  '.git', '.gitignore'
)

# Gather files
$all = Get-ChildItem -Recurse $addon | Where-Object { -not $_.PSIsContainer }
$files = @()
foreach ($f in $all) {
  $rel = $f.FullName.Substring($projectRoot.Path.Length + 1) -replace '\\','/'
  $skip = $false
  foreach ($pat in $excludePatterns) { if ($rel -like $pat) { $skip = $true; break } }
  if (-not $skip) { $files += $f.FullName }
}

if ($files.Count -eq 0) { throw "No files selected for packaging." }

Compress-Archive -Path $files -DestinationPath $zip -CompressionLevel Optimal
Write-Host "Created: $zip" -ForegroundColor Cyan
