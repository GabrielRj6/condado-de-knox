# 🌲 CONDADO DE KNOX — Roadmap de Melhorias (para Google AI Studio)

> **Como usar este arquivo:** envie este `.md` junto com o código do jogo (`public/index.html`, `api/servers.js`, `server.mjs`, `vercel.json`) para o Google AI Studio e peça: *"Leia o MELHORIAS_KNOX.md, analise o código atual e implemente a Fase X."* Faça **uma fase por vez** e teste antes de ir para a próxima.

---

## 0. Instruções para a IA (leia primeiro)

**Contexto do projeto**
- Jogo de sobrevivência 3D estilo DayZ / Project Zomboid, rodando no navegador (Three.js / WebGL).
- Multiplayer P2P via WebRTC (PeerJS) + listagem de salas em `api/servers.js` (Vercel Serverless, região `gru1`).
- Modelos `.GLB` em `public/GUNS/` e `public/MODELOS PERSONAGENS/` (carregados via Git LFS).
- Arquivo principal do jogo: `public/index.html`.
- Controles atuais (não quebrar): WASD, Shift, Ctrl/C, Espaço, botão direito (mira), Z, V, R, E, TAB/B, P, F, Alt, N, ESC.

**Regras obrigatórias**
1. **Primeiro leia o código inteiro** e liste os sistemas que já existem (mapa procedural, rede, carros, zumbis, inventário, áudio sintético, HUD) antes de alterar qualquer coisa.
2. **Não remover nem quebrar** funcionalidades existentes. Se algo precisar ser substituído (ex.: tecla `N`), explique o motivo.
3. **Sem etapa de build.** Tem que continuar funcionando só com arquivos estáticos na Vercel e com `INICIAR_LOCAL.bat`. Bibliotecas só via CDN/ESM.
4. **Nada de `Math.random()` na geração do mundo.** Use PRNG com seed (ex.: `mulberry32`) e hash inteiro. Todos os jogadores precisam gerar **exatamente o mesmo mundo** a partir da mesma seed.
5. **Configuração centralizada.** Valores de balanceamento (fome, dano, velocidade de zumbi, distâncias) devem ficar em objetos de config no topo do arquivo (`CONFIG`, `BALANCE`, `ZOMBIE_TYPES`), nunca espalhados pelo código.
6. **Performance alvo:** 60 FPS em PC médio e 30+ FPS em notebook fraco no preset "Baixo".
7. **Entrega:** como o `index.html` é grande, se a resposta não couber, entregue **por blocos/seções**, dizendo exatamente *onde* colar cada trecho. Ao final de cada fase, liste: o que mudou, o que testar, e riscos conhecidos.
8. **Multiplayer sempre em mente:** toda feature nova precisa dizer o que é sincronizado, por qual canal e com que frequência.

---

## 1. Ordem de implementação sugerida

| Fase | Tema | Por que nessa ordem |
| :-- | :-- | :-- |
| 0 | Base: `CONFIG` central, PRNG com seed, sistema de eventos | Tudo abaixo depende disso |
| 1 | Menu de Configurações robusto | Os outros sistemas vão ler dele (distância, volume, etc.) |
| 2 | Mundo por chunks + escolha de spawn | Muda a base do mapa e da rede |
| 3 | Renderização suave (LOD / fim do "popando") | Precisa dos chunks prontos |
| 4 | Sincronização multiplayer completa | Depende de chunks (área de interesse) |
| 5 | Sistema de sobrevivência | Independente, mas usa HUD e config |
| 6 | Sistema de combate | Usa ruído/stamina/status da fase 5 |
| 7 | Tipos de zumbis + IA | Usa combate, ruído e chunks |

---

## 2. FASE 1 — Menu de Configurações robusto (ESC → Configurações)

**Objetivo:** tela de configurações completa, com abas, aplicada em tempo real e salva no navegador.

**Estrutura sugerida:** abas laterais — `Áudio | Gráficos | Controles | Jogabilidade | Multiplayer | Acessibilidade`. Botões: **Aplicar**, **Restaurar padrão**, **Exportar/Importar** (JSON).

### 2.1 Áudio
O jogo usa áudio sintético (WebAudio). Criar **barramentos (buses)** com `GainNode` por categoria, todos ligados a um `master`:

- Volume Geral (master)
- Música / Trilha ambiente
- Efeitos de armas
- Passos e movimentação
- Zumbis (rosnados, gritos)
- Veículos (motor, buzina, batida)
- Ambiente (vento, chuva, grilos, noite)
- Interface (cliques, alertas)
- Voz/Chat (se houver no futuro)

Extras úteis:
- Botão **"Testar som"** em cada categoria.
- **Silenciar ao perder o foco** da aba (opção).
- Opção de **áudio 3D/espacial** ligado/desligado (`PannerNode`) e distância máxima de audição.
- Compressor/limitador no master para tiros não estourarem o áudio.
- Opção "Reduzir sons graves" (para fones ruins) via filtro.

### 2.2 Gráficos
- **Presets:** Baixo / Médio / Alto / Ultra / Personalizado.
- Distância de renderização (ver Fase 3) — slider em metros.
- Qualidade de sombras (Desligado / Baixa / Média / Alta) e distância das sombras.
- Anti-aliasing (ligado/desligado) — exige recriar o renderer; avisar "requer reinício".
- **Escala de resolução** (50%–100%+) via `renderer.setPixelRatio` / tamanho do canvas.
- Limite de FPS (30 / 60 / 120 / ilimitado) e VSync.
- FOV (60–110) separado para 1ª e 3ª pessoa.
- Névoa (densidade), qualidade de partículas, densidade de vegetação/props.
- Qualidade de LOD (quão cedo troca para modelo simples).
- Máximo de luzes dinâmicas (lanternas e faróis — ver Fase 4).
- Mostrar FPS / ping / uso de memória (overlay de debug).

### 2.3 Controles
- **Remapeamento de teclas** (clicar na ação → apertar a nova tecla), com detecção de conflito.
- Sensibilidade do mouse (geral, mira ADS, mira em carro).
- Inverter eixo Y, suavização de mira.
- Alternar vs. segurar: agachar, mirar, correr.

### 2.4 Jogabilidade
- HUD: ligar/desligar elementos (barra de status, mini-mapa, mira, marcador de dano).
- Tamanho do HUD, opacidade.
- Unidades (metros/pés), formato de hora (24h/12h).
- Dificuldade (afeta `BALANCE` — ver Fase 5): Casual / Normal / Hardcore.
- Câmera: tremor de câmera (headbob) ligado/desligado, intensidade.

### 2.5 Multiplayer
- Apelido (nick), cor do personagem.
- Mostrar nomes sobre jogadores (sempre / só aliados / nunca) e distância.
- Mostrar ping e estado da conexão.
- Código da sala visível com botão **Copiar**.

### 2.6 Acessibilidade
- Modo daltônico (paleta do HUD), legendas para sons importantes (ex.: "zumbi gritando à esquerda"), reduzir flash/tremor.

### 2.7 Persistência
```js
// Exemplo de estrutura (adaptar ao código existente)
const DEFAULT_SETTINGS = {
  version: 1,
  audio:   { master: 0.8, music: 0.5, weapons: 0.9, steps: 0.7, zombies: 0.8, vehicles: 0.8, ambient: 0.6, ui: 0.7, muteOnBlur: true },
  graphics:{ preset: 'medium', renderDistance: 400, shadows: 'medium', resolutionScale: 1.0, fpsCap: 60, fovFirst: 80, fovThird: 70, fog: 1.0, maxDynamicLights: 6 },
  controls:{ sensitivity: 1.0, adsSensitivity: 0.6, invertY: false, keys: { /* ação → tecla */ } },
  gameplay:{ difficulty: 'normal', hud: { minimap: true, crosshair: true, status: true }, headbob: true },
  multiplayer:{ nick: '', showNames: 'allies' },
  access:  { colorblind: 'off', subtitles: false, reduceShake: false }
};
// salvar em localStorage com a chave 'knox.settings.v1' e fazer merge com DEFAULT_SETTINGS ao carregar
```
**Critério de aceite:** mexer em qualquer slider muda o jogo na hora; fechar e abrir o navegador mantém tudo; botão "Restaurar padrão" funciona.

---

## 3. FASE 2 — Mundo por chunks + escolher onde nascer

### 3.1 Conceito: mundo "inteiro" virtual + chunks sob demanda
Gerar o mundo todo de uma vez na memória é inviável. A solução: o mundo **existe inteiro por matemática** (seed + funções determinísticas) e cada **chunk só é materializado (meshes, props, loot, zumbis) quando alguém está perto**. Para o jogador, é como se o mundo todo estivesse gerado.

- **Seed do mundo:** o host define a seed (ou digita/aleatória) e envia no handshake; todos geram igual. A tecla `N` passa a ser "nova seed" (só host/solo).
- **Tamanho do mundo configurável** (sugestão): Pequeno 4×4 km · Médio 8×8 km · Grande 16×16 km.
- **Tamanho do chunk (sugestão):** 64 m ou 128 m. Raio de chunks ativos ligado à "Distância de renderização" das configurações.
- **Seed por chunk:** `chunkSeed = hash(worldSeed, cx, cz)` → mesmo chunk sempre igual para todos.
- **Macro-mapa (gerado uma vez, em baixa resolução, ex.: 512×512):** relevo/bioma, água, estradas principais, localização e nome das cidades/vilas. Os chunks consultam o macro-mapa para saber o que construir. Esse mesmo macro-mapa alimenta a tela de escolha de spawn e o mini-mapa.
- **Streaming:** carregar chunks em anel ao redor do jogador, **descarregar** os distantes (devolver geometria/materiais, usar pool de objetos).
- **Estado persistente (diffs):** o que o jogador alterou (loot pego, porta aberta, carro destruído, corpo no chão) é guardado como "diferenças" por chunk, aplicadas por cima da geração base. Isso também é o que o host manda para quem entra depois.

### 3.2 Dicas técnicas
- Gerar chunks em **Web Worker** (ruído/terreno/colocação de props) e só montar as meshes na thread principal, **com orçamento de ms por frame**.
- Usar `InstancedMesh` para árvores, postes, cercas, props repetidos; `BufferGeometryUtils.mergeGeometries` para prédios estáticos.
- **Origem flutuante (floating origin):** se o mundo passar de ~5 km, mover o mundo em vez do jogador de tempos em tempos para evitar tremedeira por precisão de float.
- Evitar funções que variam entre navegadores na geração (`Math.sin` pode diferir em casos extremos). Preferir **hash inteiro** + ruído próprio.
- Física/colisão só para chunks próximos do jogador (e dos outros jogadores, no host).

### 3.3 Tela de escolha de spawn
Exibida ao entrar na sala e ao **respawnar** depois de morrer.

- Mapa 2D (canvas) desenhado a partir do macro-mapa: relevo, água, estradas, cidades com nome.
- **Zoom e arrastar**; clique para escolher o ponto de nascimento; botão **"Aleatório"**.
- **Regiões nomeadas** (ex.: nomes inspirados em cidades brasileiras como Cuiabá, Fortaleza etc., ou nomes fictícios — a definir). Dica: cada região pode ter dificuldade/loot diferente (cidade grande = mais loot e mais zumbis; interior = calmo, pouco loot).
- Validar o ponto: precisa ser terra firme, fora de construção/água; ajustar para o ponto válido mais próximo.
- **Cada jogador nasce onde quiser**, independente dos outros (um em "Cuiabá", outro em outra região).
- Regras opcionais (ligar/desligar pelo host): distância mínima entre spawns de jogadores não aliados; opção "nascer perto de um aliado".
- **Tela de carregamento:** antes de liberar o jogador, pré-carregar os chunks ao redor do ponto escolhido (barra de progresso) para ele não cair no vazio.
- Mostrar no mapa os pontos de spawn de aliados (se houver esquadrão).

### 3.4 Impacto no multiplayer
- Cada cliente envia `spawn{x,z}` ao host; o host valida e passa a **simular zumbis/loot dos chunks ativos de TODOS os jogadores** (não só os dele).
- **Área de interesse (AOI):** só enviar a cada jogador os dados de entidades dentro do raio dele (chunks próximos). Jogadores longe um do outro quase não trocam dados.
- `api/servers.js` deve guardar também **seed e tamanho do mundo** para mostrar na lista de salas.

**Critério de aceite:** dois jogadores nascem em lugares diferentes do mapa, cada um vê o mundo igual (mesmas casas/estradas), e ao se aproximarem se enxergam normalmente.

---

## 4. FASE 3 — Renderização suave (acabar com casas e detalhes "popando" na frente)

**Diagnóstico provável:** a geometria detalhada dos prédios está sendo criada tarde demais (quando o jogador já está perto) e de uma vez só, aparecendo de repente e causando engasgos.

### 4.1 Soluções combinadas
1. **Anel de pré-carga maior que o raio de visão:** começar a construir o chunk *antes* de ele entrar na tela (ex.: raio de carga = raio visível + 2 chunks).
2. **Time-slicing:** fila de tarefas com orçamento (ex.: 3–4 ms por frame). Nada de construir um prédio inteiro num frame só.
3. **Fade-in suave:** objetos novos entram com transição (opacidade/dithering, ~0.4–0.8 s) em vez de aparecer de repente. Dica: `alphaHash`/dither no material ou animar `opacity` por poucos frames.
4. **Névoa de distância** para esconder a borda do mundo carregado (a cor da névoa acompanha o céu/hora do dia).
5. **Pré-aquecer shaders:** `renderer.compile(scene, camera)` ao carregar e ao criar materiais novos, para evitar travada na primeira vez que algo aparece.
6. **Pré-carregar GLBs** (armas e zumbis) na tela de loading; clonar com `SkeletonUtils.clone` em vez de recarregar.
7. **Evitar GC:** reutilizar vetores/geometrias (pools), não criar objetos novos todo frame.

### 4.2 LOD (níveis de detalhe) por distância — sugestão
| Distância | O que renderiza |
| :-- | :-- |
| 0–40 m | Tudo: interior, mobília, props, portas funcionais, sombras |
| 40–120 m | Casca do prédio (paredes, janelas, telhado), **sem interior**, sem sombras |
| 120–300 m | Volume simplificado (mesclado/instanciado), cor/textura básica |
| 300 m+ | Silhueta / impostor (billboard) coberta pela névoa |
| Além do raio | Descarregado |

- **Casca primeiro, interior depois:** montar o exterior do prédio ao entrar no anel médio; o interior só quando o jogador chegar a ~40 m (ou ao se aproximar da porta).
- Frustum culling, e culling por oclusão simples (não renderizar interior se jogador está fora e porta fechada).
- Os limiares de LOD devem **escalar com a "Distância de renderização" e a "Qualidade de LOD"** das configurações.

**Critério de aceite:** andar de carro em alta velocidade e a pé não mostra construções ou detalhes surgindo bruscamente; nenhuma travada visível ao atravessar fronteira de chunk.

---

## 5. FASE 4 — Sincronização multiplayer completa

### 5.1 Princípios
- **Host autoritativo** para: zumbis, dano, loot, carros, hora do dia. Clientes enviam *intenções*; o host valida.
- **Dois canais PeerJS por conexão:**
  - *Não confiável* (`reliable: false`) → estado contínuo: posição, rotação, velocidade (10–20 Hz).
  - *Confiável* (`reliable: true`) → eventos: ligar farol, tiro, pegar item, morte, abrir porta.
- **Bitmask de flags** no pacote de estado (1 número com vários on/off: lanterna, agachado, mirando, correndo, farol, etc.) para economizar banda.
- **Quantizar** posições (ex.: 1/100 m) e ângulos (ex.: 1 byte).
- **Interpolação** (buffer de ~100 ms) no cliente para movimento suave.
- **Snapshot ao entrar (late join):** host envia estado completo (hora, carros, portas abertas, diffs dos chunks próximos, jogadores).
- **Interesse por área (AOI):** enviar só o que está perto de cada jogador.

### 5.2 Lista do que precisa ser sincronizado
| Item | Tipo | Observações |
| :-- | :-- | :-- |
| **Farol do carro** (ligado/desligado/alto) | flag + evento | **Bug atual:** quem liga, o outro jogador não vê. Renderizar nos clientes. |
| Lanterna `F` do jogador | flag | Ver limite de luzes abaixo |
| Buzina, motor (RPM), derrapagem, freio de mão | evento/estado | Som 3D no cliente conforme RPM/velocidade |
| Posição/rotação/velocidade do carro | estado | Interpolar; quem dirige é a fonte |
| Motorista e passageiros | evento | Entrar/sair, banco ocupado |
| Vida do carro, fogo, explosão | evento | Explosão = evento único + física local |
| Portas de casas e de carros | evento | Também entra nos diffs do chunk |
| Arma equipada e anexos visíveis (mira, silenciador) | estado | Modelo certo na mão do outro jogador |
| Pose: agachado, mirando, recarregando, correndo, pulando | flags | Animação no cliente remoto |
| Tiros (origem, direção, arma) | evento | Cliente remoto mostra flash, som, tracer, impacto; **dano validado no host** |
| Golpe de faca / corpo a corpo | evento | |
| Loot: pegar, soltar, containers | evento + diff | Evita item duplicado |
| Zumbis: posição, estado, animação, vida | estado (host → clientes) | Clientes só interpolam |
| Hora do dia e clima | estado (baixa freq.) | Sincronizar com o host |
| Mortes, corpos com loot, respawn | evento | |
| Esquadrão (aliança), dano amigo | evento | |
| Status do jogador (vida, sangramento) | estado | Para barra acima de aliados, etc. |

### 5.3 ⚠️ Limite de luzes dinâmicas
Muitas `SpotLight`/`PointLight` derrubam o FPS. Sugestão:
- Só as **N luzes mais próximas** (config `maxDynamicLights`) são luzes reais; as demais viram **mesh emissivo / sprite de brilho** (barato).
- Faróis e lanternas **sem sombra** (ou só a do próprio jogador, se o preset permitir).

**Critério de aceite:** ligar farol/lanterna, abrir porta, trocar de arma e entrar em carro aparecem corretamente para todos os jogadores, inclusive para quem entrou depois.

---

## 6. FASE 5 — Sistema de sobrevivência (fome, sede e mais)

**Objetivo:** sobreviver ser mais do que atirar. Tudo configurável em um objeto `BALANCE` e escalado pela dificuldade.

### 6.1 Necessidades básicas
| Status | Comportamento sugerido |
| :-- | :-- |
| **Fome** | Cai com o tempo; cai mais correndo/lutando. Fome baixa → menos stamina; zero → perde vida lentamente. |
| **Sede** | Cai mais rápido que a fome. Sede baixa → visão turva/stamina menor; zero → perde vida. |
| **Energia/Fadiga** | Cai com esforço; recupera descansando. Opcional: sono. |
| **Stamina** | Correr, pular, golpear e carregar peso gastam; regenera parado/agachado. |
| **Temperatura** | Afetada por clima, noite, chuva, roupa e fogueira. Frio/calor extremo causa efeitos. |

Pontos de partida (ajustar jogando): fome esgota em ~45–60 min de jogo parado, sede em ~30–40 min; correr multiplica o gasto em ~1.5×.

### 6.2 Ferimentos e condições
- **Sangramento:** vida cai até usar bandagem; tem ícone e som de gotejar.
- **Fraturas:** perna quebrada → só anda devagar/mancando; precisa de tala/analgésico.
- **Infecção:** mordida/ferida suja → infecção; precisa de antibiótico ou desinfetante.
- **Dor/choque:** vida baixa → visão com vinheta e respiração pesada.
- **Doença:** beber água suja ou comer comida estragada.

### 6.3 Itens e crafting
- **Comida:** enlatados, frutas, carne crua/cozida (estraga com o tempo), barras.
- **Água:** garrafas, água suja (precisa ferver/purificar), cantil.
- **Médicos:** bandagem, kit médico, antibiótico, analgésico, tala.
- **Fogueira:** acender, cozinhar, ferver água, se aquecer (gera luz e atrai zumbis).
- **Roupas:** isolamento térmico, resistência a chuva, bolsos (aumentam capacidade).
- **Peso/capacidade:** limite de carga; excesso reduz stamina e velocidade.
- **Validade/estragar:** comida perecível com timer.
- Crafting simples: rasgar pano → bandagem; ferver água; amarrar tala etc.

### 6.4 Morte e respawn
- Ao morrer, deixa **corpo com o inventário** no local; novo personagem escolhe spawn de novo (Fase 2).
- Opção de dificuldade: Casual (mantém parte do loot) / Hardcore (perde tudo).

### 6.5 HUD
- Ícones de status (fome, sede, sangue, temperatura, stamina) que **mudam de cor/pulsam** quando críticos; sem poluir a tela (configurável nas opções).
- Indicadores de condição (sangrando, quebrado, infectado) ao lado da barra de vida.

**Sincronização:** status ficam locais (cada um controla o seu), mas **vida, sangramento e morte** são enviados para os outros.

---

## 7. FASE 6 — Sistema de combate

### 7.1 Armas de fogo
- **Dano por região do corpo:** cabeça (×2–3), tronco (×1), membros (×0.6) — valem para jogadores e zumbis.
- **Recuo e dispersão:** recuo vertical/horizontal, dispersão aumenta ao correr/pular/atirar em rajada e diminui agachado/mirando (ADS).
- **Balanço da arma (sway)** respirando, afetado por stamina e peso.
- **Tipos de munição** (padrão, perfurante) com impacto no dano e alcance.
- **Queda de projétil e velocidade** (opcional: projétil real em vez de hitscan nas armas de longo alcance).
- **Durabilidade** da arma (degrada com uso) e **enrosco/falha** ocasional se estiver muito gasta.
- **Recarga tática:** com/sem bala na câmara (recarga mais rápida se ainda tem bala).
- Anexos (já existem) com efeitos reais: mira (zoom), silenciador (menos ruído, menos alcance), lanterna na arma, coronha (menos recuo).

### 7.2 Corpo a corpo (faca KA-BAR e outras)
- Ataque rápido vs. ataque carregado; gasta **stamina**.
- Armas improvisadas: pé de cabra, machado, taco, pá (cada uma com dano, velocidade e durabilidade).
- Golpe pelas costas/zumbi desatento = dano alto (execução silenciosa).
- Empurrar/chutar zumbi para ganhar distância.

### 7.3 Ruído (liga combate à IA)
- Cada ação gera **raio de ruído** (config): tiro sem silenciador (grande), com silenciador (pequeno), correr, bater em porta, buzina, explosão de carro.
- Zumbis dentro do raio vão **investigar a origem do som**. Agachado reduz o ruído dos passos.
- Isso torna silenciador/faca/stealth estrategicamente úteis.

### 7.4 Feedback e polimento
- **Hitmarker** (som + marcador diferente para acerto na cabeça/morte).
- **Indicador direcional de dano** (seta vermelha de onde veio o golpe).
- Efeitos: sangue, impacto em superfície, ejeção de cartucho, flash de boca de cano, tracer.
- Câmera: tremor ao tomar dano, vinheta de dor, som abafado com vida baixa.
- Mira em 3ª pessoa (OTS) com colisão para não atirar através da parede da câmera.

### 7.5 PvP e rede
- **Host valida os tiros** (origem, direção, alcance, linha de visão) para reduzir trapaça.
- Compensação simples de lag (considerar posição do alvo ~ping/2 atrás).
- Aliados (Esquadrão, tecla `P`) **não** sofrem fogo amigo.

---

## 8. FASE 7 — Tipos de zumbis + IA

### 8.1 Tipos (os com ★ são sugestões extras, remover se não quiser)
| Tipo | Vel. | Vida | Dano | Comportamento | Dica visual/sonora |
| :-- | :-- | :-- | :-- | :-- | :-- |
| **Caminhante** (padrão) | Lenta | Média | Baixo | Vaga pelo mapa; segue som/visão | Rosnado grave |
| **Corredor / Rápido** | Muito rápida | Baixa | Médio | Dispara em linha reta; perde o rastro mais fácil | Magro, grito agudo |
| **Saltador** | Média + pulos | Baixa | Médio | **Pula** sobre obstáculos/cercas e em cima do jogador; tem *cooldown* e *aviso* antes do pulo (agacha e grunhe) | Postura encolhida, som de "mola" |
| **Gigante / Brutamontes** | Lenta | **Muito alta** | **Alto** | Arrebenta portas e **amassa carros**; empurra o jogador; ataque em área | Escala ~1.6–2×, passos que tremem a câmera |
| ★ **Rastejante** | Lenta | Baixa | Baixo | Rasteja, difícil de ver, ataca pernas (pode causar fratura) | Baixo, arrasta |
| ★ **Gritador** | Média | Baixa | Baixo | Ao ver o jogador **grita e atrai hordas** em raio grande — prioridade para eliminar | Grito alto |
| ★ **Inchado / Explosivo** | Lenta | Média | Área | Explode ao morrer/perto, dano em área e atrai zumbis | Corpo dilatado |
| ★ **Blindado** (policial/militar) | Média | Alta | Médio | Resistente a tiro no tronco; fraco na cabeça/pernas | Colete/capacete |

Os números reais ficam em `ZOMBIE_TYPES` (vida, velocidade, dano, alcance de visão/audição, escala, peso de spawn).

```js
// Exemplo de estrutura (adaptar)
const ZOMBIE_TYPES = {
  walker:  { hp: 100, speed: 1.2, damage: 10, hearing: 40, sight: 25, scale: 1.0, spawnWeight: 60 },
  runner:  { hp: 60,  speed: 4.8, damage: 12, hearing: 55, sight: 35, scale: 0.95, spawnWeight: 20, nightBonus: 2.0 },
  jumper:  { hp: 70,  speed: 3.2, damage: 15, jumpCooldown: 4.0, jumpRange: 8, spawnWeight: 10 },
  brute:   { hp: 600, speed: 1.6, damage: 45, breaksDoors: true, hitsVehicles: true, scale: 1.7, spawnWeight: 3 },
};
```

### 8.2 Como fazer com os modelos .GLB existentes
- Reaproveitar o modelo base e variar por **escala**, **cor/tint do material** e **velocidade das animações** (`timeScale`) — evita carregar modelos novos.
- Gigante = mesmo modelo em escala maior + material mais escuro/pele danificada.
- Saltador: usar animação de pulo/queda do próprio rig ou gerar o salto por script (parábola) com animação de "agachar" antes.
- Se tiver modelos novos no futuro, entram por `ZOMBIE_TYPES[tipo].model`.

### 8.3 IA (máquina de estados)
`Ocioso/Vagando → Investigando (som) → Perseguindo → Atacando → Procurando (perdeu o alvo) → Voltando a vagar`

- **Percepção:** visão (cone + distância + linha de visão, reduzida no escuro e agachado), audição (raio de ruído da Fase 6), opcional olfato/sangue.
- **Hordas:** gritos e tiros altos "acordam" zumbis próximos em cadeia.
- **Obstáculos:** contornar paredes, atravessar portas abertas, quebrar portas fechadas (brutamontes), pular cercas (saltador). Pathfinding simples em grid ou *steering* + raycast.
- **Spawn por chunk:** densidade maior em cidades, menor no interior; mais corredores à noite; chance baixa de gigante/gritador; **despawn** quando todos os jogadores estão longe; teto global de zumbis ativos.

### 8.4 Performance e rede
- **LOD de IA:** zumbi longe atualiza a lógica poucas vezes por segundo; muito longe fica "dormindo".
- **LOD de animação:** só animar esqueleto completo dos mais próximos (ex.: 30–40); os outros em taxa reduzida.
- Reaproveitar zumbis (pool) em vez de criar/destruir.
- **Rede:** o host simula; clientes só recebem posição/estado/animação com interpolação (AOI por chunk).

**Critério de aceite:** dá para diferenciar cada tipo de longe (silhueta/som), cada um exige tática diferente, e o FPS se mantém estável com hordas.

---

## 9. Checklist final de testes

- [ ] Configurações salvam, aplicam em tempo real e restauram padrão.
- [ ] Dois jogadores, spawns em regiões distantes, mundo idêntico para ambos.
- [ ] Entrar na sala depois (late join) mostra tudo no estado atual (portas, carros, loot).
- [ ] Farol do carro e lanterna aparecem para todos.
- [ ] Sem construções "popando"; sem travadas ao cruzar chunks.
- [ ] FPS estável nos presets Baixo e Alto; memória não cresce indefinidamente ao andar pelo mapa (chunks descarregam).
- [ ] Fome/sede/sangramento funcionam e afetam o jogo; morte gera corpo com loot.
- [ ] Combate: dano por região, ruído atraindo zumbis, silenciador útil.
- [ ] Todos os tipos de zumbi funcionando e sincronizados.
- [ ] Deploy na Vercel continua funcionando (sem build, GLB via LFS).

---

## 10. Decisões em aberto (preencher antes de começar)

1. **Tamanho do mundo padrão:** Pequeno (4 km) / Médio (8 km) / Grande (16 km)? → _______
2. **Tamanho do chunk:** 64 m ou 128 m? → _______
3. **Nomes das regiões/cidades de spawn:** reais (ex.: Cuiabá…) ou fictícios? → _______
4. **Dificuldade padrão e perda de loot ao morrer:** _______
5. **Quais zumbis ★ extras manter:** _______
6. **Armas brancas improvisadas a incluir:** _______
