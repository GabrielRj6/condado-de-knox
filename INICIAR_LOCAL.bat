@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Condado de Knox - Servidor Local (ZeroTier / LAN)

echo ============================================================
echo   CONDADO DE KNOX - SERVIDOR LOCAL (PORTA 3000)
echo ============================================================
echo.

set "PORT=3000"
set "ZT_IP="
set "LAN_IP="

for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$zt = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -match 'ZeroTier' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1 -ExpandProperty IPAddress; if (-not $zt) { $zt = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '10.147.*' } | Select-Object -First 1 -ExpandProperty IPAddress }; if ($zt) { Write-Output $zt }"`) do set "ZT_IP=%%I"

for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$lan = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notmatch 'ZeroTier|vEthernet|Loopback' } | Select-Object -First 1 -ExpandProperty IPAddress; if ($lan) { Write-Output $lan }"`) do set "LAN_IP=%%I"

if defined ZT_IP (
  echo [ZeroTier] IP detectado: !ZT_IP!
  echo [Firewall] Configurando regra para porta %PORT% no IP !ZT_IP!...
  netsh advfirewall firewall delete rule name="Condado de Knox Local 3000" >nul 2>&1
  netsh advfirewall firewall add rule name="Condado de Knox Local 3000" dir=in action=allow protocol=TCP localport=%PORT% localip=!ZT_IP! >nul 2>&1
  if errorlevel 1 (
    echo [AVISO] Windows recusou a regra do Firewall ^(execute como Administrador para liberar amigos via ZeroTier^).
    echo         Continuando inicializacao do servidor local...
  ) else (
    echo [Firewall] Regra liberada com sucesso para !ZT_IP!:%PORT%.
  )
) else (
  echo [ZeroTier] Nenhum adaptador ZeroTier detectado. Iniciando em modo localhost/LAN.
)

echo.
echo   Acesso local:      http://localhost:%PORT%
if defined ZT_IP echo   Link ZeroTier:     http://!ZT_IP!:%PORT%
if defined LAN_IP echo   Link Rede Local:   http://!LAN_IP!:%PORT%
echo.
echo   Mantenha esta janela aberta enquanto joga.
echo ============================================================
echo.

start "" "http://localhost:%PORT%"
node server.mjs
pause
