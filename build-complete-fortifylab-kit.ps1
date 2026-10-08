# build-complete-fortifylab-kit.ps1

$ErrorActionPreference = "Stop"

$RepoRoot = (Get-Location).Path

Write-Host ""
Write-Host "========================================="
Write-Host " Fortify Complete Build Kit Generator"
Write-Host "========================================="
Write-Host ""

# --------------------------------------------------
# Rename base package if necessary
# --------------------------------------------------

if (
    (Test-Path "$RepoRoot\fortify-lab-toolkit") -and
    !(Test-Path "$RepoRoot\fortify-lab-toolkit-v7")
)
{
    Write-Host "Renaming fortify-lab-toolkit -> fortify-lab-toolkit-v7"
    Rename-Item `
        "$RepoRoot\fortify-lab-toolkit" `
        "fortify-lab-toolkit-v7"
}

# --------------------------------------------------
# Validate required directories
# --------------------------------------------------

$RequiredDirs = @(
    "fortify-lab-toolkit-v7",
    "fortify-github-addon-v8",
    "fortify-recovery-addon-v9",
    "fortify-validation-addon-v10",
    "fortify-guided-lifecycle-addon-v11"
)

foreach ($dir in $RequiredDirs)
{
    if (!(Test-Path "$RepoRoot\$dir"))
    {
        throw "Required directory missing: $dir"
    }
}

# --------------------------------------------------
# Locate builder
# --------------------------------------------------

$BuilderRoot = "$RepoRoot\fortifylab\fortifylab"

if (!(Test-Path "$BuilderRoot\build-v12.sh"))
{
    throw "Cannot locate build-v12.sh under $BuilderRoot"
}

Write-Host ""
Write-Host "Builder:"
Write-Host "  $BuilderRoot"

# --------------------------------------------------
# Cleanup
# --------------------------------------------------

$CompleteDir = "$RepoRoot\fortifylab-complete"

Remove-Item $CompleteDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$RepoRoot\fortifylab-complete.zip" -Force -ErrorAction SilentlyContinue
Remove-Item "$RepoRoot\fortifylab-complete.tar.gz" -Force -ErrorAction SilentlyContinue
Remove-Item "$RepoRoot\SHA256SUMS.txt" -Force -ErrorAction SilentlyContinue

# --------------------------------------------------
# Build package archives
# --------------------------------------------------

Write-Host ""
Write-Host "Creating package archives..."

$Packages = @(
    "fortify-lab-toolkit-v7",
    "fortify-github-addon-v8",
    "fortify-recovery-addon-v9",
    "fortify-validation-addon-v10",
    "fortify-guided-lifecycle-addon-v11"
)

foreach ($pkg in $Packages)
{
    $Archive = "$RepoRoot\$pkg.tar.gz"

    Remove-Item $Archive -Force -ErrorAction SilentlyContinue

    Write-Host "  $pkg"

    tar -czf $Archive $pkg

    if (!(Test-Path $Archive))
    {
        throw "Failed creating archive: $Archive"
    }
}

# --------------------------------------------------
# Create complete kit directory
# --------------------------------------------------

Write-Host ""
Write-Host "Creating complete kit..."

New-Item `
    -ItemType Directory `
    -Path $CompleteDir `
    | Out-Null

Copy-Item `
    "$BuilderRoot\*" `
    $CompleteDir `
    -Recurse

foreach ($pkg in $Packages)
{
    Copy-Item `
      "$RepoRoot\$pkg.tar.gz" `
      $CompleteDir
}

# --------------------------------------------------
# Create distributables
# --------------------------------------------------

Write-Host ""
Write-Host "Creating final archives..."

Push-Location $RepoRoot

tar -czf `
    fortifylab-complete.tar.gz `
    fortifylab-complete

Compress-Archive `
    -Path fortifylab-complete `
    -DestinationPath fortifylab-complete.zip `
    -Force

Pop-Location

# --------------------------------------------------
# SHA256
# --------------------------------------------------

Get-FileHash `
    "$RepoRoot\fortifylab-complete.tar.gz" `
    -Algorithm SHA256 |
    Format-Table -HideTableHeaders Path,Hash |
    Out-File "$RepoRoot\SHA256SUMS.txt"

Get-FileHash `
    "$RepoRoot\fortifylab-complete.zip" `
    -Algorithm SHA256 |
    Format-Table -HideTableHeaders Path,Hash |
    Out-File "$RepoRoot\SHA256SUMS.txt" `
    -Append

# --------------------------------------------------
# Report
# --------------------------------------------------

Write-Host ""
Write-Host "========================================="
Write-Host " COMPLETE BUILD KIT GENERATED"
Write-Host "========================================="
Write-Host ""

Write-Host "Generated:"

Write-Host "  fortifylab-complete.tar.gz"
Write-Host "  fortifylab-complete.zip"
Write-Host "  SHA256SUMS.txt"

Write-Host ""
Write-Host "Ready to deploy:"
Write-Host ""
Write-Host "  tar -xzf fortifylab-complete.tar.gz"
Write-Host "  cd fortifylab-complete"
Write-Host "  ./build-v12.sh"
Write-Host ""