[CmdletBinding()]
param(
    [string]$Path = (Get-Location).Path,
    [int]$DebounceSeconds = 3,
    [string]$Remote = 'origin',
    [string]$Branch = '',
    [string]$LogFile = '',
    [switch]$Push,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$script:LogFile = $LogFile

function Write-Log {
    param([string]$Message)
    $line = ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    Write-Host $line
    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )
    $output = & git -C $RepoPath @Arguments 2>&1
    $code = $LASTEXITCODE
    return [PSCustomObject]@{
        ExitCode = $code
        Output   = ($output | Out-String).Trim()
    }
}

function Test-Repo {
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $script:RepoPath = $resolved
    $isRepo = Invoke-Git @('rev-parse', '--is-inside-work-tree')
    if ($isRepo.ExitCode -ne 0) {
        throw "Path is not inside a Git working tree: $Path"
    }

    if ([string]::IsNullOrWhiteSpace($Branch)) {
        $b = Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')
        if ($b.ExitCode -ne 0 -or $b.Output -eq 'HEAD') {
            throw 'Could not determine the current branch (detached HEAD?). Pass -Branch explicitly.'
        }
        $script:Branch = $b.Output
    }

    $remotes = Invoke-Git @('remote')
    $script:HasRemote = ($remotes.ExitCode -eq 0 -and ($remotes.Output -split "\r?\n") -contains $Remote)
}

function Sync-Git {
    $status = Invoke-Git @('status', '--porcelain')
    if ($status.ExitCode -ne 0) {
        Write-Log ("git status failed: " + $status.Output)
        return
    }

    if ([string]::IsNullOrWhiteSpace($status.Output)) {
        return
    }

    Write-Log 'Changes detected; committing.'
    $add = Invoke-Git @('add', '-A')
    if ($add.ExitCode -ne 0) {
        Write-Log ("git add failed: " + $add.Output)
        return
    }

    $message = "auto sync {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $commit = Invoke-Git @('commit', '-m', $message)
    if ($commit.ExitCode -ne 0) {
        Write-Log ("git commit failed: " + $commit.Output)
        return
    }
    Write-Log ("Committed: " + $message)

    if (-not $Push) {
        return
    }

    if (-not $HasRemote) {
        Write-Log "Remote '$Remote' not found; skipping push."
        return
    }

    $current = Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($current.ExitCode -ne 0 -or $current.Output -eq 'HEAD') {
        Write-Log 'Current HEAD is detached; skipping push.'
        return
    }

    $push = Invoke-Git @('push', '-u', $Remote, $current.Output)
    if ($push.ExitCode -ne 0) {
        Write-Log ("git push failed: " + $push.Output)
    } else {
        Write-Log ("Pushed to $Remote/" + $current.Output + ".")
    }
}

try {
    Test-Repo
    Write-Log ("Watching repository: " + $RepoPath)
    Write-Log ("Branch: $Branch; Remote: $Remote; Push: $Push")

    if ($Once) {
        Sync-Git
        exit 0
    }

    $watcher = New-Object System.IO.FileSystemWatcher $RepoPath
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName `
        -bor [System.IO.NotifyFilters]::LastWrite `
        -bor [System.IO.NotifyFilters]::DirectoryName `
        -bor [System.IO.NotifyFilters]::CreationTime

    $gitDir = [IO.Path]::DirectorySeparatorChar.ToString() + '.git' + [IO.Path]::DirectorySeparatorChar.ToString()
    $gitDirEnd = [IO.Path]::DirectorySeparatorChar.ToString() + '.git'

    Register-ObjectEvent -InputObject $watcher -EventName 'Changed' | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName 'Created' | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName 'Deleted' | Out-Null
    Register-ObjectEvent -InputObject $watcher -EventName 'Renamed' | Out-Null
    $watcher.EnableRaisingEvents = $true

    Write-Log 'Auto-sync is running. Press Ctrl+C to stop.'

    $lastChange = [DateTime]::MinValue
    while ($true) {
        $evt = Wait-Event -Timeout 1
        while ($null -ne $evt) {
            $full = $evt.SourceEventArgs.FullPath
            if (-not ($full.Contains($gitDir) -or $full.EndsWith($gitDirEnd))) {
                $lastChange = Get-Date
            }
            Remove-Event -EventIdentifier $evt.EventIdentifier
            $evt = Wait-Event -Timeout 0
        }

        if ($lastChange -ne [DateTime]::MinValue -and
            ((Get-Date) - $lastChange).TotalSeconds -ge $DebounceSeconds) {
            $lastChange = [DateTime]::MinValue
            try {
                Sync-Git
            } catch {
                Write-Log ("Sync error: " + $_.Exception.Message)
            }
        }
    }
}
finally {
    Get-EventSubscriber | Where-Object { $_.SourceObject -is [System.IO.FileSystemWatcher] } |
        ForEach-Object { Unregister-Event -SubscriptionId $_.SubscriptionId -ErrorAction SilentlyContinue }
}
