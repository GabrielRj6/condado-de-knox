@echo off
title Knox Survival 3D - Servidor Dedicado (Radmin VPN)
echo ============================================================
echo   KNOX SURVIVAL 3D - SERVIDOR DEDICADO (RADMIN VPN UDP 7777)
echo ============================================================
echo.
echo O servidor continua aberto mesmo se voce fechar o jogo!
echo Passe seu IP do Radmin VPN (ex: 26.x.x.x) para seus amigos.
echo Pressione CTRL+C nesta janela para encerrar o servidor.
echo.

if exist "KnoxServer.exe" (
    KnoxServer.exe -batchmode -nographics -dedicated -port 7777 -lat -23.5505 -lng -46.6333 -area 1.0 -logfile server_log.txt
) else (
    echo [ERRO] KnoxServer.exe nao encontrado nesta pasta!
    echo Gere a build Dedicated Server (Windows) no Unity como "KnoxServer.exe" e coloque aqui.
    pause
)
