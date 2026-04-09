# Tool for creating a backup of the current state of a Minecraft server. 
# Backups will be saved to a different drive, but this can be customized for different usecases. 

# Define the source and destination paths for the backup

$sourcePath = "U:\minecraft"
$backupPath = "Z:\backups"

# Create a timestamp that will be uniquely used in the backup folder name
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Create the backup folder name using the timestamp
$backupFolderName = "minecraft_backup_$timestamp"

# Combine the backup path and folder name to get the full backup path
$fullBackupPath = Join-Path -Path $backupPath -ChildPath $backupFolderName

# Create the backup directory if it doesn't exist
if (-not (Test-Path -Path $fullBackupPath)) {
    New-Item -ItemType Directory -Path $fullBackupPath | Out-Null
}

# Copy the Minecraft server files to the backup directory
try {
    Write-Host "Starting backup of Minecraft server from $sourcePath to $fullBackupPath..."
    Copy-Item -Path $sourcePath\* -Destination $fullBackupPath -Recurse -Force
    Write-Host "Backup completed successfully!"
} catch {
    Write-Error "An error occurred during the backup process: $_"
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

