[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ProviderId = "",
    [string]$DisplayName = "",
    [string]$BaseUrl = "",
    [SecureString]$ApiKey = $null,
    [string]$Api = "openai-completions",
    [string[]]$ModelIds = @(),
    [int]$ContextWindow = 200000,
    [int]$MaxTokens = 32768,
    [switch]$Reasoning,
    [string]$HeadersJson = "",
    [string]$AgentHome = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Write-Step {
    param([string]$Message)
    Write-Host "[codex-pi] $Message"
}

function Backup-File {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
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
        return
    }
    Copy-Item -LiteralPath $Path -Destination $candidate
    Write-Step "Backup: $candidate"
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function ConvertTo-PlainText {
    param([SecureString]$SecureValue)

    if ($null -eq $SecureValue) {
        return ""
    }

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

if ([string]::IsNullOrWhiteSpace($AgentHome)) {
    $AgentHome = if ($env:PI_CODING_AGENT_DIR) {
        $env:PI_CODING_AGENT_DIR
    }
    else {
        Join-Path ([Environment]::GetFolderPath("UserProfile")) ".pi\agent"
    }
}
$AgentHome = [System.IO.Path]::GetFullPath($AgentHome)

if ([string]::IsNullOrWhiteSpace($ProviderId)) {
    $ProviderId = Read-Host "Provider id (for example my-provider or deepseek)"
}
if ($ProviderId -notmatch "^[A-Za-z0-9._-]+$") {
    throw "ProviderId may only contain letters, digits, dot, underscore and hyphen."
}

if ([string]::IsNullOrWhiteSpace($DisplayName)) {
    $DisplayName = Read-Host ("Display name [{0}]" -f $ProviderId)
    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = $ProviderId
    }
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = Read-Host "Base URL"
}
if ($BaseUrl -notmatch "^https?://") {
    throw "BaseUrl must start with http:// or https://"
}

if ($null -eq $ApiKey -and -not $DryRun) {
    $ApiKey = Read-Host "API key (input hidden)" -AsSecureString
}
$apiKeyPlain = if ($DryRun -and $null -eq $ApiKey) {
    "dry-run-placeholder"
}
else {
    ConvertTo-PlainText -SecureValue $ApiKey
}
if ([string]::IsNullOrWhiteSpace($apiKeyPlain)) {
    throw "API key must not be empty."
}

if ($ModelIds.Count -eq 0 -and -not $DryRun) {
    $modelText = Read-Host "Model ids, comma separated"
    $ModelIds = @($modelText.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
if ($ModelIds.Count -eq 0 -and $DryRun) {
    $ModelIds = @("dry-run-model")
}
$ModelIds = @($ModelIds | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
if ($ModelIds.Count -eq 0) {
    throw "At least one model id is required."
}

$headers = $null
if (-not [string]::IsNullOrWhiteSpace($HeadersJson)) {
    try {
        $headers = $HeadersJson | ConvertFrom-Json
    }
    catch {
        throw "HeadersJson is not valid JSON."
    }
}

$models = New-Object System.Collections.ArrayList
foreach ($modelId in $ModelIds) {
    $models.Add([ordered]@{
        id = $modelId
        name = $modelId
        reasoning = [bool]$Reasoning
        input = @("text")
        contextWindow = $ContextWindow
        maxTokens = $MaxTokens
        cost = [ordered]@{
            input = 0
            output = 0
            cacheRead = 0
            cacheWrite = 0
        }
    }) | Out-Null
}

$modelsPath = Join-Path $AgentHome "models.json"
$settingsPath = Join-Path $AgentHome "settings.json"

$providers = [ordered]@{}
if (Test-Path -LiteralPath $modelsPath -PathType Leaf) {
    $existingModels = [System.IO.File]::ReadAllText($modelsPath) | ConvertFrom-Json
    if ($null -ne $existingModels.PSObject.Properties["providers"]) {
        foreach ($property in $existingModels.providers.PSObject.Properties) {
            $providers[$property.Name] = $property.Value
        }
    }
}

$provider = [ordered]@{
    name = $DisplayName
    baseUrl = $BaseUrl.TrimEnd("/")
    api = $Api
    apiKey = $apiKeyPlain
    models = $models.ToArray()
}
if ($null -ne $headers) {
    $provider["headers"] = $headers
}
$providers[$ProviderId] = $provider

$settings = [ordered]@{}
if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    $existingSettings = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
    foreach ($property in $existingSettings.PSObject.Properties) {
        $settings[$property.Name] = $property.Value
    }
}

$modelRefs = @($ModelIds | ForEach-Object { "$ProviderId/$_" })
$enabledModels = New-Object System.Collections.Generic.List[string]
if ($settings.Contains("enabledModels") -and $null -ne $settings["enabledModels"]) {
    foreach ($existingRef in $settings["enabledModels"]) {
        if (-not [string]::IsNullOrWhiteSpace([string]$existingRef)) {
            $enabledModels.Add([string]$existingRef)
        }
    }
}
foreach ($modelRef in $modelRefs) {
    if (-not $enabledModels.Contains($modelRef)) {
        $enabledModels.Add($modelRef)
    }
}
$settings["defaultProvider"] = $ProviderId
$settings["defaultModel"] = $ModelIds[0]
$settings["enabledModels"] = $enabledModels.ToArray()
if (-not $settings.Contains("defaultThinkingLevel")) {
    $settings["defaultThinkingLevel"] = "high"
}

if (-not (Test-Path -LiteralPath $AgentHome -PathType Container)) {
    if ($DryRun) {
        Write-Step "DRY RUN create directory: $AgentHome"
    }
    else {
        New-Item -ItemType Directory -Path $AgentHome -Force | Out-Null
    }
}

if ($DryRun) {
    Write-Step "DRY RUN provider: $ProviderId"
    Write-Step "DRY RUN models: $($ModelIds -join ', ')"
    Write-Step "DRY RUN write: $modelsPath"
    Write-Step "DRY RUN write: $settingsPath"
    exit 0
}

if (-not $PSCmdlet.ShouldProcess($modelsPath, "Write pi provider configuration")) {
    return
}

Backup-File -Path $modelsPath
Backup-File -Path $settingsPath
Write-Utf8NoBom -Path $modelsPath -Content (([ordered]@{ providers = $providers }) | ConvertTo-Json -Depth 12)
Write-Utf8NoBom -Path $settingsPath -Content ($settings | ConvertTo-Json -Depth 8)

$apiKeyPlain = $null
Write-Step "Configured provider: $ProviderId"
Write-Step "Default model: $ProviderId/$($ModelIds[0])"
Write-Step "Models file: $modelsPath"
Write-Step "Settings file: $settingsPath"
