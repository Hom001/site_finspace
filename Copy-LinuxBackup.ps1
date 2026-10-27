$ErrorActionPreference = 'Stop'

# Connection and file settings
$LinuxHost = '46.149.69.254'
$LinuxUser = 'backupuser'
$SshPort = 22
$RemoteArchivePath = '/var/backups/site-backup.tar.gz'
$LocalBackupDirectory = 'D:\Backups'
$SshKeyPath = "$env:USERPROFILE\.ssh\id_ed25519"

try {
    if ($RemoteArchivePath -notmatch '^/[A-Za-z0-9._/-]+$' -or
        $RemoteArchivePath -match '(^|/)\.\.?(/|$)' -or
        $RemoteArchivePath.EndsWith('/')) {
        throw 'RemoteArchivePath must be an absolute file path containing only letters, digits, dots, underscores, hyphens, and slashes; "." and ".." path segments are not allowed.'
    }

    if ([string]::IsNullOrWhiteSpace($LinuxHost) -or
        [string]::IsNullOrWhiteSpace($LinuxUser)) {
        throw 'Set LinuxHost and LinuxUser at the top of the script.'
    }

    $scp = Get-Command scp.exe -ErrorAction Stop
    $ssh = Get-Command ssh.exe -ErrorAction Stop

    if (-not [string]::IsNullOrWhiteSpace($SshKeyPath) -and
        -not (Test-Path -LiteralPath $SshKeyPath -PathType Leaf)) {
        throw "SSH key file was not found: $SshKeyPath"
    }

    $null = New-Item -ItemType Directory -Path $LocalBackupDirectory -Force

    $archiveName = Split-Path -Path $RemoteArchivePath -Leaf
    $localArchivePath = Join-Path $LocalBackupDirectory $archiveName
    $remoteTarget = '{0}@{1}:{2}' -f $LinuxUser, $LinuxHost, $RemoteArchivePath

    $scpArguments = @('-P', "$SshPort", '-p')
    if (-not [string]::IsNullOrWhiteSpace($SshKeyPath)) {
        $scpArguments += @('-i', $SshKeyPath)
    }
    $scpArguments += @($remoteTarget, $localArchivePath)

    Write-Host "Copying $RemoteArchivePath from $LinuxHost..."
    & $scp.Source @scpArguments
    if ($LASTEXITCODE -ne 0) {
        throw "scp failed with exit code $LASTEXITCODE. The remote archive was not deleted."
    }

    if (-not (Test-Path -LiteralPath $localArchivePath -PathType Leaf)) {
        throw "scp reported success, but the local archive was not found: $localArchivePath. The remote archive was not deleted."
    }

    $localArchive = Get-Item -LiteralPath $localArchivePath
    if ($localArchive.Length -eq 0) {
        throw "The downloaded archive is empty: $localArchivePath. The remote archive was not deleted."
    }

    $sshArguments = @('-p', "$SshPort")
    if (-not [string]::IsNullOrWhiteSpace($SshKeyPath)) {
        $sshArguments += @('-i', $SshKeyPath)
    }
    $remoteCommand = "rm -- '$RemoteArchivePath'"
    $sshArguments += @("$LinuxUser@$LinuxHost", $remoteCommand)

    & $ssh.Source @sshArguments
    if ($LASTEXITCODE -ne 0) {
        throw "The archive was copied to '$localArchivePath', but deleting it from the server failed (ssh exit code $LASTEXITCODE)."
    }

    Write-Host "Backup copied to '$localArchivePath' and deleted from the server."
}
catch {
    Write-Error $_
    exit 1
}
