param(
    [Parameter(Position=0)]
    [ValidateSet('install','build','query','explain','path','open','status')]
    [string]$Action = 'build',
    [Parameter(Position=1)][string]$Value,
    [Parameter(Position=2)][string]$Target
)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$configuration = Get-Content -LiteralPath (Join-Path $projectRoot 'config/graphify.json') -Raw | ConvertFrom-Json
$toolRoot = Join-Path $projectRoot '.tools/graphify'
$sourceRoot = Join-Path $toolRoot 'source'
$toolPython = Join-Path $toolRoot 'venv/Scripts/python.exe'
$graphifyExe = Join-Path $toolRoot 'venv/Scripts/graphify.exe'

function Invoke-NativeTool([string]$Executable, [string[]]$Arguments) {
    # PowerShell 5.1 turns redirected native stderr (including harmless warnings)
    # into error records. Judge native commands by their exit status.
    $ErrorActionPreference = 'Continue'
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed (exit $LASTEXITCODE)" }
}

Push-Location $projectRoot
try {
    if ($Action -eq 'install') {
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $projectRoot '.tools/.gdignore') -Value ''
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot '.git'))) {
            Invoke-NativeTool git @('clone','--no-checkout','--depth','1',$configuration.repository,$sourceRoot)
        }
        $remote = Invoke-NativeTool git @('-C',$sourceRoot,'remote','get-url','origin')
        if ($remote -ne $configuration.repository) { throw 'Unexpected Graphify repository' }
        Invoke-NativeTool git @('-C',$sourceRoot,'fetch','--depth','1','origin',$configuration.revision)
        Invoke-NativeTool git @('-C',$sourceRoot,'checkout','--detach',$configuration.revision)
        if (-not (Test-Path -LiteralPath $toolPython)) {
            $bootstrapPython = Join-Path $projectRoot '.venv/Scripts/python.exe'
            if (-not (Test-Path -LiteralPath $bootstrapPython)) { $bootstrapPython = 'python' }
            Invoke-NativeTool $bootstrapPython @('-m','venv',(Join-Path $toolRoot 'venv'))
        }
        Invoke-NativeTool $toolPython @('-m','pip','install',$sourceRoot,"tree-sitter-language-pack==$($configuration.language_pack_version)")
        $skillRoot = Join-Path $projectRoot '.codex/skills/graphify'
        New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'graphify/skill-codex.md') -Destination (Join-Path $skillRoot 'SKILL.md') -Force
        Set-Content -LiteralPath (Join-Path $skillRoot '.graphify_version') -Value $configuration.version -Encoding Ascii -NoNewline
        foreach ($notice in @('LICENSE','LICENSE-MIT','NOTICE')) {
            Copy-Item -LiteralPath (Join-Path $sourceRoot $notice) -Destination (Join-Path $skillRoot $notice) -Force
        }
        $referenceRoot = Join-Path $sourceRoot 'graphify/skills/codex/references'
        if (Test-Path -LiteralPath $referenceRoot) {
            Copy-Item -LiteralPath $referenceRoot -Destination $skillRoot -Recurse -Force
        }
        Write-Output 'Graphify installed for this project. Run ./tools/graphify.ps1 build.'
        return
    }
    if (-not (Test-Path -LiteralPath $graphifyExe)) {
        throw 'Graphify is not installed. Run ./tools/graphify.ps1 install first.'
    }
    $previousBackend = $env:GRAPHIFY_BACKEND
    $previousTips = $env:GRAPHIFY_NO_TIPS
    $previousOutput = $env:GRAPHIFY_OUT
    $previousUtf8 = $env:PYTHONUTF8
    try {
        $env:GRAPHIFY_BACKEND = 'none'
        $env:GRAPHIFY_NO_TIPS = '1'
        $env:GRAPHIFY_OUT = $configuration.output
        $env:PYTHONUTF8 = '1'
        switch ($Action) {
            'build' { Invoke-NativeTool $toolPython @((Join-Path $PSScriptRoot 'graphify_essaim.py')) }
            'query' { if (-not $Value) { throw 'Supply a question.' }; Invoke-NativeTool $graphifyExe @('query',$Value) }
            'explain' { if (-not $Value) { throw 'Supply a concept.' }; Invoke-NativeTool $graphifyExe @('explain',$Value) }
            'path' { if (-not $Value -or -not $Target) { throw 'Supply two concepts.' }; Invoke-NativeTool $graphifyExe @('path',$Value,$Target) }
            'status' {
                $graphPath = Join-Path $projectRoot "$($configuration.output)/graph.json"
                if (-not (Test-Path -LiteralPath $graphPath)) { throw 'Build the graph first.' }
                $graph = Get-Content -LiteralPath $graphPath -Raw | ConvertFrom-Json
                $edgeList = if ($null -ne $graph.edges) { $graph.edges } else { $graph.links }
                [pscustomobject]@{Nodes=@($graph.nodes).Count;Edges=@($edgeList).Count;Graph=$graphPath;Version=$configuration.version}
            }
            'open' {
                $htmlPath = Join-Path $projectRoot "$($configuration.output)/graph.html"
                if (-not (Test-Path -LiteralPath $htmlPath)) { throw 'Build the graph first.' }
                Start-Process -FilePath $htmlPath
            }
        }
    } finally {
        $env:GRAPHIFY_BACKEND = $previousBackend
        $env:GRAPHIFY_NO_TIPS = $previousTips
        $env:GRAPHIFY_OUT = $previousOutput
        $env:PYTHONUTF8 = $previousUtf8
    }
} finally { Pop-Location }
