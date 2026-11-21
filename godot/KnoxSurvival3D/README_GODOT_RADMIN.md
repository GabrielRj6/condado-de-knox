# Knox Survival 3D — Godot 4 (Forward+) + Radmin VPN

Projeto completo em **Godot 4** (sem nenhum plugin externo, sem Asset Store, sem instalador pesado).

---

## 1. Como abrir em menos de 1 minuto

1. Baixe a **Godot 4 (Standard — ~60 MB, arquivo único `.exe`)** em: `https://godotengine.org/download/windows/`
2. Dê `git pull` na sua pasta do projeto.
3. Abra o executável da Godot 4 → clique em **Import (Importar)** → selecione o arquivo:
   `godot/KnoxSurvival3D/project.godot`
4. Clique em **Edit** e aperte **F5** (Play)! **Já funciona imediatamente — sem baixar nenhum pacote extra!**

---

## 2. Como jogar online com amigos via Radmin VPN (UDP 7777)

### Modo Host Rápido
1. Conecte-se com seus amigos na mesma rede do **Radmin VPN**.
2. Copie seu IP do Radmin (ex: `26.142.88.15`).
3. No jogo (Menu `TAB`), clique em **CRIAR SERVIDOR (HOST UDP 7777)**.
4. Seus amigos digitam seu IP `26.x.x.x` e clicam em **ENTRAR NO SERVIDOR**.

### Modo Servidor Dedicado (continua aberto se você fechar o jogo!)
- Exporte o projeto para Windows (**Project → Export → Windows Desktop**) como `KnoxServer.exe` na pasta `godot/KnoxSurvival3D/` e dê dois cliques em **`START_DEDICATED_SERVER.bat`**.
- Ou rode direto pela linha de comando do Godot sem precisar exportar:
  `Godot_v4.x_win64.exe --headless --path "godot/KnoxSurvival3D" -- --dedicated --port 7777`
- Você e seus amigos entram no seu IP do Radmin (`26.x.x.x`). Se você cair ou fechar seu jogo, a sala continua aberta e você reconecta normalmente!

### Liberar Porta UDP 7777 no Firewall do Windows (se necessário)
```powershell
New-NetFirewallRule -DisplayName "KnoxGodot UDP 7777" -Direction Inbound -Protocol UDP -LocalPort 7777 -Action Allow
```

---

## 3. Controles
- **WASD**: Andar / Dirigir · **Shift**: Correr · **Ctrl / C**: Agachar · **Espaço**: Pular / Freio de Mão & Drift
- **Botão Esq.**: Atirar (som 3D direcional para todos!) · **V**: Alternar 1ª / 3ª Pessoa · **Q**: Trocar Ombro
- **E**: Entrar / Sair de Carro ou Moto (`Shift + E` entra direto como Passageiro/Garupa)
- **G**: Trocar de Assento (ex: Piloto ↔ Garupa) · **H**: Buzina 3D · **F**: Lanterna / Farol
- **M**: Mapa Tático Completo (zoom `+`/`−`, marcadores, rota GPS no veículo e visibilidade **exclusiva para o mesmo time**)
- **TAB**: Menu Radmin (Nome salvo, Time, IP, Horário Dia/Tarde/Noite, Carregar Cidade Real OSM, Spawnar Carro/Motos/Zumbis para todos)
