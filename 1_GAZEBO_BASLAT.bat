@echo off
title TEKNOFEST 2026 - Gazebo Harmonic
set "WIN_DIR=%~dp0"
for /f "tokens=*" %%i in ('wsl -d Ubuntu-22.04 wslpath -u "%WIN_DIR:~0,-1%"') do set "WSL_DIR=%%i"
wsl -d Ubuntu-22.04 --cd "%WSL_DIR%" bash -l -c "./scripts/run_gazebo.sh"
pause
