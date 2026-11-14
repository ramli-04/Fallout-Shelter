param([Parameter(Position=0)][ValidateSet('install','download','start','stop','status')][string]$Action='status')
$ErrorActionPreference='Stop'
$projectRoot=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$configuration=Get-Content -LiteralPath (Join-Path $projectRoot 'config/openjev.json') -Raw | ConvertFrom-Json
$toolRoot=Join-Path $projectRoot '.tools/openjev'
$sourceRoot=Join-Path $toolRoot 'source'
$toolPython=Join-Path $toolRoot 'venv/Scripts/python.exe'
$processFile=Join-Path $toolRoot 'process.json'
function Invoke-NativeTool([string]$Executable,[string[]]$Arguments) {
    $ErrorActionPreference='Continue'
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed (exit $LASTEXITCODE)" }
}
Push-Location $projectRoot
try {
    if ($Action -eq 'install') {
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot '.git'))) {
            Invoke-NativeTool git @('clone','--depth','1','--no-checkout',$configuration.repository,$sourceRoot)
        }
        $remote=Invoke-NativeTool git @('-C',$sourceRoot,'remote','get-url','origin')
        if ($remote -ne $configuration.repository) { throw 'Unexpected OpenJev repository' }
        Invoke-NativeTool git @('-C',$sourceRoot,'fetch','--depth','1','origin',$configuration.revision)
        Invoke-NativeTool git @('-C',$sourceRoot,'checkout','--detach',$configuration.revision)
        if (-not (Test-Path -LiteralPath $toolPython)) {
            $bootstrap=Join-Path $projectRoot '.venv/Scripts/python.exe'
            if (-not (Test-Path -LiteralPath $bootstrap)) { $bootstrap='python' }
            Invoke-NativeTool $bootstrap @('-m','venv',(Join-Path $toolRoot 'venv'))
        }
        Invoke-NativeTool $toolPython @('-m','pip','install',"$sourceRoot[laya]")
        Write-Output 'Installed OpenJev. First start downloads the Laya checkpoint.'
        return
    }
    $managedProcess=$null
    if (Test-Path -LiteralPath $processFile) {
        $record=Get-Content -LiteralPath $processFile -Raw | ConvertFrom-Json
        $candidate=Get-Process -Id $record.id -ErrorAction SilentlyContinue
        if ($candidate -and $candidate.Path -eq $toolPython -and $candidate.StartTime.ToUniversalTime().ToString('o') -eq $record.started) { $managedProcess=$candidate }
    }
    if ($Action -eq 'download') {
        if ($managedProcess) { throw 'Stop the managed server before downloading its checkpoint.' }
        Invoke-NativeTool $toolPython @((Join-Path $PSScriptRoot 'download_openjev_model.py'))
    } elseif ($Action -eq 'start') {
        if ($managedProcess) { Write-Output "OpenJev already running (PID $($managedProcess.Id))."; return }
        if (-not (Test-Path -LiteralPath $toolPython)) { throw 'Run ./tools/openjev.ps1 install first.' }
        $launcher=Join-Path $PSScriptRoot 'run_openjev.py'
        $managedProcess=Start-Process -FilePath $toolPython -ArgumentList @('"'+$launcher+'"') -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $toolRoot 'server.log') -RedirectStandardError (Join-Path $toolRoot 'server-error.log') -PassThru
        @{id=$managedProcess.Id;started=$managedProcess.StartTime.ToUniversalTime().ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $processFile
        Write-Output "OpenJev starting locally (PID $($managedProcess.Id)); use ./tools/openjev.ps1 status."
    } elseif ($Action -eq 'stop') {
        if ($managedProcess) {
            # Windows venv's python.exe is a redirector with a child interpreter.
            $children=Get-CimInstance Win32_Process -Filter "ParentProcessId=$($managedProcess.Id)"
            foreach ($child in $children) {
                if ($child.CommandLine -like '*run_openjev.py*') { Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue }
            }
            Stop-Process -Id $managedProcess.Id -ErrorAction SilentlyContinue
            Write-Output 'Stopped the managed OpenJev server.'
        }
        else { Write-Output 'No managed OpenJev process is running.' }
    } else {
        $endpoint=[Uri]$configuration.endpoint
        try { Invoke-RestMethod -Uri ($endpoint.GetLeftPart([System.UriPartial]::Authority)+'/health') -TimeoutSec 3 | ConvertTo-Json -Depth 4 }
        catch {
            Write-Output $(if ($managedProcess) {'OpenJev is starting or not ready yet.'} else {'OpenJev is not running.'})
            $log=Join-Path $toolRoot 'server-error.log'
            if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 10 }
        }
    }
} finally { Pop-Location }
