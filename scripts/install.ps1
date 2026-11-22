[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$InstallDir = "",
    [string]$CodexHome = "",
    [string]$AgentHome = "",
    [string]$NodeExe = "",
    [string]$NpmCmd = "",
    [string]$NpmGlobalPrefix = "",
    [switch]$SkipNpmInstall,
    [switch]$SkipMcpConfig,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$KitRoot = Split-Path -Parent $PSScriptRoot
$Backups = New-Object System.Collections.Generic.List[string]
$Actions = New-Object System.Collections.Generic.List[string]

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Write-Step {
    param([string]$Message)
    Write-Host "[codex-pi] $Message"
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Ensure-Directory {
    param([string]$Path)
    if ($DryRun) {
        Write-Step "DRY RUN create directory: $Path"
        return
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Backup-File {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $parent = Split-Path -Parent $Path
    $leaf = Split-Path -Leaf $Path
    $index = 1
    do {
        $candidate = Join-Path $parent ("{0}.bak.{1}" -f $leaf, $index)
        $index += 1
    } while (Test-Path -LiteralPath $candidate)

    if ($DryRun) {
        Write-Step "DRY RUN backup: $Path -> $candidate"
        return $candidate
    }

    Copy-Item -LiteralPath $Path -Destination $candidate
    $Backups.Add($candidate)
    Write-Step "Backup: $candidate"
    return $candidate
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $display = "$FilePath $($Arguments -join ' ')"
    if ($DryRun) {
        Write-Step "DRY RUN command: $display"
        return
    }

    Write-Step "Run: $display"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $display"
    }
}

function Merge-ManagedBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    $beginMarker = "<!-- CODEX_PI_KIT:BEGIN -->"
    $endMarker = "<!-- CODEX_PI_KIT:END -->"
    $source = [System.IO.File]::ReadAllText($SourcePath)

    if (-not $source.Contains($beginMarker) -or -not $source.Contains($endMarker)) {
        throw "Managed source is missing CODEX_PI_KIT markers: $SourcePath"
    }

    $target = ""
    if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
        $target = [System.IO.File]::ReadAllText($TargetPath)
    }

    $beginIndex = $target.IndexOf($beginMarker, [System.StringComparison]::Ordinal)
    $endIndex = $target.IndexOf($endMarker, [System.StringComparison]::Ordinal)
    if ($beginIndex -ge 0 -and $endIndex -ge $beginIndex) {
        $afterEnd = $endIndex + $endMarker.Length
        $merged = $target.Substring(0, $beginIndex) + $source.Trim() + $target.Substring($afterEnd)
    }
    elseif ([string]::IsNullOrWhiteSpace($target)) {
        $merged = $source.Trim() + "`r`n"
    }
    else {
        $merged = $target.TrimEnd() + "`r`n`r`n" + $source.Trim() + "`r`n"
    }

    Backup-File -Path $TargetPath | Out-Null
    if ($DryRun) {
        Write-Step "DRY RUN merge managed block into: $TargetPath"
        return
    }
    Write-Utf8NoBom -Path $TargetPath -Content $merged
    $Actions.Add("Merged managed block into $TargetPath")
}

function Copy-WithBackup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Source file not found: $SourcePath"
    }

    Backup-File -Path $TargetPath | Out-Null
    if ($DryRun) {
        Write-Step "DRY RUN copy: $SourcePath -> $TargetPath"
        return
    }
    Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    $Actions.Add("Installed $TargetPath")
}

function Resolve-NodeExecutable {
    if (-not [string]::IsNullOrWhiteSpace($NodeExe)) {
        $candidate = Resolve-FullPath -Path $NodeExe -BasePath (Get-Location).Path
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
        throw "Node executable not found: $candidate"
    }

    $command = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "node.exe was not found in PATH. Install Node.js 22.19.0 or newer first."
    }
    return $command.Source
}

function Resolve-NpmCommand {
    param([string]$ResolvedNodeExe)

    if (-not [string]::IsNullOrWhiteSpace($NpmCmd)) {
        $candidate = Resolve-FullPath -Path $NpmCmd -BasePath (Get-Location).Path
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
        throw "npm command not found: $candidate"
    }

    $adjacent = Join-Path (Split-Path -Parent $ResolvedNodeExe) "npm.cmd"
    if (Test-Path -LiteralPath $adjacent -PathType Leaf) {
        return $adjacent
    }

    $command = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw "npm.cmd was not found. Install npm or add it to PATH."
}

function Assert-NodeVersion {
    param([string]$ResolvedNodeExe)

    $text = (& $ResolvedNodeExe --version).Trim()
    if ($text -notmatch "^v?(\d+)\.(\d+)\.(\d+)") {
        throw "Could not parse Node.js version from: $text"
    }
    $version = [version]("{0}.{1}.{2}" -f $Matches[1], $Matches[2], $Matches[3])
    if ($version -lt [version]"22.19.0") {
        throw "Node.js $version is too old. Version 22.19.0 or newer is required."
    }
    return $version
}

function Set-ExampleIfMissing {
    param(
        [string]$TargetPath,
        [string]$Content,
        [string]$Description
    )

    if (Test-Path -LiteralPath $TargetPath) {
        Write-Step "Keep existing $Description`: $TargetPath"
        return
    }

    if ($DryRun) {
        Write-Step "DRY RUN create $Description`: $TargetPath"
        return
    }
    Write-Utf8NoBom -Path $TargetPath -Content ($Content.TrimEnd() + "`r`n")
    $Actions.Add("Created $TargetPath")
    Write-Step "Created $Description`: $TargetPath"
}

$now = Get-Date
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

$InstallDir = Resolve-FullPath -Path $InstallDir -BasePath (Get-Location).Path
$CodexHome = Resolve-FullPath -Path $CodexHome -BasePath (Get-Location).Path
$AgentHome = Resolve-FullPath -Path $AgentHome -BasePath (Get-Location).Path
if ([string]::IsNullOrWhiteSpace($NpmGlobalPrefix)) {
    $NpmGlobalPrefix = Join-Path $InstallDir "npm-global"
}
$NpmGlobalPrefix = Resolve-FullPath -Path $NpmGlobalPrefix -BasePath (Get-Location).Path

$ResolvedNodeExe = Resolve-NodeExecutable
$ResolvedNpmCmd = Resolve-NpmCommand -ResolvedNodeExe $ResolvedNodeExe
$NodeVersion = Assert-NodeVersion -ResolvedNodeExe $ResolvedNodeExe

Write-Step "Kit: $KitRoot"
Write-Step "Node: $ResolvedNodeExe ($NodeVersion)"
Write-Step "npm: $ResolvedNpmCmd"
Write-Step "Install prefix: $NpmGlobalPrefix"
Write-Step "CODEX_HOME: $CodexHome"
Write-Step "PI_CODING_AGENT_DIR: $AgentHome"

Ensure-Directory -Path $NpmGlobalPrefix
Ensure-Directory -Path $InstallDir

if (-not $SkipNpmInstall) {
    Invoke-Checked -FilePath $ResolvedNpmCmd -Arguments @(
        "install",
        "-g",
        "--prefix",
        $NpmGlobalPrefix,
        "@earendil-works/pi-coding-agent@1.5.0",
        "pi-delegate-mcp@0.1.1"
    )
}
else {
    Write-Step "Skip npm install"
}

$sdkRoot = Join-Path $NpmGlobalPrefix "node_modules\@earendil-works\pi-coding-agent"
$delegateRoot = Join-Path $NpmGlobalPrefix "node_modules\pi-delegate-mcp"
if (-not $DryRun) {
    if (-not (Test-Path -LiteralPath (Join-Path $sdkRoot "package.json"))) {
        throw "pi SDK package is missing after install: $sdkRoot"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $delegateRoot "package.json"))) {
        throw "pi delegate package is missing after install: $delegateRoot"
    }
}

$mcpDir = Join-Path $CodexHome "mcp"
Ensure-Directory -Path $mcpDir
Copy-WithBackup `
    -SourcePath (Join-Path $KitRoot "mcp\pi-delegate-mcp-launcher.mjs") `
    -TargetPath (Join-Path $mcpDir "pi-delegate-mcp-launcher.mjs")

$pathsObject = [ordered]@{
    sdkRoot = $sdkRoot
    delegateRoot = $delegateRoot
    npmGlobalPrefix = $NpmGlobalPrefix
    nodeExe = $ResolvedNodeExe
    generatedAt = $now.ToString("o")
    kitVersion = "1.0.1"
}
$pathsPath = Join-Path $mcpDir "pi-delegate-paths.json"
Backup-File -Path $pathsPath | Out-Null
if (-not $DryRun) {
    Write-Utf8NoBom -Path $pathsPath -Content ($pathsObject | ConvertTo-Json -Depth 4)
    $Actions.Add("Wrote package path table to $pathsPath")
}

Ensure-Directory -Path $AgentHome
$settingsPath = Join-Path $AgentHome "settings.json"
$settingsContent = @'
{
  "defaultThinkingLevel": "high"
}
'@
Set-ExampleIfMissing `
    -TargetPath $settingsPath `
    -Content $settingsContent `
    -Description "pi settings"

$piMcpPath = Join-Path $AgentHome "mcp.json"
$piMcpContent = @'
{
  "mcpServers": {}
}
'@
Set-ExampleIfMissing `
    -TargetPath $piMcpPath `
    -Content $piMcpContent `
    -Description "pi MCP configuration"

Ensure-Directory -Path $CodexHome
$agentsPath = Join-Path $CodexHome "AGENTS.md"
Merge-ManagedBlock `
    -TargetPath $agentsPath `
    -SourcePath (Join-Path $KitRoot "AGENTS.md")

Copy-WithBackup `
    -SourcePath (Join-Path $KitRoot "PI_PLAYBOOK.md") `
    -TargetPath (Join-Path $CodexHome "PI_PLAYBOOK.md")

if (-not $SkipMcpConfig) {
    $configPath = Join-Path $CodexHome "config.toml"
    $templatePath = Join-Path $KitRoot "config\codex-pi-mcp.example.toml"
    $template = [System.IO.File]::ReadAllText($templatePath)

    if ($ResolvedNodeExe.Contains("'") -or $CodexHome.Contains("'") -or $NpmGlobalPrefix.Contains("'")) {
        throw "A selected path contains a single quote, which this safe TOML template does not support."
    }

    $snippet = $template.Replace("{{NODE_EXE}}", $ResolvedNodeExe)
    $snippet = $snippet.Replace("{{CODEX_HOME}}", $CodexHome)
    $snippet = $snippet.Replace("{{NPM_GLOBAL_PREFIX}}", $NpmGlobalPrefix)

    $existing = ""
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $existing = [System.IO.File]::ReadAllText($configPath)
    }

    $hasManagedBlock = $existing.Contains("# BEGIN CODEX_PI_KIT") -and $existing.Contains("# END CODEX_PI_KIT")
    $hasPiSection = $existing -match "(?m)^\s*\[mcp_servers\.pi\]\s*$"

    if ($hasManagedBlock) {
        $beginIndex = $existing.IndexOf("# BEGIN CODEX_PI_KIT", [System.StringComparison]::Ordinal)
        $endMarker = "# END CODEX_PI_KIT"
        $endIndex = $existing.IndexOf($endMarker, [System.StringComparison]::Ordinal)
        $afterEnd = $endIndex + $endMarker.Length
        $merged = $existing.Substring(0, $beginIndex) + $snippet.Trim() + $existing.Substring($afterEnd)

        Backup-File -Path $configPath | Out-Null
        if ($DryRun) {
            Write-Step "DRY RUN replace managed Codex MCP block: $configPath"
        }
        else {
            Write-Utf8NoBom -Path $configPath -Content ($merged.TrimEnd() + "`r`n")
            $Actions.Add("Updated managed pi MCP block in $configPath")
        }
    }
    elseif ($hasPiSection) {
        $snippetPath = Join-Path $mcpDir "pi-mcp-snippet.toml"
        Backup-File -Path $snippetPath | Out-Null
        if (-not $DryRun) {
            Write-Utf8NoBom -Path $snippetPath -Content ($snippet.TrimEnd() + "`r`n")
        }
        Write-Warning "[mcp_servers.pi] already exists without kit markers. It was not modified. Review: $snippetPath"
        $Actions.Add("Preserved existing pi MCP block and wrote candidate snippet to $snippetPath")
    }
    else {
        Backup-File -Path $configPath | Out-Null
        if ($DryRun) {
            Write-Step "DRY RUN append pi MCP block: $configPath"
        }
        else {
            $prefix = if ([string]::IsNullOrWhiteSpace($existing)) { "" } else { $existing.TrimEnd() + "`r`n`r`n" }
            Write-Utf8NoBom -Path $configPath -Content ($prefix + $snippet.Trim() + "`r`n")
            $Actions.Add("Appended pi MCP block to $configPath")
        }
    }
}
else {
    Write-Step "Skip Codex MCP config"
}

if (-not $DryRun) {
    $reportPath = Join-Path $InstallDir "install-report.json"
    $report = [ordered]@{
        kitVersion = "1.0.1"
        installedAt = $now.ToString("o")
        nodeExe = $ResolvedNodeExe
        nodeVersion = $NodeVersion.ToString()
        npmCommand = $ResolvedNpmCmd
        npmGlobalPrefix = $NpmGlobalPrefix
        sdkRoot = $sdkRoot
        delegateRoot = $delegateRoot
        codexHome = $CodexHome
        agentHome = $AgentHome
        launcher = Join-Path $mcpDir "pi-delegate-mcp-launcher.mjs"
        packagePaths = $pathsPath
        backups = @($Backups)
        actions = @($Actions)
        nextSteps = @(
            "Restart Codex desktop.",
            "Call the pi MCP init tool.",
            "Run scripts/verify.ps1 and, after configuring a model, optionally use -RunSmoke.",
            "Configure pi provider credentials if models.json is not ready."
        )
    }
    Write-Utf8NoBom -Path $reportPath -Content ($report | ConvertTo-Json -Depth 6)
    Write-Step "Install report: $reportPath"
}

Write-Host ""
Write-Host "Installation completed."
Write-Host "Next:"
Write-Host "  1. Configure a pi model if needed:"
Write-Host "     powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-provider.ps1"
Write-Host "  2. Verify:"
Write-Host "     powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1"
Write-Host "  3. Restart Codex and call the pi MCP init tool first."
