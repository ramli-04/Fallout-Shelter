# Offline temporary announcement. No network/TTS service is contacted.
Add-Type -AssemblyName System.Speech
$warningAssetRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets/audio/warnings'
New-Item -ItemType Directory -Path $warningAssetRoot -Force | Out-Null
$warningVoice = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
    $warningVoice.SelectVoice('Microsoft Zira Desktop')
    $warningVoice.Rate = 0
    $warningVoice.Volume = 65
    $warningVoice.SetOutputToWaveFile((Join-Path $warningAssetRoot 'temporary_emergency_broadcast.wav'))
    $warningVoice.Speak('Emergency warning. A nuclear strike is imminent. Seek immediate shelter. Follow emergency personnel. Do not remain outdoors.')
} finally {
    $warningVoice.Dispose()
}
Write-Output 'Normalize with: .venv/Scripts/python.exe tools/generate_warning_audio.py'
