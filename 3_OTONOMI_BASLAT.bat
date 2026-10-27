@echo off
title TEKNOFEST 2026 - IHAILOS Otonomi
set "IHAILOS_DIR=%~dp0..\IHAILOS"
if exist "%IHAILOS_DIR%" (
    cd /d "%IHAILOS_DIR%"
)
python main.py --synthetic --duration 20
pause
