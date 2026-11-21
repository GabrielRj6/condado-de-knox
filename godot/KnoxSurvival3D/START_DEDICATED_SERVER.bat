@echo off
title Knox Survival 3D - Servidor Dedicado Godot (Radmin VPN)
echo ===============================================================
echo   KNOX SURVIVAL 3D (GODOT 4) - SERVIDOR DEDICADO (RADMIN VPN)
echo ===============================================================
echo.
echo O servidor continua aberto mesmo se voce fechar o jogo!
echo Passe seu IP do Radmin VPN (ex: 26.x.x.x) na porta UDP 7777.
echo Pressione CTRL+C nesta janela para encerrar o servidor.
echo.

if exist "KnoxServer.exe" (
    KnoxServer.exe --headless -- --dedicated --port 7777
) else (
    echo [INFO] KnoxServer.exe nao encontrado; tentando rodar direto pelo Godot no PATH...
    godot --headless --path "%~dp0" -- --dedicated --port 7777
    if errorlevel 1 (
        echo.
        echo [ERRO] Exporte o jogo no Godot como "KnoxServer.exe" nesta pasta
        echo ou adicione o executavel do Godot ao PATH do Windows.
        pause
    )
)
