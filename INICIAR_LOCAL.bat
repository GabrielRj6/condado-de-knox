@echo off
setlocal
cd /d "%~dp0"
if not defined PORT set "PORT=3000"
call npm ls --depth=0 >nul 2>&1
if errorlevel 1 (
  call npm ci
  if errorlevel 1 goto :erro
)
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $portNumber=[int]$env:PORT; if ($portNumber -lt 1 -or $portNumber -gt 65535) { throw 'Porta invalida' }; $adapters=@(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and ($_.InterfaceDescription -like '*ZeroTier*' -or $_.Name -like '*ZeroTier*') }); if (!$adapters) { Write-Host 'ZeroTier sem adaptador ativo. Confira sua rede ZeroTier.' }; foreach ($a in $adapters) { Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Where-Object { $_.AddressState -eq 'Preferred' } | ForEach-Object { Write-Host ('Link para seus amigos: http://{0}:{1}' -f $_.IPAddress,$portNumber) }; $rule='Knox-ZeroTier-'+$a.InterfaceGuid+'-'+$portNumber; if (!(Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue)) { if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { New-NetFirewallRule -Name $rule -DisplayName ('Condado de Knox - ZeroTier TCP '+$portNumber) -Direction Inbound -Action Allow -Protocol TCP -LocalPort $portNumber -InterfaceAlias $a.Name -Profile Any | Out-Null } else { Write-Host 'Para criar a regra do Firewall do Windows, execute este BAT uma vez como administrador.' } } }"
if errorlevel 1 goto :erro
start "" "http://localhost:%PORT%"
node server.mjs
:erro
pause
