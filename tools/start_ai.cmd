@echo off
cd /d "%~dp0.."
if not exist .venv\Scripts\python.exe py -m venv .venv
.venv\Scripts\python.exe -m pip install -r ai_service\requirements.txt
.venv\Scripts\python.exe -m uvicorn ai_service.main:app --host 127.0.0.1 --port 8765
pause
