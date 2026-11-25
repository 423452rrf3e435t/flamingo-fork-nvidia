# RTX 3070 / 8 GiB profile for the Flamingo-based VIctory port.
#
# Build first:
#   cargo build --profile diag -p victory
#
# Example:
#   .\scripts\play-rtx3070.ps1 -GameExe "C:\path\to\game_scarlett_master.exe"
#
# Series S mode is selected by default: it reduces the title's rendering
# workload and uses the title's Series S upscaler. Pass -SeriesX to compare
# the sharper, heavier Series X rendering path.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$GameExe,

    [string]$VictoryExe = (Join-Path $PSScriptRoot "..\target\diag\victory.exe"),

    [string]$ConfigPath = "",

    [ValidateRange(128, 1024)]
    [int]$CardBuffersMb = 512,

    [switch]$SeriesX,

    [switch]$NoOverlay
)

$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$GameExe = [System.IO.Path]::GetFullPath($GameExe)
$VictoryExe = [System.IO.Path]::GetFullPath($VictoryExe)

if (-not (Test-Path -LiteralPath $VictoryExe -PathType Leaf)) {
    throw "victory.exe not found at '$VictoryExe'. Build it with: cargo build --profile diag -p victory"
}

if ($ConfigPath) {
    $ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config file not found at '$ConfigPath'."
    }
}

# The port can use a large working set. Warn rather than trying to alter
# Windows' paging-file configuration without the user's consent.
try {
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $ramGiB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
    Write-Host ("Detected physical memory: {0} GiB" -f $ramGiB)
    if ($ramGiB -lt 24) {
        Write-Warning "This port can put substantial pressure on system memory. On a 16 GiB PC, close browsers and other heavy apps, keep a Windows-managed paging file on an SSD, and check Task Manager > Performance > Memory > Committed. This script does not change your page file."
    }
} catch {
    Write-Warning "Could not read the installed RAM amount; continuing."
}

# Keep the environment changes local to this launch and restore previous
# values even when the game exits with an error.
$names = @(
    "VICTORY_CONFIG",
    "VICTORY_NO_WATCHDOG",
    "VICTORY_PIPELINE_WAIT_MS",
    "VICTORY_RELAY",
    "VICTORY_LATE_WAIT",
    "VICTORY_CARD_BUFFERS_MIN_MB",
    "VICTORY_CARD_BUFFERS_MB",
    "VICTORY_INDIRECT_WINDOW",
    "VICTORY_SHADER_OPT",
    "VICTORY_WIDE_MERGE",
    "VICTORY_BVH_BUILDER",
    "VICTORY_AMBIENT_STUB",
    "VICTORY_SHADOWMASK_STUB",
    "FLAMINGO_OSD"
)

$previous = @{}
foreach ($name in $names) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

$exitCode = 0
try {
    if ($ConfigPath) {
        $env:VICTORY_CONFIG = $ConfigPath
    }

    # Baseline from this repository's tested Series S launch recipe.
    # The card-copy pool is reduced from the 1 GiB / 12 GiB test-card setting
    # to 512 MiB for an 8 GiB card.
    $env:VICTORY_NO_WATCHDOG = "1"
    $env:VICTORY_PIPELINE_WAIT_MS = "24"
    $env:VICTORY_RELAY = "1"
    $env:VICTORY_LATE_WAIT = "3"
    $env:VICTORY_CARD_BUFFERS_MIN_MB = "1"
    $env:VICTORY_CARD_BUFFERS_MB = "$CardBuffersMb"
    $env:VICTORY_INDIRECT_WINDOW = "1"
    $env:VICTORY_SHADER_OPT = "0"
    $env:VICTORY_WIDE_MERGE = "1"

    # Do not let an inherited experimental setting replace lighting passes
    # or start the unfinished ray-tracing structure builder.
    $env:VICTORY_BVH_BUILDER = "0"
    $env:VICTORY_AMBIENT_STUB = "0"
    $env:VICTORY_SHADOWMASK_STUB = "0"

    if ($NoOverlay) {
        $env:FLAMINGO_OSD = "0"
    } else {
        $env:FLAMINGO_OSD = "1"
    }

    $console = if ($SeriesX) { "series-x" } else { "series-s" }

    Write-Host ""
    Write-Host "Flamingo / VIctory RTX 3070 profile"
    Write-Host ("Executable:       {0}" -f $VictoryExe)
    Write-Host ("Game:             {0}" -f $GameExe)
    Write-Host ("Console profile:  {0}" -f $console)
    Write-Host ("Card copy budget: {0} MiB" -f $CardBuffersMb)
    Write-Host ("Stats overlay:    {0}" -f (-not $NoOverlay))
    Write-Host "Ray-tracing builder and lighting stand-ins: OFF"
    Write-Host "Press F9 to hide/show the stats overlay."
    Write-Host ""

    Push-Location $repoRoot
    try {
        & $VictoryExe run $GameExe --execute --console $console
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if ($exitCode -ne 0) {
        throw "VIctory exited with code $exitCode. Check the console output and the title's data-folder crashes.log."
    }
} finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process")
    }
}

exit $exitCode
