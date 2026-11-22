# 🌲 CONDADO DE KNOX — Atualização 5: Ponto de restauração, limpeza do storage, troca de personagens/zumbis/armas e varredura de bugs

> **Para o Gemini (Antigravity):** siga este arquivo **na ordem**. Cada fase tem um critério de "pronto". Não pule o ponto de restauração.
> **Para o Gabriel:** coloque este arquivo e a pasta `tools/` na raiz do projeto. Depois mande ao Gemini: *"Leia o ATUALIZACAO_5_KNOX.md e execute a Fase 0 e a Fase 1. Pare e me mostre os relatórios antes de apagar qualquer coisa."*

---

## 0. REGRAS (obrigatórias)

1. **Fase 1 (ponto de restauração) vem antes de qualquer mudança.** Sem `✔ Ponto de restauração criado e verificado`, nada é alterado.
2. **Nada é apagado sem estar no ponto de restauração** e sem constar no relatório da auditoria. Arquivos "sem referência" **não são apagados na hora**: ver Fase 3.
3. Mudanças **pequenas e reversíveis**, uma fase por commit (`git commit` com a mensagem indicada em cada fase).
4. Não mude regras de jogo (dano, balanceamento, controles) nesta atualização. Só visual/animação/assets e correção de bugs **claros**.
5. Não execute comandos que apaguem projeto/deployments em massa. A limpeza de deployments da Vercel é feita pelo **painel** (ou CLI **depois de ler `--help`** e com confirmação do Gabriel).
6. Tudo que for incerto vira **pergunta ao Gabriel** na seção "Decisões em aberto" do relatório final, não suposição.
7. Se a Atualização 4 (persistência) já foi aplicada: use a versão **mais recente** de `knox-persistence.js` (que guarda o personagem escolhido, ver Fase 4.6).

**Ordem recomendada com as outras atualizações:** Atualização 2 → **esta (5)** → Atualização 3 (animações/armas novas), porque a 3 será refeita em cima dos assets novos. Se a 3 já foi aplicada, continue; só avise quais animações/armas antigas ela criou, pois serão substituídas.

---

## 1. FASE 0 — Ferramentas

Os dois scripts em `tools/` não têm dependências (Node 18.15+). Rode sempre **dentro da pasta do jogo**.

| Script | Para quê |
| :-- | :-- |
| `tools/knox-restore-point.mjs create \| verify \| diff` | Ponto de restauração (cópia completa fora do projeto + tag + branch + SHA-256) |
| `tools/knox-audit.mjs` | Auditoria: peso, duplicatas, arquivos sem uso, GLB (ossos, clips, texturas), compatibilidade animação × personagem, mudanças recentes |

Adicione ao `.gitignore`: `_audit/` (os relatórios são descartáveis).

---

## 2. FASE 1 — Ponto de restauração

```bash
node tools/knox-restore-point.mjs create --label antes-da-troca
```

O que ele faz:
- copia **o projeto inteiro (com `.git`)** para uma pasta **fora** dele (`<projeto>__RESTORE_antes-da-troca_<data>`), sem `node_modules`, `.vercel`, `_audit` e sem a pasta nova `Personagens Novos e Animações` (que ainda não é "jogo antigo");
- grava `RESTORE_MANIFEST.json` com **SHA-256 de cada arquivo** e confere a cópia logo depois;
- cria a **tag** `restore/antes-da-troca-<data>` e o **branch** `backup/antes-da-troca-<data>` no commit atual;
- **recusa** criar o ponto se achar *ponteiros Git LFS* (arquivo que não é o real). Nesse caso: `git lfs pull` e rode de novo.
- recusa se o destino ficar dentro do projeto, se já existir e não estiver vazio, ou se faltar espaço.

⚠ A tag/branch apontam para o **último commit**. O que estiver **sem commit** só existe na cópia da pasta. Por isso, **antes**, rode `git status`; se houver mudanças que valem, faça commit (`git commit -am "estado antes da troca"`) e **depois** crie o ponto.

Conferir e comparar depois:

```bash
node tools/knox-restore-point.mjs verify "<pasta do ponto>"                 # cópia íntegra?
node tools/knox-restore-point.mjs diff   "<pasta do ponto>" --out _audit/mudancas.md   # o que mudou desde então
```

Como voltar atrás (também está no `RESTORE_README.txt` dentro da cópia):
- **código:** `git switch -c voltar restore/antes-da-troca-<data>`
- **tudo:** copiar o conteúdo da pasta do ponto (menos `RESTORE_*`) por cima do projeto.

**Pronto quando:** `✔ Ponto de restauração criado e verificado` + `verify` com `✔ Cópia íntegra`. Informe ao Gabriel o caminho da cópia e o nome da tag, e sugira copiar a pasta do ponto para um HD/nuvem (ela não vai para o deploy).

> Opcional: `git push origin <tag> <branch>` envia só as referências ao GitHub (sem arquivos novos pesados).

---

## 3. FASE 2 — Diagnóstico do storage da Vercel (10 GB)

### 3.1 O que provavelmente é (fatos da documentação da Vercel)

- Contas **Hobby** têm **10 GB de Deployment Storage**. Cada deployment retido ocupa o **tamanho do que foi publicado** (os arquivos do build/webroot). Ao passar do limite, pode **bloquear novos deploys** e deployments inativos são apagados.
- Uso = **nº de deployments retidos × tamanho do output × tempo**. Ou seja: **cada deploy copia de novo todos os GLB/áudios/texturas do webroot.** Um jogo com 150 MB de assets × 70 deploys ≈ 10 GB.
- Em Hobby, cada projeto mantém os **3 últimos deployments de produção + os 3 últimos de qualquer tipo**, além do deployment de produção atual e dos que tenham alias ou branch ativa.
- Existem outros medidores separados: **Functions Storage**, **Vercel Blob** e **Remote Cache**. Confirme qual encheu.

### 3.2 Para o Gabriel conferir no painel (2 minutos)

1. Team → **Usage** → **Deployment Storage** → aba **Projects**. Anote o projeto mais pesado e se é Deployment Storage, Functions Storage ou Blob.
2. No projeto → **Deployments** → abra um deployment recente → **Resources** (lista de arquivos estáticos e tamanhos). Anote os maiores.
3. Em **Settings → Build and Deployment → Deployment Retention Policy**: reduza Pre-Production (previews) e Canceled/Errored ao mínimo que você usa. *Não* marque "aplicar a todos os projetos" sem querer.
4. Na lista de **Deployments**: apague os previews antigos que não vai usar. **Nunca** apague o deployment de produção atual.
5. Se `git push` está disparando deploys demais (vários commits seguidos, branches abandonadas), desative previews das branches que não precisa.

### 3.3 O que o Gemini faz

```bash
node tools/knox-audit.mjs
```

Ler `_audit/audit-report.md` e resumir em 10 linhas, **com números**:
- tamanho do **webroot** (o que vai em *cada* deploy) e "quantos deploys enchem 10 GB";
- se alguma **pasta nova está dentro do webroot** (a linha "Pastas novas DENTRO do deploy"). Se estiver, **esse é o risco nº 1**: `Personagens Novos e Animações` com originais pesados iria em todo deploy. Corrija agora (3.4);
- duplicatas exatas, arquivos fora do deploy-padrão (`.zip`, `.DS_Store`, `.blend`, `.psd`, `.fbx`), candidatos a não usados, GLBs sem compressão/texturas enormes.

### 3.4 Impedir que originais pesados entrem no deploy

1. Descubra qual é o webroot real (`vercel.json → outputDirectory`, framework, `package.json → build`). O script já tenta detectar; se a raiz inteira for publicada (`webroot = (a raiz inteira)`), tudo que está na raiz vai no deploy.
2. Crie/ajuste **`.vercelignore`** na raiz com, no mínimo:

```
Personagens Novos e Animações/
_audit/
*.zip
*.blend
*.blend1
*.psd
*.fbx
*.DS_Store
```

3. Os **originais** (`Personagens Novos e Animações/`) ficam no repositório/máquina **apenas como fonte**; o jogo só publica as **cópias otimizadas** em `public/assets/v2/` (Fase 4).
4. Se o repositório já contém muita coisa pesada no histórico do Git, **não reescreva o histórico** sem o Gabriel pedir (muda todos os hashes). Apenas pare de adicionar.

**Pronto quando:** relatório lido e resumido, `.vercelignore` criado, e o Gabriel sabe qual medidor encheu.

---

## 4. FASE 3 — Limpeza segura (somente depois da Fase 1)

Use `_audit/audit-report.md`. Classifique cada achado em **A (seguro)**, **B (confirmar)** ou **C (não mexer)**.

| Classe | O que entra | Ação |
| :-- | :-- | :-- |
| **A** | `.DS_Store`, `Thumbs.db`, `*.zip/*.rar` de backup dentro do webroot (o ponto de restauração já guarda tudo) | `git rm` + `.gitignore` |
| **A** | **Duplicatas exatas**: manter **uma** cópia (a que o código referencia); apontar o código para ela e remover as demais | corrigir o caminho no código e só depois remover |
| **B** | **Sem nenhuma referência** no código | listar para o Gabriel com tamanho; remover **só com "ok"** dele. Se confirmar, `git rm` num commit separado (`chore: remove assets sem uso`) |
| **C** | **Referência fraca** (só o nome sem extensão ou a pasta aparece): assets carregados dinamicamente (listas de armas, zumbis, skins) | **não apagar**; investigar como o nome é montado |
| **C** | Tudo que a Fase 4 vai substituir | **fica até a Fase 4 terminar** (ver 5.9) |

Depois de cada remoção: rodar o jogo, abrir o console e confirmar **zero** erros `404`/`Failed to load`. Reexecute `node tools/knox-audit.mjs` e compare o "Vai em CADA deploy".

**Importante:** apagar do repositório **não** libera o storage já usado pelos deploys antigos. Isso só cai com retenção/remoção de deployments (Fase 2.2) e com o próximo deploy menor.

**Pronto quando:** webroot menor, nenhum 404, relatório "antes × depois" em 5 linhas.

---

## 5. FASE 4 — Troca de personagens, zumbis e armas

> **Princípio:** *trocar o visual sem trocar a lógica.* A lógica (vida, dano, IA, rede, colisão) continua; só muda o modelo 3D e a animação que o representa. Tudo atrás de um **manifesto** e de um **carregador único**, para as próximas trocas serem só editar um JSON.

### 5.1 Inventário (Gemini faz e mostra antes de codar)

Rode `node tools/knox-audit.mjs` e use as seções **8 (GLB)**. Monte uma tabela **por arquivo novo**: tipo (personagem/zumbi/arma/animação), ossos, clips (nome e duração), texturas (formato e tamanho), compressão, peso. Responda:
- Cada personagem tem **o mesmo esqueleto** (mesmos nomes de ossos)? E as animações dos zumbis?
- A seção **"Compatibilidade animação × personagem"** mostra `Exato` ou só `Parecido`? (se só `Parecido`, vale a Fase 4.3)
- Quais armas têm clips (`fire`, `reload`, `draw`, `inspect`…)? Têm pontos de encaixe (`muzzle`, `grip`, `mag`)? Se não tiverem, liste como pendência (não invente posições sem testar).

### 5.2 Estrutura final e manifesto

```
public/assets/v2/
  characters/<id>.glb
  zombies/<id>.glb
  anim/characters/*.glb      (só clips, se vierem separados)
  anim/zombies/*.glb
  weapons/<id>.glb
  manifest.json
```

`manifest.json` (exemplo; use os **nomes reais** das pastas do Gabriel como `id`):

```json
{
  "version": 2,
  "characters": [
    { "id": "soldier_01", "name": "Soldado", "file": "characters/soldier_01.glb",
      "scale": 1, "yawOffset": 0, "boneNormalize": true,
      "clips": { "idle": "Idle", "walk": "Walk", "run": "Run", "crouchIdle": "CrouchIdle", "crouchWalk": "CrouchWalk", "prone": "Prone", "jump": "Jump", "death": ["Death_A", "Death_B"] } }
  ],
  "zombies": [
    { "id": "zombie_walker", "file": "zombies/zombie.glb", "scale": 1,
      "clips": { "idle": "Idle", "walk": "Walk", "run": "Run", "attack": ["Attack_A", "Attack_B"], "crawl": "Crawl", "death": ["Death_A", "Death_B"] } }
  ],
  "weapons": [
    { "id": "ak47", "file": "weapons/ak47.glb", "scale": 1, "sockets": { "muzzle": "Muzzle", "grip": "Grip" },
      "clips": { "fire": "Fire", "reload": "Reload", "draw": "Draw" } }
  ]
}
```

Regras: `id` é estável (vai para o save e para a rede). Clips ausentes = `null`; o carregador usa um **fallback** (ex.: `run` → `walk` acelerado) e registra `console.warn` **uma vez**.

### 5.3 Pipeline de otimização (antes de colocar em `public/`)

Os originais ficam em `Personagens Novos e Animações/` (fora do deploy). Gere as cópias de runtime com **glTF-Transform**. As flags abaixo são as do `optimize`; **confirme com `npx @gltf-transform/cli optimize --help` antes**, porque podem variar por versão:

```bash
npx @gltf-transform/cli optimize "origem.glb" "public/assets/v2/characters/soldier_01.glb" \
  --compress meshopt --texture-compress webp --texture-size 1024
```

Metas **sugeridas** (ajuste vendo o visual): personagem ≤ 1–2 MB, zumbi ≤ 1 MB, arma ≤ 1–2 MB, textura ≤ 1024 px (armas em primeiro plano até 2048), nenhuma PNG > 500 KB. **Nunca substituir o original.**

Se usar `meshopt`, o carregador precisa de `loader.setMeshoptDecoder(MeshoptDecoder)` (três.js `examples/jsm/libs/meshopt_decoder.module.js`). WebP dentro do GLB é aceito pelo `GLTFLoader`. KTX2 exige `KTX2Loader` + transcoder (mais trabalho; só se WebP não bastar). **Teste cada modelo no jogo** depois de otimizar: compare visual e animação com o original.

Resultado esperado: o peso total dos assets cai muito. Meça com o `knox-audit` e registre o "antes × depois".

### 5.4 Carregador único (`AssetLibrary`)

Crie **um** módulo (ex.: `src/assets/assetLibrary.js`, ou o equivalente do projeto) que:
1. carrega `manifest.json` e valida (ids únicos, arquivos existem);
2. carrega cada GLB **uma vez** (cache por `id`) com `GLTFLoader` (+ decoders se usados) e mostra progresso (reaproveite a tela de loading);
3. entrega instâncias **clonadas com `SkeletonUtils.clone()`** (nunca `scene.clone()` em modelo com esqueleto, ou todos compartilham os ossos);
4. cria um `AnimationMixer` **por instância** e **compartilha** os `AnimationClip` entre instâncias;
5. **normaliza nomes de ossos** quando `boneNormalize: true`: troca o prefixo (`mixamorig:`, `Armature|`…) e iguala maiúsculas/minúsculas nos nomes das *tracks* (`<osso>.position|quaternion|scale`) para casar com o esqueleto do modelo. **Só funciona se a hierarquia/proporção for a mesma**; senão é preciso *retarget* de verdade (peça ajuda ao Gabriel, não improvise);
6. libera memória: `dispose()` de geometria/material/texturas ao remover (ver 6.4).

### 5.5 Personagens (escolha no spawn)

1. Na **tela de spawn** (Fase 2), adicione a **seleção de personagem** com os itens de `manifest.characters` (nome + miniatura; se não houver miniatura, mostre o modelo girando com `idle`). Pode ser a lista de cards que a tela já usa.
2. O jogo usa o personagem escolhido no boneco local **e** nos bonecos dos outros jogadores (o `characterId` viaja na mensagem de entrada e no estado inicial de cada jogador; os demais clientes carregam o modelo pelo id).
3. Estado de animação ↔ clip: `parado → idle`, `andar → walk`, `correr → run`, `agachado → crouchIdle/crouchWalk`, `deitado → prone`, `pulo → jump`, `morte → death[random]`. Troca com **crossfade** de ~0,15–0,2 s. Mantenha a velocidade da animação proporcional à velocidade real (`timeScale`).
4. Arma na mão: acople o modelo da arma ao osso da mão direita (ex.: `RightHand`) com o **offset** do manifesto. Se o personagem tiver clips de mira/tiro, use; se não, mantenha a pose atual e **liste a pendência**.
5. Primeira pessoa/câmera: confira se o modelo novo não corta a câmera (esconda cabeça/tronco do **próprio** jogador se a câmera for 1ª pessoa, como já é hoje).
6. **Persistência (Atualização 4):** salve `appearance: { characterId }` no save do jogador (o `knox-persistence.js` mais novo já aceita o campo). Ao retomar, o boneco volta com o mesmo personagem. Id inexistente no manifesto → usar o primeiro personagem e `console.warn`.

### 5.6 Zumbis

1. Mapa **estado da IA → clip**: `parado → idle`, `perseguir → walk/run`, `atacar → attack[random]`, `rastejar → crawl` (se existir), `morrer → death[random]`.
2. **Performance** (é o ponto crítico, há muitos zumbis): `SkeletonUtils.clone` por zumbi; atualizar o `mixer` **só dos visíveis/próximos**; zumbis longe atualizam a ~15 Hz ou ficam em pose fixa; limite de zumbis com animação completa (ex.: 40) configurável; reaproveitar (pool) em vez de criar/destruir.
3. **Morte variada**: sortear entre os clips de morte; ao terminar, congelar no último frame (`clampWhenFinished = true`, `LoopOnce`) e só depois aplicar o tempo de despawn do corpo. O **corpo deve poder ser lootado** do jeito que já é hoje.
4. O **hitbox/colisão não muda** (cápsula/caixas atuais). Se o modelo novo for mais alto/largo, ajuste só a **escala** no manifesto, não a lógica de dano. Teste tiro na cabeça/corpo.

### 5.7 Armas

1. Substitua os modelos atuais pelos de `manifest.weapons`, mapeando **por função** (fuzil de assalto, sniper, pistola…). Mostre ao Gabriel a tabela *arma antiga → arma nova* **antes** de aplicar; se houver armas novas sem equivalente, são **armas novas** (adicione ao catálogo com **os mesmos campos** das existentes e valores *provisórios copiados da arma de mesma classe*, marcados `// TODO balanceamento`). Não invente números.
2. O ponto de saída do tiro (`muzzle`), a posição da mira e os efeitos (flash, som, cápsula ejetada) devem sair dos **sockets** do manifesto. Se o GLB não tiver `muzzle`, defina um offset manual **por arma** no manifesto.
3. Animação de arma (`fire`, `reload`, `draw`): dispare no evento correspondente; `reload` deve **durar o tempo de recarga do jogo** (ajuste `timeScale` do clip, não a regra).
4. Attachments (Atualização 3) **não** são tema desta atualização; só deixe os sockets prontos.

### 5.8 Rede

O que viaja: `characterId` (string curta), `weaponId` já existente, estado de animação (se já sincronizado; **não** envie ossos). Cliente desconhecido para um `id` → modelo padrão, sem travar.

### 5.9 Transição segura (sem quebrar o jogo)

1. Enquanto migra, mantenha uma chave `?assets=v1` (modelos antigos) e `?assets=v2` (novos). Padrão `v2` só quando o checklist (5.10) passar.
2. Só depois de **tudo** validado: remova os assets antigos substituídos (num commit `chore: remove assets v1`), rode `knox-audit` e registre o novo peso do webroot.
3. Cada etapa (personagens, zumbis, armas) em **commit separado**, para reverter uma sem perder as outras.

### 5.10 Checklist da Fase 4

- [ ] Todos os personagens aparecem na seleção, spawnam e animam (idle, andar, correr, agachar, deitar, pular, morrer).
- [ ] Os **outros jogadores** veem o personagem escolhido e a animação certa (testar com 2 abas: `?profile=1` e `?profile=2`, se a Atualização 4 estiver aplicada).
- [ ] Sair e voltar mantém o mesmo personagem.
- [ ] Zumbis: andar, correr, atacar, morrer (variado) sem travar; 60 zumbis perto ainda dá FPS aceitável (anote o FPS antes × depois).
- [ ] Cada arma nova: aparece na mão, atira da boca do cano, recarrega, troca de arma sem "teleportar" o modelo.
- [ ] Nenhum erro no console (`Failed to load`, `Cannot read properties of undefined`, `THREE.PropertyBinding: Can not bind`) — o último indica **nome de osso que não casou**.
- [ ] Memória estável após 5 min (ver 6.4).
- [ ] `knox-audit` mostra o peso novo do webroot e **nenhum asset novo sem referência**.

---

## 6. FASE 5 — Varredura total de bugs

### 6.1 Mudanças recentes (primeiro lugar onde há bug)

```bash
git log -n 30 --stat --date=short --pretty=format:"%h %ad %s"
node tools/knox-audit.mjs        # seção "Mudanças recentes"
```

Revise `git diff` dos **últimos commits** (e dos arquivos mais recentes por data). Para cada arquivo alterado, procure: referências a variáveis/funções que mudaram de nome, código novo chamado antes de ser inicializado, `try/catch` vazio, valores `NaN`/`undefined` indo para posição/rotação, `await` esquecido, listeners duplicados.

### 6.2 Análise estática (o que existir no projeto)

- `node --check arquivo.js` em cada JS solto; se houver ESLint/TypeScript no projeto: `npx eslint .` e/ou `npx tsc --noEmit`. **Não** adicione ferramentas novas ao projeto só para isso; rode em modo temporário (`npx`).
- Busque padrões de risco (`grep`/pesquisa no editor) e anote cada ocorrência com arquivo:linha:
  - `console.error`/`catch (e) {}` vazios;
  - `setInterval`/`requestAnimationFrame`/`addEventListener` sem remoção correspondente ao sair do jogo/chunk;
  - `new THREE.*Geometry|Material|Texture` criados dentro de loops de frame (vazamento e GC);
  - arrays/mapas que só crescem (balas, partículas, corpos, mensagens);
  - `Math.random()` em lógica que deveria ser igual para todos (mapa, loot): precisa de seed;
  - `peer.id`/`conn.peer` usados como identidade de jogador (a Atualização 4 troca por `playerId`).

### 6.3 Multiplayer (o host é a autoridade)

- **Dano, munição, loot e inventário**: o host **valida** (alcance, cadência, munição, distância do item). O cliente só envia intenção.
- Posição enviada pelo cliente: o host limita velocidade/teleporte e descarta `NaN`.
- Mensagens malformadas não podem derrubar o host: `try/catch` no handler de rede com `console.warn`, nunca silencioso.
- Desconexão: boneco, veículo, balas e timers do jogador são limpos (sem fantasma).
- Duas ações simultâneas no mesmo item (dois jogadores pegando): só um ganha.

### 6.4 Vazamento de memória e desempenho

1. Abra o jogo, ande por 5 min (atravessando vários chunks), observe **Memory** e **Performance** nas DevTools: o heap deve **estabilizar**.
2. Ao descarregar chunk/zumbi/corpo/projétil: `geometry.dispose()`, `material.dispose()`, `texture.dispose()`, `scene.remove()`, parar o `mixer` (`mixer.stopAllAction(); mixer.uncacheRoot(root)`).
3. Meça `renderer.info` (`geometries`, `textures`, `calls`) antes/depois de andar: **não pode crescer sem parar**.
4. Dê atenção a: número de draw calls, sombras (tamanho do mapa), zumbis animados ao mesmo tempo, partículas de sangue/tiro.

### 6.5 Teste de fumaça no navegador

Abra o jogo com o console aberto e rode, **por no mínimo 3 minutos**, este roteiro: entrar → escolher personagem → andar/correr/agachar/deitar → pegar item → atirar → recarregar → trocar de arma → morrer → renascer → (se houver) entrar/sair de veículo → sair do jogo. **Qualquer** erro vermelho vira item na tabela de bugs. (Opcional: automatizar com Playwright em `npx`, sem adicionar ao projeto.)

### 6.6 Regras para corrigir

- **Bug claro** (erro de console reproduzível, `undefined` óbvio, vazamento comprovado): corrija com a **menor mudança possível**, um commit por correção (`fix: <o que>`), com um teste manual descrito.
- **Dúvida de design** ou correção que mude a regra do jogo: **não corrija**; registre na tabela como "decisão".
- Não faça "limpeza" estética, renomeação em massa ou reescrita.

### 6.7 Relatório de bugs (entregar em `_audit/bugs.md`)

| # | Gravidade | Onde (arquivo:linha) | Sintoma | Causa | Correção feita / sugerida | Como testar |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |

Gravidade: **Crítico** (trava/perde progresso/duplica item), **Alto** (quebra uma função), **Médio** (visual/raro), **Baixo**.

---

## 7. ENTREGA FINAL (o Gemini responde com isto)

1. **Ponto de restauração:** caminho da cópia, nome da tag/branch, resultado do `verify`.
2. **Storage:** webroot antes × depois, causa provável dos 10 GB, o que o Gabriel precisa fazer no painel (Fase 2.2) e o que já foi feito (`.vercelignore`, remoções).
3. **Limpeza:** lista A removida, lista B aguardando "ok", lista C mantida (com motivo).
4. **Troca de assets:** o que foi trocado (personagens, zumbis, armas), o que ficou pendente (clips/sockets que faltam), FPS antes × depois.
5. **Bugs:** a tabela de `_audit/bugs.md`, separando corrigidos e pendentes.
6. **Decisões em aberto** (abaixo), com a recomendação do Gemini.

---

## 8. Decisões em aberto (Gabriel responde)

1. **Onde ficam os assets pesados?** (a) comprimidos dentro do deploy (mais simples; recomendado primeiro), (b) fora do deploy em Vercel Blob/outro CDN (zera o peso por deploy, mas exige URL base, CORS e conferir preço/limite), (c) migrar para plano Pro (cobrado por GB-mês). → _______
2. **Apagar os assets antigos (v1) depois de validar?** (recomendado: sim, no commit separado) → _______
3. **Quantos personagens ficam selecionáveis?** (todos os da pasta?) → _______
4. **Armas novas sem equivalente:** entram como armas novas com valores provisórios da mesma classe? → _______
5. **Zumbis:** limite de zumbis com animação completa perto do jogador? (sugestão: 40) → _______
6. **Atualização 3:** aplicar só **depois** desta troca? (recomendado) → _______
