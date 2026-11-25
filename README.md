# 🌲 CONDADO DE KNOX // Sobrevivência Multiplayer Estilo DayZ & Project Zomboid

Protótipo tático de sobrevivência em 3D (WebGL / Three.js) com geração de mapa procedural, combate em primeira e terceira pessoa, zumbis, 10 armas 3D reais (.GLB), inventário com anexos (miras, silenciadores, etc.), carros dirigíveis com atropelamento frontal/física de explosão, e multiplayer online P2P via WebRTC (PeerJS) e descoberta de salas no servidor Node.js local.

---

## Rodar e testar localmente

Instale Node.js 24 e Git LFS. Na raiz do projeto, execute:

```sh
git lfs install --local
git lfs pull
npm ci
npm test
npm run dev
```

Abra `http://localhost:3000`. No Windows, depois de preparar os modelos com Git LFS, também é possível usar `INICIAR_LOCAL.bat`. O servidor entrega as bibliotecas e os modelos pelo próprio computador. Mapas reais usam serviços externos.

**Jogar pelo ZeroTier no Windows.** Conecte os computadores à mesma rede ZeroTier autorizada. No PC anfitrião, execute o BAT uma vez como administrador para liberar a porta TCP do jogo na interface ZeroTier. Copie o link exibido no terminal para seus amigos e mantenha a janela aberta. Crie uma sala no menu do jogo. Os amigos abrem o link no navegador, atualizam a lista e entram na sala. O jogo e a sinalização usam o mesmo IP e porta. A conexão de dados entre os navegadores usa WebRTC.

## 🌐 Como Funciona o Multiplayer

O multiplayer utiliza uma arquitetura híbrida de alta performance e baixo custo:
1. **P2P via WebRTC (PeerJS):** Sincronização em tempo real de movimento, tiro, inventário, dano PvP, carros e zumbis diretamente entre os navegadores (sem lag de servidor intermediário).
2. **Descoberta Dupla de Servidores:**
   - **API local (`/api/servers`):** Registra salas ativas na memória do servidor Node.
   - **Slots locais WebRTC (`knox-br-room-1` a `6`):** Caso a API esteja indisponível, o jogo varre os slots P2P do anfitrião diretamente.
   - **Entrada por Código Direto:** Você pode copiar o ID da sala e enviar para um amigo colar no campo "Ou cole o ID/Código direto da sala".
3. **Sistema de Esquadrão / Time (Tecla P):**
   - Todos nascem como sobreviventes neutros (estilo DayZ).
   - Pressione **P** para abrir a janela de Esquadrão, ver jogadores próximos e enviar convite de aliança.
   - Aliados ganham identificador visual e não sofrem dano acidental.

---

## 🎮 Controles

| Tecla / Ação | Função |
| :--- | :--- |
| **W, A, S, D** | Movimentação / Direção do veículo |
| **Shift** | Correr a pé / Acelerar carro |
| **Ctrl ou C** | Agachar (estratégico para menor ruído e mira firme) |
| **Espaço** | Pular a pé / Freio de mão no carro |
| **Botão Direito** | Mira Tática OTS (3ª Pessoa) ou Mira de Ferro Real ADS (1ª Pessoa) |
| **Z** | Alternar modo de mira 1ª Pessoa direta (ADS) |
| **V** | Alternar Câmera (1ª Pessoa vs 3ª Pessoa) |
| **Botão Esquerdo** | Disparar arma / Golpe de faca KA-BAR |
| **R** | Recarregar munição |
| **E** | Interagir: Pegar loot, abrir/fechar portas, entrar/sair de veículos |
| **TAB ou B** | Abrir Inventário de Sobrevivência & Loot |
| **P** | Menu de Esquadrão / Time Multiplayer |
| **F** | Lanterna tática |
| **Alt (Segurar)** | Câmera livre / Olhar ao redor sem girar o corpo |
| **N** | Gerar novo mapa procedural (apenas Host/Solo) |
| **ESC** | Menu principal / Lista de servidores / Configurações |

---

## 📦 Estrutura do Projeto

```
condado-de-knox/
├── server.mjs              # Servidor local Node.js (com suporte a public/ e MIME .glb)
├── INICIAR_LOCAL.bat       # Inicializador rápido de 1 clique
├── vercel.json             # Desativa deploys automáticos pelo Git
├── package.json            # Metadados do projeto
├── api/
│   └── servers.js          # Rota do servidor local para listagem de salas
└── public/                 # Pasta estática do jogo (servida na raiz /)
    ├── index.html          # Jogo completo (Three.js WebGL, áudio sintético, HUD, P2P)
    ├── GUNS/               # Modelos 3D (.glb) das 10 armas de fogo
    └── MODELOS PERSONAGENS/# Modelos 3D (.glb) dos Zumbis
```
