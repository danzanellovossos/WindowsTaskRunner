param(
    [Parameter(Mandatory)]
    [string]$TaskName,
    [string]$RDPConfig
)

Start-Transcript -Path "C:\ProgramData\TaskRunner\TaskRunner.log" -Append -Force

function Get-ProcessID {

    $rdpHost = Select-String -Path $RDPConfig -Pattern "^full address:s:(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value }

    $connections = Get-NetTCPConnection -State Established
    $filteredConnections = $connections | Where-Object { $_.RemoteAddress -eq $rdpHost }

    $targetRDPClientPIDs = $filteredConnections | ForEach-Object {
        $_.OwningProcess
    }

    $targetRDPClientPID = $targetRDPClientPIDs | Select-Object -Unique | Select-Object -First 1

    if ($targetRDPClientPID -and $targetRDPClientPID -is [int]) {
        return $targetRDPClientPID
    } elseif ($targetRDPClientPID -and $targetRDPClientPID -isnot [int]) {
        try {
            return [int]$targetRDPClientPID
        } catch {
            Write-Output "Failed to convert PID to integer: $targetRDPClientPID"
            return $null
        }
    } else {
        return $null
    }
}


function Stop-ProcessByPID {

    param (
        [int]$ProcessID
    )

    Write-Output "Attempting to stop process ID: $ProcessID"
    try {
        $process = Get-Process -Id $ProcessID
        $process | Stop-Process -Force
        Write-Output "Process $ProcessID has been terminated."
    } catch {
        Write-Output "Failed to terminate process $ProcessID. Error: $_"
    }

}

function Disconnect-UserSessions {

    Write-Host "Disconnecting all sessions for user: $env:USERNAME"
    query user | ForEach-Object {
        if ($_ -match $env:USERNAME) {
            $sessionId = ($_ -split '\s+')[2]
            logoff $sessionId
        }
    }

    $sessionInfo = query user
    Write-Host "=== Session Info After Disconnecting All Sessions ==="
    Write-Host $sessionInfo

}

function Start-RDPSession {

    Start-Process -FilePath mstsc.exe -ArgumentList $RDPConfig -WindowStyle Hidden
    Start-Sleep -Seconds 5
    $sessionInfo = query user
    Write-Host "=== Session Info After Connection Attempt ==="
    Write-Host $sessionInfo

}

function Disconnect-RDPSession {

    Write-Host "Disconnecting target RDP Session"

    $targetRDPClientPID = Get-ProcessID
    if ($targetRDPClientPID) {
        Write-Output "Found PID $targetRDPClientPID for IP $RDPHost"
        Stop-ProcessByPID -ProcessID $targetRDPClientPID
    } else {
        Write-Output "No connection found for IP $RDPHost"
    }

}

function Start-Task {

    Write-Host "Invoking task: $TaskName"
    schtasks /run /tn $TaskName

}

function Wait-TaskCompletion {

    Write-Host "Waiting for task '$TaskName' to complete..."

    do {

        Start-Sleep -Seconds 5
        $taskStatus = schtasks /query /tn $TaskName /fo LIST /v | Select-String "Status"

    } while ($taskStatus -match "Running")

    Write-Host "Task '$TaskName' has completed."

}

Write-Host "Run Task Event Received"

$sessionInfo = query user
Write-Host "=== Session Info Before Task Execution ==="
Write-Host $sessionInfo

if ($RDPConfig) {
    Disconnect-UserSessions
    Start-RDPSession
}

Start-Task
Wait-TaskCompletion

if ($RDPConfig) {
    Disconnect-RDPSession
}