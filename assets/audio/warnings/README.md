# Warning audio assets

No licensed external siren recordings were supplied or downloaded.

| Included file | Source | Duration |
|---|---|---:|
| temporary_civil_defense_wail.wav | Original procedural mechanical-style harmonics with a 12-second rise/fall cycle | 24 s |
| temporary_final_warning.wav | Original procedural fast sweeps and pulses | 8 s |
| temporary_emergency_broadcast.wav | Local Windows System.Speech, Microsoft Zira Desktop; fictional text below, mildly saturated and normalized | 11.45 s |
| temporary_explosion.wav | Original seeded filtered noise and low-frequency rumble | 4 s |

These are clearly named **temporary assets**, not authentic civil-defense recordings. They are mono 16-bit PCM WAV. The three tones use 22,050 Hz; the local speech file uses its Windows synthesis output rate. Tone peaks are capped at 0.35 full scale and speech is normalized below 0.30. Default tower and master gains further reduce level. Warning buses include limiters, including a limiter on the combined warning output. There are no cloud speech calls.

Announcement text:

> Emergency warning. A nuclear strike is imminent. Seek immediate shelter. Follow emergency personnel. Do not remain outdoors.

To use real recordings you have permission to use, place WAV or OGG files here with these basenames: civil_defense_wail, emergency_broadcast, final_warning, explosion. Default paths prefer .ogg, then the matching .wav, then the temporary_* fallback. Or edit audio_paths in resources/warnings.json to other project res:// WAV/OGG paths. Let Godot import the files and restart the game. Keep provenance/permission notes alongside any supplied recordings; no external recording license is asserted by this project.

Match announcement_text to the actual prerecorded words. The engine uses that text for a comprehensible agent observation. If the voice is unintelligible or replaced with a tone, set announcement_comprehensible=false. No WARNING_MESSAGE_RECEIVED observation is generated when that flag is false or the speech resource is absent.

Regenerate the local fallback voice on this Windows machine:

```powershell
powershell -NoProfile -File tools/generate_warning_voice.ps1
.venv/Scripts/python.exe tools/generate_warning_audio.py
```

The generator writes only temporary_* files; it does not overwrite replacement recordings. Microsoft Zira Desktop must be installed for the optional offline voice generator. Included fallback WAVs work without speech synthesis at runtime. Reimport after regeneration.
