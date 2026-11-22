[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$KitRoot = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.Generic.List[string]

function Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message"
    $Failures.Add($Message)
}

$requiredFiles = @(
    "README.md",
    "CODEX_SETUP_PROMPT.md",
    "AGENTS.md",
    "PI_PLAYBOOK.md",
    "INSTALL_PROMPT.md",
    "MIGRATION_GUIDE.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "CHANGELOG.md",
    "VERSION",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "config\codex-pi-mcp.example.toml",
    "config\pi-agent-models.example.json",
    "config\pi-agent-settings.example.json",
    "mcp\pi-delegate-mcp-launcher.mjs",
    "scripts\install.ps1",
    "scripts\configure-provider.ps1",
    "scripts\verify.ps1"
)

foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $KitRoot $relativePath
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        Pass "Required file: $relativePath"
    }
    else {
        Fail "Missing file: $relativePath"
    }
}

foreach ($scriptPath in Get-ChildItem -Path (Join-Path $KitRoot "scripts") -Filter "*.ps1") {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    if ($errors.Count -eq 0) {
        Pass "PowerShell syntax: $($scriptPath.Name)"
    }
    else {
        Fail "PowerShell syntax: $($scriptPath.Name): $($errors[0].Message)"
    }
}

$jsonFiles = @(
    (Join-Path $KitRoot "config\pi-agent-models.example.json"),
    (Join-Path $KitRoot "config\pi-agent-settings.example.json")
)
foreach ($jsonPath in $jsonFiles) {
    try {
        [System.IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json | Out-Null
        Pass "JSON parses: $($jsonPath.Substring($KitRoot.Length + 1))"
    }
    catch {
        Fail "JSON parse failed: $jsonPath"
    }
}

$agentsPath = Join-Path $KitRoot "AGENTS.md"
if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
    $agents = [System.IO.File]::ReadAllText($agentsPath)
    if ($agents.Contains("CODEX_PI_KIT:BEGIN") -and $agents.Contains("CODEX_PI_KIT:END")) {
        Pass "AGENTS.md markers"
    }
    else {
        Fail "AGENTS.md markers"
    }
}

$launcherPath = Join-Path $KitRoot "mcp\pi-delegate-mcp-launcher.mjs"
$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
if ($null -ne $nodeCommand) {
    & $nodeCommand.Source --check $launcherPath
    if ($LASTEXITCODE -eq 0) {
        Pass "MCP launcher syntax"
    }
    else {
        Fail "MCP launcher syntax"
    }
}
else {
    Fail "node.exe is required to validate launcher syntax"
}

Write-Host ""
Write-Host ("Validation summary: {0} failure(s)." -f $Failures.Count)
if ($Failures.Count -gt 0) {
    throw "Kit validation failed."
}

Write-Host "Kit validation passed."
