# Tool for creating a backup of the current state of a Minecraft server. 
# Backups will be saved to a different drive, but this can be customized for different usecases. 

# Define the source and destination paths for the backup

$sourcePath = "U:\minecraft"
$backupPath = "Z:\backups"
$allowLiveCopyFallback = $true

if (-not (Test-Path -Path $sourcePath)) {
    throw "Source path is not accessible: $sourcePath"
}

if (-not (Test-Path -Path $backupPath)) {
    throw "Backup path is not accessible: $backupPath"
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Script is not running as Administrator. VSS snapshot and backup-mode features may not be available."
}

function New-VssSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VolumeRoot
    )

    $result = ([WMIClass]"Win32_ShadowCopy").Create($VolumeRoot, "ClientAccessible")
    if ($result.ReturnValue -ne 0) {
        throw "Failed to create VSS snapshot for $VolumeRoot. Return code: $($result.ReturnValue)"
    }

    $shadowCopy = Get-WmiObject Win32_ShadowCopy -Filter "ID='$($result.ShadowID)'"
    if (-not $shadowCopy) {
        throw "VSS snapshot was created but could not be queried."
    }

    return $shadowCopy
}

function Invoke-RobocopyDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FromPath,
        [Parameter(Mandatory = $true)]
        [string]$ToPath
    )

    $robocopyArgs = @(
        $FromPath,
        $ToPath,
        '/E',
        '/R:2',
        '/W:1',
        '/COPY:DAT',
        '/DCOPY:DAT',
        '/Z',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NP'
    )

    & robocopy @robocopyArgs | Out-Null
    $robocopyExitCode = $LASTEXITCODE
    return $robocopyExitCode
}

# Create a timestamp that will be uniquely used in the backup folder name
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Create the backup folder name using the timestamp
$backupFolderName = "minecraft_backup_$timestamp"

# Combine the backup path and folder name to get the full backup path
$fullBackupPath = Join-Path -Path $backupPath -ChildPath $backupFolderName

# Copy the Minecraft server files to the backup directory using VSS so the server can stay online
$shadowCopy = $null
try {
    $volumeRoot = (Get-Item -Path $sourcePath).PSDrive.Root
    $relativePath = $sourcePath.Substring($volumeRoot.Length).TrimStart('\\')

    $didUseVss = $false
    try {
        Write-Host "Creating VSS snapshot for $volumeRoot..."
        $shadowCopy = New-VssSnapshot -VolumeRoot $volumeRoot

        $snapshotRoot = $shadowCopy.DeviceObject
        if (-not $snapshotRoot.EndsWith('\\')) {
            $snapshotRoot += '\\'
        }

        $snapshotSourcePath = if ([string]::IsNullOrWhiteSpace($relativePath)) { $snapshotRoot } else { "$snapshotRoot$relativePath" }
        Write-Host "Starting online backup of Minecraft server from snapshot path $snapshotSourcePath to $fullBackupPath..."
        $vssCopyExitCode = Invoke-RobocopyDirectory -FromPath $snapshotSourcePath -ToPath $fullBackupPath
        if ($vssCopyExitCode -ge 8) {
            throw "VSS copy failed with robocopy exit code $vssCopyExitCode"
        }

        $didUseVss = $true
    } catch {
        if (-not $allowLiveCopyFallback) {
            throw
        }

        Write-Warning "VSS snapshot copy failed: $_"
        Write-Warning "Falling back to live copy. To require VSS-only backups, set `$allowLiveCopyFallback = `$false."
        Write-Host "Starting live backup from $sourcePath to $fullBackupPath..."
        $liveCopyExitCode = Invoke-RobocopyDirectory -FromPath $sourcePath -ToPath $fullBackupPath
        if ($liveCopyExitCode -ge 8) {
            Write-Warning "Live backup completed with robocopy exit code $liveCopyExitCode (some files may have been skipped due to locks)."
        }
    }

    if (-not (Test-Path -Path $fullBackupPath)) {
        throw "Backup destination folder was not created: $fullBackupPath"
    }

    $copiedItemCount = (Get-ChildItem -Path $fullBackupPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($copiedItemCount -eq 0) {
        throw "Backup completed but destination is empty: $fullBackupPath"
    }

    if ($didUseVss) {
        Write-Host "Backup completed successfully using VSS snapshot!"
    } else {
        Write-Host "Backup completed successfully using live copy fallback."
    }
} catch {
    if ((Test-Path -Path $fullBackupPath) -and ((Get-ChildItem -Path $fullBackupPath -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0)) {
        Remove-Item -Path $fullBackupPath -Force -Recurse -ErrorAction SilentlyContinue
    }
    Write-Error "An error occurred during the backup process: $_"
} finally {
    if ($shadowCopy) {
        try {
            Write-Host "Removing VSS snapshot..."
            $null = $shadowCopy.Delete()
        } catch {
            Write-Warning "Backup finished, but failed to remove VSS snapshot: $_"
        }
    }
}

# Clean up old backups, retention is older than 7 days. 
$backupRetentionDays = 7
$backupFolders = Get-ChildItem -Path $backupPath -Directory
foreach ($folder in $backupFolders) {
    $folderAge = (Get-Date) - $folder.CreationTime
    if ($folderAge.TotalDays -gt $backupRetentionDays) {
        try {
            Write-Host "Deleting old backup: $($folder.FullName)"
            Remove-Item -Path $folder.FullName -Recurse -Force
            Write-Host "Deleted old backup: $($folder.FullName)"
        } catch {
            Write-Error "An error occurred while deleting old backup: $_"
        }
    }
}

