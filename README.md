# 🌲 CONDADO DE KNOX // Sobrevivência Multiplayer Estilo DayZ & Project Zomboid

Protótipo tático de sobrevivência em 3D (WebGL / Three.js) com geração de mapa procedural, combate em primeira e terceira pessoa, zumbis, 10 armas 3D reais (.GLB), inventário com anexos (miras, silenciadores, etc.), carros dirigíveis com atropelamento frontal/física de explosão, e multiplayer online P2P via WebRTC (PeerJS) e Vercel Serverless.

---

## 🚀 Como Hospedar no Vercel (Passo a Passo)

O projeto foi 100% configurado para rodar na Vercel com 0 configurações complexas:

### 1. Conecte o repositório na Vercel
1. Acesse [vercel.com](https://vercel.com) e faça login com sua conta do GitHub.
2. Clique em **"Add New..." -> "Project"**.
3. Selecione o repositório **`condado-de-knox`**.
4. Framework Preset: Deixe em **"Other"**.
5. Root Directory: Deixe como `./` (raiz).
6. Clique em **Deploy**.

### 2. ⚠️ ATIVAÇÃO OBRIGATÓRIA DO GIT LFS NA VERCEL (Para carregar os modelos 3D .GLB)
Como as armas e os zumbis são modelos 3D reais (.GLB) gerenciados pelo Git LFS:
1. No painel do seu projeto na Vercel, vá na aba **Settings**.
2. No menu lateral esquerdo, clique em **Git**.
3. Role até a seção **"Git Large File Storage (LFS)"**.
4. Ative a opção (**Enable**).
5. Depois de ativar, vá na aba **Deployments**, clique nos `...` do último deploy e selecione **Redeploy** (para que a Vercel baixe os arquivos binários reais do LFS).

Pronto! Seu link (ex: `https://condado-de-knox.vercel.app`) já estará no ar para você e seus amigos jogarem!

---

## 🌐 Como Funciona o Multiplayer

O multiplayer utiliza uma arquitetura híbrida de alta performance e baixo custo:
1. **P2P via WebRTC (PeerJS):** Sincronização em tempo real de movimento, tiro, inventário, dano PvP, carros e zumbis diretamente entre os navegadores (sem lag de servidor intermediário).
2. **Descoberta Dupla de Servidores:**
   - **API Serverless Vercel (`/api/servers`):** Registra salas ativas na região `gru1` (São Paulo, Brasil).
   - **Slots Públicos WebRTC (`knox-br-room-1` a `6`):** Caso a API esteja em cold-start, o jogo varre slots públicos P2P diretamente.
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

## 💻 Como Rodar Localmente no seu Computador

Caso queira testar ou programar offline:
1. Dê dois cliques em **`INICIAR_LOCAL.bat`**.
2. O navegador abrirá automaticamente em `http://localhost:3000`.
3. Para parar o servidor, basta fechar a janela do terminal.

---

## 📦 Estrutura do Projeto

```
condado-de-knox/
├── index.html              # Jogo completo (Three.js WebGL, áudio sintético, HUD, P2P)
├── server.mjs              # Servidor local Node.js (com suporte completo a MIME .glb)
├── INICIAR_LOCAL.bat       # Inicializador rápido de 1 clique
├── vercel.json             # Configuração da Vercel (região SP gru1 + cache imutável de .GLB)
├── package.json            # Metadados do projeto
├── api/
│   └── servers.js          # Rota Serverless da Vercel para listagem de salas
├── GUNS/                   # Modelos 3D (.glb) das 10 armas de fogo
│   ├── ak-47-tactical-upgrade.glb
│   ├── akm-assault-rifle-game-ready-model.glb
│   ├── ar-15-style-rifle.glb
│   ├── assault-rifle-m4a1.glb
│   ├── hk-mp5-smg.glb
│   ├── lr-300-ml-a-assault-rifle.glb
│   ├── ps1-double-barrel-shotgun-1840.glb
│   ├── ps1-style-awp-sniper.glb
│   ├── ps1-style-sawn-off-shotgun.glb
│   └── psx-magnum-44.glb
└── MODELOS PERSONAGENS/    # Modelos 3D (.glb) dos Zumbis
    ├── zombie.glb
    └── zombie2.glb
```
