# MinecraftBackupServiceWindows
Backup service for Minecraft Server on Windows.

## Notes

- The backup script now performs an online backup using a VSS snapshot, so the Minecraft service can stay running.
- The task must run with administrative privileges so VSS snapshot creation succeeds.
- In Task Scheduler, avoid mapped drives (like `U:` or `Z:`) unless the task maps them itself; use local paths or UNC paths instead.
- If VSS cannot be created, the script falls back to live copy and will warn if some locked files were skipped.
