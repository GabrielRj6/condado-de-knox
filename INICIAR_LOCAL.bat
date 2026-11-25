@echo off
setlocal
cd /d "%~dp0"
if not defined PORT set "PORT=3000"
call npm ls --depth=0 >nul 2>&1
if errorlevel 1 (
  call npm ci
  if errorlevel 1 goto :erro
)
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0tools\configurar-zerotier.ps1"
if errorlevel 1 echo Aviso: confira o ZeroTier e o Firewall se seus amigos nao conseguirem entrar.
start "" "http://localhost:%PORT%"
node server.mjs
:erro
pause
