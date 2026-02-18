@echo off
title NR MIS Schema Graph Tool
color 0B

echo.
echo  Fetching and launching MIS Schema Graph Tool from GitHub...
echo.

powershell -ExecutionPolicy Bypass -Command "& { $ProgressPreference='SilentlyContinue'; $ps1 = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/NathanielRitchie01/Graph-Theory-Database-Connections/main/Invoke-SchemaGraph' -UseBasicParsing).Content; Invoke-Expression $ps1 }" -FromGitHub

if errorlevel 1 (
    echo.
    echo  Something went wrong. Check your internet connection.
    echo  Repo must be public: github.com/NathanielRitchie01/Graph-Theory-Database-Connections
    echo.
    pause
)
