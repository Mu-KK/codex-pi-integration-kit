[CmdletBinding()]
param(
    [string]$InstallDir = "",
    [string]$CodexHome = "",
    [string]$AgentHome = "",
    [switch]$RunSmoke,
    [string]$SmokeCwd = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$Failures = New-Object System.Collections.Generic.List[string]
$Warnings = New-Object System.Collections.Generic.List[string]

function Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message"
    $Warnings.Add($Message)
}

function Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message"
    $Failures.Add($Message)
}

function Get-PackageVersion {
    param([string]$PackageRoot)
    $packageJson = Join-Path $PackageRoot "package.json"
    if (-not (Test-Path -LiteralPath $packageJson -PathType Leaf)) {
        return $null
    }
    return (([System.IO.File]::ReadAllText($packageJson) | ConvertFrom-Json).version)
}

$homePath = [Environment]::GetFolderPath("UserProfile")
$localAppData = [Environment]::GetFolderPath("LocalApplicationData")
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $localAppData "CodexPi"
}
if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $homePath ".codex" }
}
if ([string]::IsNullOrWhiteSpace($AgentHome)) {
    $AgentHome = if ($env:PI_CODING_AGENT_DIR) {
        $env:PI_CODING_AGENT_DIR
    }
    else {
        Join-Path $homePath ".pi\agent"
    }
}

$reportPath = Join-Path $InstallDir "install-report.json"
$pathsPath = Join-Path $CodexHome "mcp\pi-delegate-paths.json"
$launcherPath = Join-Path $CodexHome "mcp\pi-delegate-mcp-launcher.mjs"
$configPath = Join-Path $CodexHome "config.toml"
$agentsPath = Join-Path $CodexHome "AGENTS.md"
$playbookPath = Join-Path $CodexHome "PI_PLAYBOOK.md"

if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
    Pass "Install report exists: $reportPath"
}
else {
    Warn "Install report not found: $reportPath"
}

if (Test-Path -LiteralPath $pathsPath -PathType Leaf) {
    try {
        $paths = [System.IO.File]::ReadAllText($pathsPath) | ConvertFrom-Json
        $nodeExe = $paths.nodeExe
        $sdkRoot = $paths.sdkRoot
        $delegateRoot = $paths.delegateRoot
        $npmGlobalPrefix = $paths.npmGlobalPrefix
        Pass "Package path table parses: $pathsPath"
    }
    catch {
        Fail "Package path table is invalid: $pathsPath"
        $paths = $null
    }
}
else {
    Fail "Package path table missing: $pathsPath"
    $paths = $null
}

if ($null -ne $paths) {
    if (Test-Path -LiteralPath $nodeExe -PathType Leaf) {
        $nodeVersionText = (& $nodeExe --version).Trim()
        if ($nodeVersionText -match "^v?(\d+)\.(\d+)\.(\d+)") {
            $nodeVersion = [version]("{0}.{1}.{2}" -f $Matches[1], $Matches[2], $Matches[3])
            if ($nodeVersion -ge [version]"22.19.0") {
                Pass "Node.js version: $nodeVersion"
            }
            else {
                Fail "Node.js version is too old: $nodeVersion"
            }
        }
        else {
            Fail "Could not parse Node.js version: $nodeVersionText"
        }
    }
    else {
        Fail "node.exe missing: $nodeExe"
    }

    $sdkVersion = Get-PackageVersion -PackageRoot $sdkRoot
    if ($sdkVersion -eq "1.5.0") {
        Pass "pi package version: $sdkVersion"
    }
    else {
        Fail "Expected pi 1.5.0, found: $sdkVersion"
    }

    $delegateVersion = Get-PackageVersion -PackageRoot $delegateRoot
    if ($delegateVersion -eq "0.1.1") {
        Pass "MCP adapter version: $delegateVersion"
    }
    else {
        Fail "Expected pi-delegate-mcp 0.1.1, found: $delegateVersion"
    }

    $piCmd = Join-Path $npmGlobalPrefix "pi.cmd"
    if (Test-Path -LiteralPath $piCmd -PathType Leaf) {
        $piVersionText = (& $piCmd --version).Trim()
        if ($piVersionText -match "1\.5\.0") {
            Pass "pi CLI reports: $piVersionText"
        }
        else {
            Fail "Unexpected pi CLI version: $piVersionText"
        }
    }
    else {
        Fail "pi.cmd missing: $piCmd"
    }
}

if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
    Pass "MCP launcher exists: $launcherPath"
    if ($null -ne $paths -and (Test-Path -LiteralPath $nodeExe -PathType Leaf)) {
        & $nodeExe --check $launcherPath
        if ($LASTEXITCODE -eq 0) {
            Pass "MCP launcher syntax"
        }
        else {
            Fail "MCP launcher syntax check failed"
        }
    }
}
else {
    Fail "MCP launcher missing: $launcherPath"
}

if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $configText = [System.IO.File]::ReadAllText($configPath)
    if ($configText -match "(?m)^\s*\[mcp_servers\.pi\]\s*$") {
        Pass "Codex config contains [mcp_servers.pi]"
    }
    else {
        Fail "Codex config does not contain [mcp_servers.pi]"
    }
    if ($configText -match "(?m)^\s*startup_timeout_sec\s*=\s*180\s*$") {
        Pass "pi MCP startup timeout is 180 seconds"
    }
    else {
        Warn "pi MCP startup timeout is not 180 seconds"
    }
    if ($configText -match "(?m)^\s*tool_timeout_sec\s*=\s*1800\s*$") {
        Pass "pi MCP tool timeout is 1800 seconds"
    }
    else {
        Warn "pi MCP tool timeout is not 1800 seconds"
    }
    if ($configText -match "(?m)^\s*PI_DELEGATE_STRICT_SCOPE\s*=\s*'1'\s*$") {
        Pass "pi MCP strict model scope is enabled"
    }
    else {
        Warn "pi MCP strict model scope is not enabled"
    }
}
else {
    Fail "Codex config missing: $configPath"
}

if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
    $agentsText = [System.IO.File]::ReadAllText($agentsPath)
    if ($agentsText.Contains("CODEX_PI_KIT:BEGIN") -and $agentsText.Contains("CODEX_PI_KIT:END")) {
        Pass "AGENTS.md managed block exists"
    }
    else {
        Fail "AGENTS.md managed block is missing"
    }
}
else {
    Fail "AGENTS.md missing: $agentsPath"
}

if (Test-Path -LiteralPath $playbookPath -PathType Leaf) {
    Pass "PI_PLAYBOOK.md exists"
}
else {
    Fail "PI_PLAYBOOK.md missing: $playbookPath"
}

if (Test-Path -LiteralPath (Join-Path $AgentHome "settings.json") -PathType Leaf) {
    Pass "pi settings.json exists"
}
else {
    Warn "pi settings.json not found: $(Join-Path $AgentHome 'settings.json')"
}

$legacyModelsPath = Join-Path $AgentHome "models.json"
$modelsStorePath = Join-Path $AgentHome "models-store.json"
$authPath = Join-Path $AgentHome "auth.json"
if (Test-Path -LiteralPath $legacyModelsPath -PathType Leaf) {
    try {
        $modelConfig = [System.IO.File]::ReadAllText($legacyModelsPath) | ConvertFrom-Json
        if ($null -ne $modelConfig.providers -and @($modelConfig.providers.PSObject.Properties).Count -gt 0) {
            Pass "pi models.json contains provider configuration"
        }
        else {
            Warn "pi models.json has no providers"
        }
    }
    catch {
        Fail "pi models.json is not valid JSON"
    }
}
elseif ((Test-Path -LiteralPath $modelsStorePath -PathType Leaf) -and (Test-Path -LiteralPath $authPath -PathType Leaf)) {
    try {
        [System.IO.File]::ReadAllText($modelsStorePath) | ConvertFrom-Json | Out-Null
        Pass "pi credential store and auth.json are present"
    }
    catch {
        Fail "pi models-store.json is not valid JSON"
    }
}
else {
    Warn "No pi provider store found; configure a provider before model smoke"
}

if ($RunSmoke) {
    if ($null -eq $paths) {
        Fail "Cannot run model smoke without package paths"
    }
    else {
        $piCmd = Join-Path $npmGlobalPrefix "pi.cmd"
        if (-not (Test-Path -LiteralPath $piCmd -PathType Leaf)) {
            Fail "Cannot run model smoke because pi.cmd is missing"
        }
        else {
            $oldLocation = Get-Location
            try {
                if (-not [string]::IsNullOrWhiteSpace($SmokeCwd)) {
                    Set-Location -LiteralPath $SmokeCwd
                }
                Write-Host "[codex-pi] Running read-only model smoke; this may cost API usage."
                & $piCmd -p `
                    --no-extensions --no-mcp `
                    --tools read,grep,find,ls `
                    --session-id "codex-pi-kit-verify-20261118" `
                    "Read-only smoke. Inspect the current directory only. Return exactly CODEX_PI_READY and do not modify files."
                if ($LASTEXITCODE -eq 0) {
                    Pass "pi read-only model smoke completed"
                }
                else {
                    Fail "pi read-only model smoke failed with exit code $LASTEXITCODE"
                }
            }
            finally {
                Set-Location $oldLocation
            }
        }
    }
}

Write-Host ""
Write-Host ("Verification summary: {0} failure(s), {1} warning(s)." -f $Failures.Count, $Warnings.Count)
if ($Failures.Count -gt 0) {
    throw "Verification failed."
}

Write-Host "Verification passed."
