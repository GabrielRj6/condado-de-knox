# 🌲 CONDADO DE KNOX — Atualização 4: Persistência (progresso salvo enquanto o servidor estiver aberto)

> **Pedido:** todas as modificações que o jogador fizer (coletar armas, itens, mexer no mundo etc.) precisam ficar **salvas enquanto o servidor estiver aberto**. Se ele sair ou cair e voltar para a mesma sala, tudo deve estar como deixou.
>
> **Ordem:** pode ser feita logo depois da Fase 2 e da Atualização 2, pois depende dos *diffs por chunk* (Fase 2) e do inventário. Vale a seção **"0. Instruções para a IA"** do `MELHORIAS_KNOX.md`.
>
> **Como usar:** envie este arquivo + os anteriores + o código ao Google AI Studio e peça: *"Leia o ATUALIZACAO_4_KNOX.md. Antes de mexer, me diga como a identidade do jogador e o inventário funcionam hoje e por que o progresso se perde ao reconectar."*

---

## 1. Regra de ouro

Enquanto a sala estiver aberta, o **host guarda o personagem de cada jogador** (inclusive dos que saíram) e **o que mudou no mundo**. Ao voltar à mesma sala, o jogador retoma **o mesmo personagem**: posição, vida, status, inventário, armas (com munição, durabilidade e attachments), roupas, esquadrão.

---

## 2. Por que provavelmente se perde hoje (a IA deve confirmar no código)

1. O **ID do PeerJS muda a cada conexão**, então o host não reconhece quem voltou.
2. O estado do jogador (inventário, vida, armas) só existe **na memória do cliente**; ao fechar, some.
3. Alterações do mundo vivem dentro do **chunk carregado**; ao descarregar/recarregar o chunk, o item volta ao chão ou o loot "renasce".
4. A tecla `N` (nova seed) e reinício do host regeneram tudo.

---

## 3. Identidade persistente

- No primeiro acesso, o cliente gera e guarda no navegador (`localStorage`): **`playerId`** (UUID) e **`playerToken`** (segredo aleatório).
- O host guarda `playerId → { tokenHash, nick, save }`. Guardar só o **hash** do token (`crypto.subtle`, SHA-256).
- **Handshake ao conectar:** `hello { playerId, token, nick, version }`
  - `playerId` desconhecido → personagem novo (tela de spawn da Fase 2).
  - `playerId` conhecido + token correto → **retomar** (`resume`).
  - token errado → `resume_denied` (impede alguém assumir o personagem de outro).
- **Chave do save:** `worldSeed/roomId + playerId`. Sala diferente = personagem diferente.
- **Conexão duplicada** (F5, duas abas): a conexão nova assume e a antiga é derrubada (`kicked_duplicate`).

---

## 4. Fonte da verdade: o host (anti-duplicação)

- **Nunca restaurar o inventário a partir do `localStorage` do cliente.** Seria trapaça fácil e causaria itens duplicados (o item já saiu do mundo mas "volta" na mochila).
- O cliente envia **intenções** (pegar, soltar, equipar, usar); o **host altera o inventário e grava**.
- Todo item tem **`uid` único**. Mover item é **transação atômica** (sai de um lugar e entra no outro no mesmo passo), para não existir duplicado nem sumido.

---

## 5. O que é salvo

### 5.1 Jogador
| Grupo | Conteúdo |
| :-- | :-- |
| Posição | x, y, z, rotação, postura (em pé/agachado/deitado) |
| Status | vida, fome, sede, stamina, temperatura, sangramento, fraturas, infecção (Fase 5) |
| Inventário | tudo, incluindo **containers aninhados** (mochila, bolsos) |
| Equipamento | arma na mão e nas costas, **attachments, munição no carregador, durabilidade, modo de tiro** |
| Roupas | peças vestidas |
| Social | esquadrão/aliados |
| Estado | vivo/morto, região de spawn escolhida, nick, cor |

### 5.2 Mundo (vale para todos enquanto o servidor estiver aberto)
- **Diffs por chunk:** loot pego/solto, containers abertos, portas abertas, corpos com loot, itens colocados.
- **Veículos:** posição, rotação, combustível, vida/peças, farol, onde ficou estacionado.
- Fogueiras e itens montados; **relógio do jogo e clima**; timers de respawn de loot/zumbis e de despawn de corpos.
- ⚠️ Os diffs ficam em um **store global por `chunkId`**, separado do chunk carregado. Descarregar e recarregar um chunk **não pode** perder nem resetar nada.

---

## 6. Ciclo de vida do jogador

```
Online → queda/saída detectada → TIMER de logout (padrão 30 s) → salvo e removido do mundo
                                      └─ morreu no timer → corpo com loot + save marca "morto"
Volta à sala → hello → resume → snapshot do jogador + do mundo próximo → loading → solta o jogador
```

- **Detecção de saída:** evento `close`/`error` do PeerJS **mais heartbeat** (ex.: sem resposta por 8–10 s), pois a queda do WebRTC pode demorar a ser notificada.
- **Timer de logout (anti "combat log"):** ao sair, o boneco continua no mundo por ~30 s e pode ser morto. Se morrer nesse tempo, ele perde o loot como qualquer morte. Se voltar **dentro do timer** (queda curta de internet), retoma na hora.
- **Ao voltar:** o host envia o save do jogador e o snapshot do mundo ao redor (Fase 4). O cliente mostra **tela de loading** pré-carregando os chunks perto da posição salva (Fase 2) antes de liberar o controle.
- **Se morreu enquanto estava fora:** tela "Você morreu enquanto estava fora"; o corpo fica no local com o loot; escolhe novo spawn (Fase 2) e começa um personagem novo.
- **Se saiu dentro de um veículo:** ao sair do jogo, tirar do banco e colocar em ponto livre ao lado do veículo (checando colisão). O veículo permanece onde está.
- **Posição inválida** (dentro de parede, no ar, chunk mudou): ajustar ao ponto válido mais próximo (mesma função de validação do spawn).
- **Quando salvar (no host, em memória):** a cada evento relevante (pegar, soltar, equipar, usar item, tomar dano, morrer, sair de veículo, trocar de arma), **periodicamente** a cada 5–10 s se houve mudança, e **sempre ao desconectar**.

---

## 7. Tempo offline (decidir)

Enquanto o jogador está fora:
- **Mundo continua:** relógio, clima, timers, corpos e veículos seguem rodando (o servidor está aberto).
- **Sobrevivência do jogador:** sugestão **pausar** fome/sede/temperatura enquanto ele está offline (mais justo). Alternativa: continuar rodando (mais punitivo). Deixar em config:

```js
const OFFLINE_RULES = {
  logoutTimerSec: 30,            // boneco permanece no mundo após sair
  survivalDecayWhileOffline: 'paused',   // 'paused' | 'running'
  keepOfflineBodyVisible: false, // boneco "dormindo" no mapa depois do timer
  saveExpireHours: 72,           // remove saves de quem nunca voltou
  maxSavesPerRoom: 200
};
```

---

## 8. Rede (canal confiável)

| Mensagem | Direção | Conteúdo |
| :-- | :-- | :-- |
| `hello` | cliente → host | playerId, token, nick, versão |
| `resume_ok` | host → cliente | save do jogador + snapshot do mundo próximo |
| `new_character` | host → cliente | personagem novo, abrir tela de spawn |
| `resume_denied` | host → cliente | motivo (token inválido, versão incompatível) |
| `kicked_duplicate` | host → cliente | outra sessão assumiu |
| `server_closed` | host → clientes | servidor encerrado |
| `ping/pong` | ambos | heartbeat |

Saves grandes (inventário cheio) podem ser enviados em partes.

---

## 9. Formato do save (versionado)

```js
const PLAYER_SAVE_V1 = {
  v: 1, playerId: '...', nick: '', color: '#...',
  alive: true, pos: { x: 0, y: 0, z: 0 }, yaw: 0, stance: 'stand',
  stats: { hp: 100, food: 80, water: 70, stamina: 100, temp: 36.6 },
  conditions: ['bleeding'],                       // sangramento, fratura, infecção...
  equipment: { hands: 'uid_12', back: 'uid_30', body: 'uid_5' },
  items: {                                        // todos os itens por uid
    uid_12: { type: 'sniper_bolt', ammoInMag: 3, durability: 87,
              attachments: { optic: 'scope_8x', muzzle: 'suppressor' } },
    uid_30: { type: 'backpack', contains: ['uid_31', 'uid_32'] }
  },
  squad: ['playerId_a'], spawnRegion: '', lastSeen: 0
};
```
O campo `v` permite **migrar** saves antigos quando o formato mudar.

---

## 10. Casos de borda

- **Tecla `N` (nova seed) / reiniciar mundo:** **invalida todos os saves** (a posição e os chunks deixam de existir). Pedir confirmação: *"Isso apaga o progresso de todos os jogadores."* Os saves ficam atrelados à `worldSeed`; se a seed muda, são descartados.
- **Host é jogador também:** usa exatamente o mesmo sistema de save.
- **Limite do P2P:** o "servidor" é a **aba do host**. Se o host fechar ou recarregar, a sala encerra e o progresso se perde; os clientes devem ver "Servidor encerrado" (`server_closed`) em vez de erro genérico.
- **Armas e itens com estado:** munição, durabilidade e attachments precisam estar **no item**, não só no tipo, senão a arma volta zerada.
- **Item largado por jogador offline** continua no mundo como qualquer outro (outros podem pegar).
- **Limites:** teto de saves por sala e expiração de inativos para a memória do host não crescer indefinidamente.

---

## 11. ★ Opcional: sobreviver ao F5 do host

Como o servidor é a aba do host, qualquer recarga dele apaga tudo. Se quiser blindar isso, o host pode gravar o estado (saves + diffs de chunk + veículos + relógio) no **IndexedDB** a cada poucos segundos e restaurar ao reabrir **a mesma sala**. Fora do que foi pedido; só implementar se decidir que vale.

---

## 12. Checklist de testes

- [ ] Pegar uma arma, sair (fechar a aba) e voltar à mesma sala: mesma arma, **mesma munição**, mesmos attachments, mesma posição.
- [ ] Item pego não reaparece no chão; item largado continua lá depois de o chunk descarregar e recarregar.
- [ ] Sair e voltar rápido (queda de internet) retoma na hora, sem duplicar o boneco.
- [ ] Sair no meio de um combate: o boneco permanece pelo timer e pode ser morto.
- [ ] Morrer enquanto offline: tela de morte ao voltar, corpo com loot no local.
- [ ] Dois jogadores: um sai e volta, o outro o vê reaparecer sem bug.
- [ ] Tentativa de duplicar (sair com item na mão e voltar) **não** duplica.
- [ ] F5 no cliente retoma o mesmo personagem; token errado é recusado.
- [ ] Sair dentro de veículo coloca o jogador em ponto livre; veículo continua onde estava.
- [ ] `N` pede confirmação e invalida os saves.
- [ ] Host encerrando mostra "Servidor encerrado" aos clientes.

---

## 13. Decisões em aberto

1. **Timer de logout:** 30 s serve? → _______
2. **Fome/sede enquanto offline:** pausar (recomendado) ou continuar? → _______
3. **Boneco visível "dormindo" depois do timer?** → _______
4. **Expiração de saves** (sugestão 72 h) e **limite por sala** (sugestão 200)? → _______
5. **Gravar o estado do host em IndexedDB** (item 11)? → _______
