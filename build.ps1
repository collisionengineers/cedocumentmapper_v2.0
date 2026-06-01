param(
    [switch]$SkipTests,
    [switch]$SkipFrontend,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RepoRoot

if ($Clean) {
    Remove-Item -LiteralPath (Join-Path $RepoRoot "build") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $RepoRoot "dist") -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Installing Python dependencies..."
python -m pip install -r requirements-dev.txt

if (-not $SkipFrontend) {
    Write-Host "Building frontend..."
    Push-Location (Join-Path $RepoRoot "frontend")
    try {
        if (Test-Path "package-lock.json") {
            npm ci
        } else {
            npm install
        }
        npm run build
    } finally {
        Pop-Location
    }
}

if (-not $SkipTests) {
    Write-Host "Running tests..."
    python -m pytest
}

function Find-TesseractDir {
    if ($env:CEDOCUMENTMAPPER_TESSERACT_DIR -and (Test-Path (Join-Path $env:CEDOCUMENTMAPPER_TESSERACT_DIR "tesseract.exe"))) {
        return (Resolve-Path $env:CEDOCUMENTMAPPER_TESSERACT_DIR).Path
    }

    $command = Get-Command "tesseract.exe" -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        return (Split-Path -Parent $command.Source)
    }

    $candidates = @()
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "Tesseract-OCR")
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Tesseract-OCR")
    }

    foreach ($candidate in $candidates) {
        if (Test-Path (Join-Path $candidate "tesseract.exe")) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

$PyInstallerArgs = @(
    "--noconfirm",
    "--clean",
    "--windowed",
    "--paths", "src",
    "--name", "CE-Document-Mapper",
    "--icon", "ce_document_mapper.ico",
    "--add-data", "providers.json;.",
    "--add-data", "frontend/dist;frontend/dist"
)

$TesseractDir = Find-TesseractDir
if ($TesseractDir) {
    Write-Host "Bundling Tesseract from: $TesseractDir"
    $PyInstallerArgs += @("--add-data", "$TesseractDir;tesseract")
} else {
    Write-Warning "Tesseract was not found; OCR will require system Tesseract or CEDOCUMENTMAPPER_TESSERACT_DIR."
}

$PyInstallerArgs += "app.py"

Write-Host "Building Windows executable..."
python -m PyInstaller @PyInstallerArgs

$ExePath = Join-Path $RepoRoot "dist\CE-Document-Mapper\CE-Document-Mapper.exe"
if (-not (Test-Path $ExePath)) {
    throw "Expected executable was not created: $ExePath"
}

Write-Host "Built executable: $ExePath"
