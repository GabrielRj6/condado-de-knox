# Knox Survival 3D — Godot 4 (Vulkan Forward+ GPU + CPU Multi-Core + Radmin VPN)

Projeto pronto para abrir na Godot 4 e exportar direto para `.exe` (Jogo + Servidor Dedicado).

---

## 1. Como abrir AGORA na tela da Godot que já está aberta

1. Puxe os arquivos novos no **GitHub Desktop** (**Fetch origin → Pull origin**).
2. Na tela inicial da Godot 4, clique em **`Import` (Import Existing Project)**.
3. Clique em **Browse**, navegue até a pasta do seu repositório e selecione:
   `godot/KnoxSurvival3D/project.godot`
4. Clique em **`Import & Edit`**.
5. Assim que o editor abrir, aperte **`F5`** (Play) — o jogo já roda imediatamente!

---

## 2. Como exportar para `.exe` (para mandar aos amigos no Radmin VPN)

Os dois presets de exportação já vêm configurados (`export_presets.cfg`):
1. Na Godot 4, vá em **Editor → Manage Export Templates** → clique em **Download and Install** (baixa uma única vez).
2. Vá em **Project → Export...**:
   - **Windows Desktop (Jogo .exe)** → clique em **Export Project** para gerar `builds/KnoxSurvival3D.exe` (é só mandar esse `.exe` único para seus amigos!).
   - **Windows Dedicated Server (.exe)** → clique em **Export Project** para gerar `builds/KnoxServer.exe` (para deixar o servidor rodando aberto via `START_DEDICATED_SERVER.bat` mesmo se você fechar seu jogo!).

---

## 3. Como jogar com amigos no Radmin VPN (UDP 7777)

- Todos entram na mesma rede do **Radmin VPN**.
- No jogo, aperte **`TAB`**:
  - **Host**: clique em **CRIAR HOST (UDP 7777)** e passe seu IP do Radmin (`26.x.x.x`).
  - **Amigos**: colam seu IP `26.x.x.x` e clicam em **ENTRAR (RADMIN IP)**.
  - **Servidor Dedicado**: rode `START_DEDICATED_SERVER.bat` e todos (inclusive você) entram pelo seu IP do Radmin.

### Liberar Porta UDP 7777 no Firewall do Windows (se um amigo não conectar)
```powershell
New-NetFirewallRule -DisplayName "KnoxGodot UDP 7777" -Direction Inbound -Protocol UDP -LocalPort 7777 -Action Allow
```

---

## 4. Controles
- **`1` a `6` ou Scroll**: Trocar arma (Faca K-Bar, Pistola 9mm, Escopeta 12G, M4A1, AK-47, Sniper .50)
- **Botão Esq.**: Atirar · **Botão Dir.**: Mira (ADS) · **`R`**: Recarregar · **`X`**: Silenciador
- **`V`**: Alternar 1ª / 3ª Pessoa · **`Q`**: Trocar Ombro · **`F`**: Lanterna / Farol
- **`E`**: Entrar / Sair de Carro ou Moto (`Shift + E` entra direto de Garupa/Passageiro)
- **`G`**: Trocar Assento (Piloto ↔ Garupa) · **`H`**: Buzina 3D · **`Espaço`**: Pular / Drift
- **`M`**: Mapa Tático Completo (zoom `+`/`−`, marcadores, rota GPS no veículo e visibilidade **só do mesmo time**)
- **`TAB`**: Menu Radmin (Nome salvo, Time, IP, Distância de Visão, Horário Dia/Tarde/Noite, Buscar Cidade Real OSM, Spawn Carro/Motos/Zumbis)
