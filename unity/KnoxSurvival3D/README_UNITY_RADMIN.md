# Knox Survival 3D — Unity 6 (URP) + FishNet + Radmin VPN

Base oficial em **Unity 6 LTS (URP)** com **FishNet v4 (Tugboat UDP)** pronta para multiplayer de alta performance via **Radmin VPN** e **Servidor Dedicado persistente**.

---

## 1. Como abrir no seu PC (Passo a Passo)

1. No seu PC, dê `git pull` na pasta do projeto.
2. Abra o **Unity Hub**:
   - Se quiser criar o projeto do zero no Unity Hub: crie um projeto **Universal 3D (URP)** no Unity 6 LTS e copie a pasta `Assets/Scripts` daqui para dentro do seu projeto; **OU**
   - Copie o conteúdo de `unity/KnoxSurvival3D/Assets/Scripts` para dentro de `Assets/Scripts` do seu projeto URP recém-criado.
3. No **Unity Editor**, instale os pacotes necessários:
   - **Window → Package Manager → Unity Registry**:
     - `AI Navigation` (para NavMesh dos zumbis)
     - `TextMeshPro` (geralmente já vem instalado)
   - **Asset Store (gratuito)**:
     - Pesquise **Fish-Networking (FishNet v4)** → *Add to My Assets* → *Open in Unity* → **Import**.
4. **Ative Forward+ para a noite sem lag** (dezenas de postes de luz e faróis):
   - Em `Assets/Settings/PC_Renderer.asset` (seu URP Renderer): troque **Rendering Path** de *Forward* para **Forward+**.
5. **Auto-Setup em 1 Clique**:
   - No menu superior do Unity, clique em:
     **`Knox Survival → 1. Criar Cena Completa (Radmin + FishNet)`**
   - Ele cria automaticamente: `NetworkManager` (com transporte **Tugboat UDP** na porta `7777`), Prefab do Sobrevivente, Prefab do Carro (4 lugares), Prefab da Moto Trail 450 (Piloto + Garupa), Prefab do Zumbi, Carregador de Mapa Real (OSM) e HUD de conexão Radmin.
6. Dê **Play** no Unity para testar na hora!

---

## 2. Como hospedar via Radmin VPN (sem erro de peer!)

### Modo Host Rápido (jogar + hospedar no mesmo executável)
1. Abra o **Radmin VPN**, crie uma rede e passe o nome/senha para seus amigos.
2. Pegue seu IP do Radmin (ex: `26.142.88.15`).
3. No jogo, clique em **CRIAR SERVIDOR (HOST)** — ele abre na porta UDP `7777`.
4. Seus amigos colocam o seu IP `26.142.88.15` no campo de IP e clicam em **ENTRAR NO SERVIDOR**.

### Modo Servidor Dedicado (continua aberto mesmo se você fechar o jogo!)
1. No Unity: **File → Build Profiles → Windows → Dedicated Server** → gere o executável como `KnoxServer.exe` na mesma pasta de `START_DEDICATED_SERVER.bat`.
2. Dê dois cliques em **`START_DEDICATED_SERVER.bat`**.
3. O servidor sobe em segundo plano (sem gastar placa de vídeo!) na porta `7777` UDP.
4. Você e seus amigos entram no IP `26.x.x.x` do Radmin. Se você cair ou fechar seu jogo, **o servidor continua aberto e seus amigos continuam jogando normalmente**; você só abre o jogo e entra de novo.

### Liberar Porta no Firewall do Windows (se algum amigo não conectar)
Abra o PowerShell como Administrador no PC do Host e rode:
```powershell
New-NetFirewallRule -DisplayName "KnoxSurvival UDP 7777" -Direction Inbound -Protocol UDP -LocalPort 7777 -Action Allow
```

---

## 3. Controles
- **WASD**: Mover / Dirigir
- **Shift**: Correr · **C / Ctrl**: Agachar · **Espaço**: Pular / Drift (no veículo)
- **Botão Esq.**: Atirar · **R**: Recarregar · **V**: Alternar 1ª / 3ª Pessoa · **Q**: Trocar Ombro
- **E**: Entrar / Sair de Carro ou Moto · **G**: Trocar de assento (ex: Piloto ↔ Garupa) · **H**: Buzina 3D · **F**: Lanterna / Farol
- **M**: Mapa Tático Completo (zoom `+`/`−`, marcadores, rota GPS no veículo e visibilidade **exclusiva para membros do mesmo time**)
- **Tab**: Menu de Conexão Radmin / Time / Horário do Dia

---

## 4. Arquitetura dos Scripts (`Assets/Scripts/`)
- `Networking/RadminServerManager.cs` — Conexão FishNet v4 + Tugboat UDP, modo Servidor Dedicado (`-dedicated`), salvar nome do sobrevivente (`PlayerPrefs`), sistema de Time/Party e sincronização global de horário/clima.
- `Audio/SpatialAudio3D.cs` — Motor de áudio espacial 3D HRTF: tiros direcionais (esquerda/direita/frente/trás com escurecimento acústico traseiro, atenuação até 500m, atraso da velocidade do som e estalo supersônico de bala), motores contínuos de Carro, Moto Trail 450 e Moto Street 600, buzinas 3D e vozes 3D de zumbis.
- `Player/SurvivorController.cs` — Movimentação 1ª/3ª pessoa, combate sincronizado com o servidor, som de tiro 3D para todos os jogadores, vida/dano e entrada em veículos.
- `Vehicles/VehicleController3D.cs` — Física de Carro (4 lugares) e Moto (Piloto + Garupa), frenagem limpa até `0 km/h`, inclinação realista da moto, alinhamento ao terreno sem flutuar e motor/drift/buzina 3D.
- `Zombies/ZombieAI.cs` — IA autoritativa no Servidor (todos os jogadores veem exatamente os mesmos zumbis), perseguição por visão/som de tiros e vocalizações 3D em todos os estados.
- `World/RealWorldMapLoader.cs` — Carregador assíncrono de mapas reais do OpenStreetMap (ruas + prédios + postes de luz + grafo de rotas GPS) sincronizado do Servidor para todos os Clientes.
- `UI/TacticalFullMapUI.cs` — Mapa tático completo `[M]` com zoom `+`/`−`, marcadores, rota GPS A* nas ruas e filtro estrito de visibilidade apenas para o mesmo time.
- `Editor/KnoxProjectBootstrapEditor.cs` — Ferramenta de 1 clique no Unity Editor para montar a cena jogável e todos os prefabs automaticamente.
