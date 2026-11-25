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

    [switch]$NoOverlay,

    # Fresh-start mode is the default for repeated testing. Existing save
    # folders are backed up before empty folders are created.
    [switch]$KeepProgress,

    [switch]$ExperimentalNoHitLighting,

    [switch]$ExperimentalQuadHelpers
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
    "VICTORY_WIDE_TEXTURES",
    "VICTORY_BVH_BUILDER",
    "VICTORY_AMBIENT_STUB",
    "VICTORY_SHADOWMASK_STUB",
    "VICTORY_AMBIENT",
    "FLAMINGO_QUAD_HELPERS",
    "FLAMINGO_BVH_MISS",
    "FLAMINGO_OSD",
    "VICTORY_WIDE_BACK",
    "VICTORY_WIDE_REFRESH",
    "VICTORY_WAVE_LDS_LOOSE",
    "VICTORY_ASYNC_SUBMIT",
    "VICTORY_QUEUE2",
    "VICTORY_QUEUE2_REFETCH",
    "VICTORY_INPLACE",
    "VICTORY_VIEW_GUARD",
    "VICTORY_DISPLAY_MODE",
    "VICTORY_CARD_REHASH_RUNS",
    "FLAMINGO_CARD_FILLS",
    "FLAMINGO_COLD_ASKS"
)

$previous = @{}
foreach ($name in $names) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

# Remove optional paths that were measured as slower, visually risky, or
# inconclusive. Removing is deliberate: some switches are presence-based,
# so assigning the string "0" would not reliably mean disabled.
$clearExperimentNames = @(
    "VICTORY_WIDE_BACK",
    "VICTORY_WIDE_REFRESH",
    "VICTORY_WAVE_LDS_LOOSE",
    "VICTORY_ASYNC_SUBMIT",
    "VICTORY_QUEUE2",
    "VICTORY_QUEUE2_REFETCH",
    "VICTORY_INPLACE",
    "VICTORY_VIEW_GUARD",
    "VICTORY_DISPLAY_MODE",
    "VICTORY_CARD_REHASH_RUNS",
    "FLAMINGO_CARD_FILLS",
    "FLAMINGO_COLD_ASKS"
)
foreach ($name in $clearExperimentNames) {
    [Environment]::SetEnvironmentVariable($name, $null, "Process")
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
    # Texture refreshes run on the independent worker pool; the project's
    # RTX 4070 run log recorded fewer streaming/turning frame dips.
    $env:VICTORY_WIDE_TEXTURES = "1"

    # Do not let inherited experiments silently alter the picture/performance.
    # The ambient floor previously washed out the image; quad helpers added
    # detail but cost about 18% in the documented test; stand-ins did not
    # restore correct lighting.
    $env:VICTORY_BVH_BUILDER = "0"
    $env:VICTORY_AMBIENT_STUB = "0"
    $env:VICTORY_SHADOWMASK_STUB = "0"
    $env:VICTORY_AMBIENT = ""
    if ($ExperimentalQuadHelpers) {
        $env:FLAMINGO_QUAD_HELPERS = "1"
        Write-Warning "Experimental quad helper reads can improve fine detail but cost about 18% in the documented test. Compare a close-up and frame time."
    } else {
        $env:FLAMINGO_QUAD_HELPERS = "0"
    }

    if ($ExperimentalNoHitLighting) {
        $env:FLAMINGO_BVH_MISS = "1"
        Write-Warning "Experimental no-hit ray tracing is enabled. It may brighten some areas but replaces reflections with fallback streaks; a previous run hung. Compare briefly, then relaunch without this switch for normal mode."
    } else {
        $env:FLAMINGO_BVH_MISS = "0"
    }

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
    Write-Host ("Fresh start:      {0}" -f (-not $KeepProgress))
    Write-Host "Ray-tracing builder and lighting stand-ins: OFF"
    Write-Host ("Experimental no-hit ray mode: {0}" -f [bool]$ExperimentalNoHitLighting)
    Write-Host ("Experimental quad helpers:  {0}" -f [bool]$ExperimentalQuadHelpers)
    Write-Host "Press F9 to hide/show the stats overlay."
    Write-Host ""

    # Fresh-start mode archives persistent title data, instead of deleting it.
    # The title ID and data directory are read from the active manifest/config.
    if (-not $KeepProgress) {
        $configOutput = ""
        $configExitCode = 0
        Push-Location $repoRoot
        try {
            $savedPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = "Continue"
                $configOutput = (& $VictoryExe config 2>&1 | Out-String)
                $configExitCode = [int]$LASTEXITCODE
            } finally {
                $ErrorActionPreference = $savedPreference
            }
        } finally {
            Pop-Location
        }
        if ($configExitCode -ne 0) {
            throw "Could not read the resolved VIctory config (exit $configExitCode); refusing to reset save data."
        }

        $configLines = $configOutput -split [Environment]::NewLine
        $dataLine = $configLines |
            Where-Object { $_.TrimStart().StartsWith("data_dir", [StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
        if (-not $dataLine) {
            throw "Could not find data_dir in 'victory config'; refusing to reset save data."
        }
        $dataDirText = $dataLine.Substring($dataLine.IndexOf(":") + 1).Trim()
        if (-not [System.IO.Path]::IsPathRooted($dataDirText)) {
            $dataDirText = Join-Path $repoRoot $dataDirText
        }
        $dataDir = [System.IO.Path]::GetFullPath($dataDirText)
        $repoPrefix = $repoRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if ($dataDir.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to reset title data inside the repository: '$dataDir'."
        }

        $manifestCandidates = New-Object 'System.Collections.Generic.List[string]'
        $manifestCandidates.Add((Join-Path (Split-Path -Parent $GameExe) "MicrosoftGame.config"))
        $gameDirLine = $configLines |
            Where-Object { $_.TrimStart().StartsWith("game_dir", [StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
        if ($gameDirLine) {
            $gameDirText = $gameDirLine.Substring($gameDirLine.IndexOf(":") + 1).Trim()
            $missingSuffix = "  (does not exist)"
            if ($gameDirText.EndsWith($missingSuffix, [StringComparison]::OrdinalIgnoreCase)) {
                $gameDirText = $gameDirText.Substring(0, $gameDirText.Length - $missingSuffix.Length).TrimEnd()
            }
            if ($gameDirText -and $gameDirText -ne "(not set)") {
                if (-not [System.IO.Path]::IsPathRooted($gameDirText)) {
                    $gameDirText = Join-Path $repoRoot $gameDirText
                }
                $manifestCandidates.Add((Join-Path $gameDirText "MicrosoftGame.config"))
            }
        }

        $manifestPath = $null
        foreach ($candidate in $manifestCandidates) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $manifestPath = $candidate
                break
            }
        }
        if (-not $manifestPath) {
            throw "MicrosoftGame.config was not found; refusing to reset save data."
        }

        try {
            $manifestXml = New-Object System.Xml.XmlDocument
            $manifestXml.Load($manifestPath)
            $titleIdNode = $manifestXml.SelectSingleNode("//*[local-name()='TitleId']")
            if ($null -eq $titleIdNode -or [string]::IsNullOrWhiteSpace($titleIdNode.InnerText)) {
                throw "TitleId element is missing."
            }
            $titleIdNumber = [UInt32]::Parse(
                $titleIdNode.InnerText.Trim(),
                [Globalization.NumberStyles]::HexNumber
            )
            $titleId = $titleIdNumber.ToString("X8")
        } catch {
            throw "Could not read the title ID from '$manifestPath': $($_.Exception.Message) Refusing to reset save data."
        }

        $titleDataDir = Join-Path $dataDir $titleId
        $backupStamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
        foreach ($stateName in @("saves", "storage")) {
            $statePath = Join-Path $titleDataDir $stateName
            if (Test-Path -LiteralPath $statePath) {
                $backupPath = "$statePath.backup-$backupStamp"
                Move-Item -LiteralPath $statePath -Destination $backupPath
                Write-Host ("Previous {0} backed up to: {1}" -f $stateName, $backupPath)
            }
            New-Item -ItemType Directory -Force -Path $statePath | Out-Null
        }
        Write-Host ("Fresh title state prepared for ID {0}." -f $titleId)
    }

    Push-Location $repoRoot
    try {
        $logDir = Join-Path $env:LOCALAPPDATA "flamingo\logs"
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $logPath = Join-Path $logDir ("rtx3070-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
        Write-Host ("Run log:          {0}" -f $logPath)

        # Windows PowerShell can represent native stderr lines as error
        # records. With the script-wide Stop preference, an ordinary Rust
        # INFO message on stderr can abort this pipeline. Continue only for
        # the child process; we still check its real exit code immediately
        # after the pipeline and throw if it is non-zero.
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            & $VictoryExe run $GameExe --execute --console $console 2>&1 |
                Tee-Object -FilePath $logPath
            if ($null -eq $LASTEXITCODE) {
                $exitCode = 1
            } else {
                $exitCode = [int]$LASTEXITCODE
            }
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    } finally {
        Pop-Location
    }

    if ($exitCode -ne 0) {
        throw "VIctory exited with code $exitCode. Check the console output and the title's data-folder crashes.log."
    }

    Write-Host "VIctory exited normally (code 0)."
} finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process")
    }
}

# Deliberately do not use the PowerShell exit statement here: after the game
# quits it would also close the user's interactive PowerShell session.
