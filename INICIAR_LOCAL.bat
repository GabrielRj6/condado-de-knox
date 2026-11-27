@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Condado de Knox - Servidor Local (ZeroTier / LAN)
if not defined PORT set "PORT=3000"
call npm ls --depth=0 >nul 2>&1
if errorlevel 1 (
  call npm ci
  if errorlevel 1 goto :erro
)
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0tools\configurar-zerotier.ps1"
if errorlevel 1 echo Aviso: confira o ZeroTier e o Firewall se seus amigos nao conseguirem entrar.

echo ============================================================
echo   CONDADO DE KNOX - SERVIDOR LOCAL (PORTA %PORT%)
echo ============================================================
echo.

set "ZT_IP="
set "LAN_IP="

for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$zt = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -match 'ZeroTier' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1 -ExpandProperty IPAddress; if (-not $zt) { $zt = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '10.147.*' } | Select-Object -First 1 -ExpandProperty IPAddress }; if ($zt) { Write-Output $zt }"`) do set "ZT_IP=%%I"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$lan = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notmatch 'ZeroTier|vEthernet|Loopback' } | Select-Object -First 1 -ExpandProperty IPAddress; if ($lan) { Write-Output $lan }"`) do set "LAN_IP=%%I"

echo   Acesso local:      http://localhost:%PORT%
if defined ZT_IP echo   Link ZeroTier:     http://!ZT_IP!:%PORT%
if defined LAN_IP echo   Link Rede Local:   http://!LAN_IP!:%PORT%
echo.
echo   Mantenha esta janela aberta enquanto joga.
echo ============================================================
echo.
start "" "http://localhost:%PORT%"
node server.mjs
:erro
pause
