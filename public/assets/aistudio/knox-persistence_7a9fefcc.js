/*!
 * knox-persistence.js
 * CONDADO DE KNOX — Atualização 4: Persistência (progresso salvo enquanto a sala estiver aberta)
 *
 * Módulo único, sem dependências, funciona em navegador (script clássico ou import de efeito colateral)
 * e em Node (require). Expõe `KnoxPersistence` em globalThis e em module.exports.
 *
 * O QUE TEM AQUI
 *  - createClientIdentity ... playerId + token fixos no navegador (localStorage)
 *  - createClientSession .... handshake (hello), heartbeat e roteamento das mensagens no CLIENTE
 *  - HostPersistence ........ saves de jogadores, ciclo de vida (queda, timer de logout, volta, morte offline) no HOST
 *  - WorldDiffStore ......... mudanças do mundo por chunkId (loot, portas, containers, corpos, veículos...)
 *  - ItemLedger ............. onde cada item (uid) está; impede duplicação e item em dois lugares
 *  - sanitizeSave / migrateSave / checkIntegrity ... formato PLAYER_SAVE_V1 versionado e validado
 *  - splitMessage / Reassembler ... envio de saves grandes em partes
 *
 * REGRA DE OURO: o HOST é a fonte da verdade. O cliente só guarda { playerId, token }.
 *
 * Mensagens usam o campo `t` (ver MSG). Use isPersistenceMessage(msg) para rotear.
 */
(function (root, factory) {
  'use strict';
  var api = factory(root);
  if (typeof module === 'object' && module && module.exports) { module.exports = api; }
  if (root) { root.KnoxPersistence = api; }
})(typeof globalThis !== 'undefined' ? globalThis : (typeof self !== 'undefined' ? self : this), function (G) {
  'use strict';

  // ════════════════════════════════════════════════════════════════
  //  CONSTANTES
  // ════════════════════════════════════════════════════════════════
  const PROTOCOL_VERSION = 1;
  const SAVE_VERSION = 1;

  const MSG = Object.freeze({
    HELLO: 'hello',                     // cliente → host
    RESUME_OK: 'resume_ok',             // host → cliente  { instant, save, world }
    NEW_CHARACTER: 'new_character',     // host → cliente  { reason, diedWhileOffline?, deathInfo? }
    RESUME_DENIED: 'resume_denied',     // host → cliente  { reason }
    KICKED_DUPLICATE: 'kicked_duplicate', // host → cliente
    SERVER_CLOSED: 'server_closed',     // host → clientes
    PING: 'ping',                       // cliente → host
    PONG: 'pong',                       // host → cliente
    RESUME_READY: 'resume_ready',       // cliente → host (terminou o loading, pode soltar o jogador)
    PART: 'part'                        // pedaço de mensagem grande
  });
  const MSG_TYPES = new Set(Object.values(MSG));

  // Decisões da Atualização 4 (valores recomendados)
  const OFFLINE_RULES = {
    logoutTimerSec: 30,                      // boneco permanece no mundo após sair
    survivalDecayWhileOffline: 'paused',     // 'paused' | 'running'
    keepOfflineBodyVisible: false,           // RESERVADO: não implementado nesta atualização
    saveExpireHours: 72,                     // remove saves de quem nunca voltou
    maxSavesPerRoom: 200,
    heartbeatIntervalMs: 3000,
    heartbeatTimeoutMs: 10000,               // sem ouvir o cliente por este tempo = queda
    autosaveIntervalMs: 7000,                // salva jogadores "sujos" a cada ~7 s
    offlineDecayPerSec: { food: 0.01, water: 0.015 }, // só usado se survivalDecayWhileOffline === 'running'
    closeDelayMs: 1500                       // espera antes de fechar conexão recusada/derrubada
  };

  const LIMITS = {
    maxItems: 600,
    maxSaveChars: 400000,
    maxNick: 20,
    maxStats: 32,
    maxConditions: 16,
    maxSlots: 16,
    maxContains: 200,
    partChars: 12000,
    maxParts: 200,
    maxPending: 8
  };

  const ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
  const TOKEN_RE = /^[A-Za-z0-9_-]{16,128}$/;
  const BAD_KEYS = new Set(['__proto__', 'constructor', 'prototype']);

  // ════════════════════════════════════════════════════════════════
  //  UTILITÁRIOS
  // ════════════════════════════════════════════════════════════════
  function isObj(v) { return v !== null && typeof v === 'object' && !Array.isArray(v); }
  function isNum(v) { return typeof v === 'number' && isFinite(v); }
  function clamp(v, a, b) { return Math.min(b, Math.max(a, v)); }
  function clone(v) { return v === undefined ? undefined : JSON.parse(JSON.stringify(v)); }
  function isSafeKey(k) { return typeof k === 'string' && k.length > 0 && k.length <= 64 && !BAD_KEYS.has(k); }
  function isUid(k) { return isSafeKey(k) && /^[\w:.\-]+$/.test(k); }

  function randomBytes(n) {
    const arr = new Uint8Array(n);
    const c = G && G.crypto;
    if (c && typeof c.getRandomValues === 'function') c.getRandomValues(arr);
    else for (let i = 0; i < n; i++) arr[i] = Math.floor(Math.random() * 256);
    return arr;
  }
  function toHex(bytes) {
    let s = '';
    for (let i = 0; i < bytes.length; i++) s += (bytes[i] < 16 ? '0' : '') + bytes[i].toString(16);
    return s;
  }
  function randomHex(nBytes) { return toHex(randomBytes(nBytes)); }
  function uuid() {
    const b = randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    const h = toHex(b);
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }

  // SHA-256 em JS puro (fallback para contextos sem crypto.subtle, ex.: http fora de localhost)
  const SHA_K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]);
  function sha256Fallback(bytes) {
    const H = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
    const l = bytes.length;
    const total = ((l + 9 + 63) >> 6) << 6;
    const buf = new Uint8Array(total);
    buf.set(bytes);
    buf[l] = 0x80;
    const dv = new DataView(buf.buffer);
    dv.setUint32(total - 8, Math.floor(l / 0x20000000), false);
    dv.setUint32(total - 4, (l << 3) >>> 0, false);
    const w = new Uint32Array(64);
    for (let off = 0; off < total; off += 64) {
      for (let i = 0; i < 16; i++) w[i] = dv.getUint32(off + i * 4, false);
      for (let i = 16; i < 64; i++) {
        const w15 = w[i - 15], w2 = w[i - 2];
        const s0 = ((w15 >>> 7) | (w15 << 25)) ^ ((w15 >>> 18) | (w15 << 14)) ^ (w15 >>> 3);
        const s1 = ((w2 >>> 17) | (w2 << 15)) ^ ((w2 >>> 19) | (w2 << 13)) ^ (w2 >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
      }
      let a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
      for (let i = 0; i < 64; i++) {
        const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
        const ch = (e & f) ^ (~e & g);
        const t1 = (h + S1 + ch + SHA_K[i] + w[i]) >>> 0;
        const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const t2 = (S0 + maj) >>> 0;
        h = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
      }
      H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0; H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
      H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0; H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
    }
    let out = '';
    for (let i = 0; i < 8; i++) out += ('00000000' + H[i].toString(16)).slice(-8);
    return out;
  }
  async function sha256Hex(str) {
    const bytes = new TextEncoder().encode(String(str));
    const c = G && G.crypto;
    if (c && c.subtle && typeof c.subtle.digest === 'function') {
      try { return toHex(new Uint8Array(await c.subtle.digest('SHA-256', bytes))); } catch (e) { /* cai no fallback */ }
    }
    return sha256Fallback(bytes);
  }
  function safeEqual(a, b) {
    a = String(a); b = String(b);
    if (a.length !== b.length) return false;
    let r = 0;
    for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
    return r === 0;
  }
  function sanitizeNick(n) {
    let s = typeof n === 'string' ? n : '';
    s = s.replace(/[\u0000-\u001f\u007f<>]/g, '').trim().slice(0, LIMITS.maxNick);
    return s;
  }
  function makeSaveKey(roomId, worldSeed, playerId) { return String(roomId) + '|' + String(worldSeed) + '|' + String(playerId); }

  // ════════════════════════════════════════════════════════════════
  //  PROTOCOLO: mensagens e partes
  // ════════════════════════════════════════════════════════════════
  function isPersistenceMessage(m) { return !!m && typeof m === 'object' && MSG_TYPES.has(m.t); }

  /** Divide uma mensagem grande em partes {t:'part',id,i,n,d}. Mensagens pequenas passam inteiras: [msg]. */
  function splitMessage(msg, maxChars) {
    maxChars = maxChars || LIMITS.partChars;
    const json = JSON.stringify(msg);
    if (json.length <= maxChars) return [msg];
    const n = Math.ceil(json.length / maxChars);
    if (n > LIMITS.maxParts) throw new Error('mensagem grande demais (' + json.length + ' chars)');
    const id = randomHex(6);
    const parts = [];
    for (let i = 0; i < n; i++) parts.push({ t: MSG.PART, id: id, i: i, n: n, d: json.slice(i * maxChars, (i + 1) * maxChars) });
    return parts;
  }

  class Reassembler {
    constructor(opts) {
      opts = opts || {};
      this.ttlMs = opts.ttlMs || 30000;
      this._now = opts.now || Date.now;
      this._p = new Map();
    }
    /** Recebe uma parte. Retorna a mensagem completa quando a última chegar; senão null. */
    feed(part) {
      if (!part || part.t !== MSG.PART || typeof part.id !== 'string' || typeof part.d !== 'string') return null;
      if (!Number.isInteger(part.i) || !Number.isInteger(part.n)) return null;
      if (part.n < 1 || part.n > LIMITS.maxParts || part.i < 0 || part.i >= part.n) return null;
      const now = this._now();
      for (const [k, v] of Array.from(this._p.entries())) if (now - v.at > this.ttlMs) this._p.delete(k);
      let e = this._p.get(part.id);
      if (!e) {
        if (this._p.size >= LIMITS.maxPending) {
          const oldest = this._p.keys().next().value;
          this._p.delete(oldest);
        }
        e = { n: part.n, got: 0, parts: new Array(part.n), at: now };
        this._p.set(part.id, e);
      }
      if (e.n !== part.n) return null;
      if (e.parts[part.i] === undefined) { e.parts[part.i] = part.d; e.got++; }
      if (e.got < e.n) return null;
      this._p.delete(part.id);
      try { const m = JSON.parse(e.parts.join('')); return (m && m.t === MSG.PART) ? null : m; } catch (err) { return null; }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  FORMATO DO SAVE (PLAYER_SAVE_V1) — validação, migração, integridade
  // ════════════════════════════════════════════════════════════════
  const MIGRATIONS = {
    // Quando existir a v2: 1: function (s) { /* ...transformar... */ s.v = 2; return s; }
  };
  function migrateSave(save) {
    if (!isObj(save) || !Number.isInteger(save.v)) return null;
    let s = save;
    while (s.v < SAVE_VERSION) {
      const m = MIGRATIONS[s.v];
      if (typeof m !== 'function') return null;
      s = m(s);
      if (!isObj(s)) return null;
    }
    return s.v === SAVE_VERSION ? s : null;
  }

  function createEmptySave(o) {
    o = o || {};
    return {
      v: SAVE_VERSION,
      playerId: String(o.playerId || ''),
      worldSeed: String(o.worldSeed !== undefined ? o.worldSeed : '0'),
      nick: sanitizeNick(o.nick),
      color: typeof o.color === 'string' ? o.color : '#cccccc',
      alive: true,
      pos: o.pos || null,
      yaw: 0,
      stance: 'stand',
      stats: o.stats || { hp: 100, food: 80, water: 70, stamina: 100, temp: 36.6 },
      conditions: [],
      equipment: {},
      items: {},
      squad: [],
      spawnRegion: o.spawnRegion || '',
      appearance: o.appearance || { characterId: '' },
      lastSeen: 0
    };
  }

  /**
   * Valida, limpa e repara um save. Retorna { save, issues }. save === null se irrecuperável.
   * Nunca lança exceção. Garante: nenhum uid em dois lugares, referências existentes, sem ciclos.
   */
  function sanitizeSave(input, ctx) {
    ctx = ctx || {};
    const issues = [];
    if (!isObj(input)) return { save: null, issues: ['not_object'] };
    let raw;
    try { raw = JSON.parse(JSON.stringify(input)); } catch (e) { return { save: null, issues: ['not_serializable'] }; }
    if (JSON.stringify(raw).length > LIMITS.maxSaveChars) return { save: null, issues: ['too_big'] };
    const s = migrateSave(raw);
    if (!s) return { save: null, issues: ['bad_version'] };

    const out = {
      v: SAVE_VERSION,
      playerId: String(ctx.playerId || s.playerId || '').slice(0, 64),
      worldSeed: String(ctx.worldSeed !== undefined ? ctx.worldSeed : (s.worldSeed !== undefined ? s.worldSeed : '0')),
      nick: sanitizeNick(s.nick),
      color: (typeof s.color === 'string' && /^#[0-9a-fA-F]{3,8}$/.test(s.color)) ? s.color : '#cccccc',
      alive: s.alive !== false,
      pos: null,
      yaw: isNum(s.yaw) ? s.yaw : 0,
      stance: (typeof s.stance === 'string' && /^[a-z_]{1,16}$/.test(s.stance)) ? s.stance : 'stand',
      stats: {},
      conditions: [],
      equipment: {},
      items: {},
      squad: [],
      spawnRegion: typeof s.spawnRegion === 'string' ? s.spawnRegion.slice(0, 64) : '',
      appearance: { characterId: '' },
      lastSeen: isNum(s.lastSeen) ? s.lastSeen : 0
    };
    // aparência (personagem escolhido na tela de spawn): só o id; o jogo resolve o modelo pelo manifesto
    if (isObj(s.appearance) && typeof s.appearance.characterId === 'string' && /^[\w.\-]{0,48}$/.test(s.appearance.characterId)) {
      out.appearance.characterId = s.appearance.characterId;
      if (typeof s.appearance.variant === 'string' && /^[\w.\-]{1,24}$/.test(s.appearance.variant)) out.appearance.variant = s.appearance.variant;
    }
    if (!out.playerId) return { save: null, issues: ['no_player_id'] };

    // posição
    if (isObj(s.pos) && isNum(s.pos.x) && isNum(s.pos.y) && isNum(s.pos.z)
        && Math.abs(s.pos.x) < 1e7 && Math.abs(s.pos.y) < 1e7 && Math.abs(s.pos.z) < 1e7) {
      out.pos = { x: s.pos.x, y: s.pos.y, z: s.pos.z };
    } else issues.push('bad_pos');

    // status
    if (isObj(s.stats)) {
      let n = 0;
      for (const k of Object.keys(s.stats)) {
        if (!isSafeKey(k) || k.length > 24) continue;
        if (n >= LIMITS.maxStats) { issues.push('too_many_stats'); break; }
        if (isNum(s.stats[k])) { out.stats[k] = clamp(s.stats[k], -1e6, 1e6); n++; }
      }
      if (isNum(out.stats.hp) && out.stats.hp < 0) out.stats.hp = 0;
    }
    if (Array.isArray(s.conditions)) {
      for (const c of s.conditions) {
        if (out.conditions.length >= LIMITS.maxConditions) break;
        if (typeof c === 'string' && c.length > 0 && c.length <= 24) out.conditions.push(c);
      }
    }
    if (Array.isArray(s.squad)) {
      for (const p of s.squad) {
        if (out.squad.length >= 32) break;
        if (typeof p === 'string' && ID_RE.test(p)) out.squad.push(p);
      }
    }

    // itens
    if (isObj(s.items)) {
      let n = 0;
      for (const uid of Object.keys(s.items)) {
        if (!isUid(uid)) { issues.push('bad_uid'); continue; }
        if (n >= LIMITS.maxItems) { issues.push('too_many_items'); break; }
        const it = s.items[uid];
        if (!isObj(it) || typeof it.type !== 'string' || it.type.length === 0 || it.type.length > 48) { issues.push('bad_item:' + uid); continue; }
        const o = {};
        for (const k of Object.keys(it)) if (isSafeKey(k)) o[k] = it[k];
        if ('ammoInMag' in o) { if (isNum(o.ammoInMag) && o.ammoInMag >= 0) o.ammoInMag = Math.floor(o.ammoInMag); else delete o.ammoInMag; }
        if ('durability' in o) { if (isNum(o.durability)) o.durability = clamp(o.durability, 0, 1e6); else delete o.durability; }
        if ('attachments' in o) {
          if (isObj(o.attachments)) {
            const a = {};
            for (const k of Object.keys(o.attachments)) if (isSafeKey(k) && typeof o.attachments[k] === 'string' && o.attachments[k].length <= 48) a[k] = o.attachments[k];
            o.attachments = a;
          } else delete o.attachments;
        }
        if ('contains' in o) {
          o.contains = Array.isArray(o.contains) ? o.contains.filter(isUid).slice(0, LIMITS.maxContains) : [];
        }
        out.items[uid] = o;
        n++;
      }
    }
    if (isObj(s.equipment)) {
      let n = 0;
      for (const slot of Object.keys(s.equipment)) {
        if (!isSafeKey(slot) || slot.length > 24) continue;
        if (n >= LIMITS.maxSlots) { issues.push('too_many_slots'); break; }
        if (isUid(s.equipment[slot])) { out.equipment[slot] = s.equipment[slot]; n++; }
      }
    }
    repairIntegrity(out, issues);
    return { save: out, issues: issues };
  }

  /** Remove referências quebradas, uid em dois lugares e ciclos. Altera `save` e acrescenta em `issues`. */
  function repairIntegrity(save, issues) {
    issues = issues || [];
    const items = save.items;
    const parent = new Map(); // uid → { kind:'slot'|'item', ref }
    for (const slot of Object.keys(save.equipment)) {
      const uid = save.equipment[slot];
      if (!items[uid]) { delete save.equipment[slot]; issues.push('dangling_equipment:' + slot); continue; }
      if (parent.has(uid)) { delete save.equipment[slot]; issues.push('duplicate_equipment:' + uid); continue; }
      parent.set(uid, { kind: 'slot', ref: slot });
    }
    for (const uid of Object.keys(items)) {
      const it = items[uid];
      if (!Array.isArray(it.contains)) continue;
      it.contains = it.contains.filter(function (cu) {
        if (cu === uid) { issues.push('self_contain:' + uid); return false; }
        if (!items[cu]) { issues.push('dangling_contains:' + cu); return false; }
        if (parent.has(cu)) { issues.push('duplicate_item:' + cu); return false; }
        parent.set(cu, { kind: 'item', ref: uid });
        return true;
      });
    }
    // ciclos: A contém B e B contém A (nenhum chega a um slot)
    for (const start of Object.keys(items)) {
      const seen = new Set();
      let cur = start;
      while (parent.has(cur) && parent.get(cur).kind === 'item') {
        if (seen.has(cur)) {
          const p = parent.get(cur).ref;
          items[p].contains = items[p].contains.filter(function (x) { return x !== cur; });
          parent.delete(cur);
          issues.push('cycle:' + cur);
          break;
        }
        seen.add(cur);
        cur = parent.get(cur).ref;
      }
    }
    for (const uid of Object.keys(items)) if (!parent.has(uid)) issues.push('orphan:' + uid);
    return issues;
  }

  /** Desconta fome/sede pelo tempo offline (só usado se survivalDecayWhileOffline === 'running'). Não mata. */
  function applyOfflineDecay(save, elapsedSec, rules) {
    rules = rules || OFFLINE_RULES;
    const rates = rules.offlineDecayPerSec || {};
    if (!save || !save.stats || !(elapsedSec > 0)) return save;
    for (const k of Object.keys(rates)) {
      if (isNum(save.stats[k]) && isNum(rates[k])) save.stats[k] = Math.max(0, save.stats[k] - rates[k] * elapsedSec);
    }
    return save;
  }

  // ════════════════════════════════════════════════════════════════
  //  IDENTIDADE DO CLIENTE
  // ════════════════════════════════════════════════════════════════
  function getLocalStorage() {
    try {
      const s = G && G.localStorage;
      if (!s) return null;
      s.setItem('__knox_t__', '1'); s.removeItem('__knox_t__');
      return s;
    } catch (e) { return null; }
  }

  /**
   * Cria/carrega a identidade fixa do navegador.
   * opts.profile → sufixo para testar 2 jogadores no mesmo navegador (ex.: ?profile=2).
   * opts.storage → objeto com getItem/setItem (padrão: localStorage). Sem storage, a identidade fica só na memória.
   */
  function createClientIdentity(opts) {
    opts = opts || {};
    const storage = opts.storage !== undefined ? opts.storage : getLocalStorage();
    const key = 'knox.identity.v1' + (opts.profile ? '.' + String(opts.profile).replace(/[^\w-]/g, '').slice(0, 16) : '');
    let ident = null;
    let persisted = false;
    try {
      const raw = storage && storage.getItem(key);
      if (raw) {
        const p = JSON.parse(raw);
        if (isObj(p) && ID_RE.test(String(p.playerId)) && TOKEN_RE.test(String(p.playerToken))) { ident = p; persisted = true; }
      }
    } catch (e) { /* identidade nova */ }
    if (!ident) {
      ident = { playerId: uuid(), playerToken: randomHex(32), createdAt: Date.now() };
      try { if (storage) { storage.setItem(key, JSON.stringify(ident)); persisted = true; } } catch (e) { persisted = false; }
    }
    return {
      get playerId() { return ident.playerId; },
      get token() { return ident.playerToken; },
      get persisted() { return persisted; },
      key: key,
      buildHello: function (o) {
        o = o || {};
        return { t: MSG.HELLO, playerId: ident.playerId, token: ident.playerToken, nick: sanitizeNick(o.nick), version: o.version !== undefined ? o.version : PROTOCOL_VERSION };
      }
    };
  }

  // ════════════════════════════════════════════════════════════════
  //  SESSÃO DO CLIENTE (handshake + heartbeat + roteamento)
  // ════════════════════════════════════════════════════════════════
  /**
   * opts: { identity, send(msg), nick (string|função), version?, handlers, rules?, now?, autoHeartbeat? }
   * handlers: onResumeOk(m), onNewCharacter(m), onDenied(m), onKicked(m), onServerClosed(m), onTimeout()
   * Uso: conn.on('open', session.start); conn.on('data', m => { if (session.receive(m)) return; ... });
   */
  function createClientSession(opts) {
    const identity = opts.identity;
    const send = opts.send;
    const handlers = opts.handlers || {};
    const rules = Object.assign({}, OFFLINE_RULES, opts.rules || {});
    const now = opts.now || Date.now;
    const reasm = new Reassembler({ now: now });
    const state = { phase: 'idle' }; // idle | hello | loading | playing | closed
    let timer = null;
    let lastPong = null;

    function emit(name, arg) {
      const f = handlers[name];
      if (typeof f !== 'function') return;
      try { f(arg); } catch (e) { if (G && G.console) G.console.error('[knox-persistence] handler ' + name + ':', e); }
    }
    function beat() {
      if (state.phase === 'closed') return;
      if (lastPong !== null && now() - lastPong > rules.heartbeatTimeoutMs) { stopTimer(); emit('onTimeout'); return; }
      send({ t: MSG.PING, c: now() });
    }
    function stopTimer() { if (timer) { clearInterval(timer); timer = null; } }
    function start() {
      state.phase = 'hello';
      lastPong = now();
      const nick = typeof opts.nick === 'function' ? opts.nick() : opts.nick;
      send(identity.buildHello({ nick: nick, version: opts.version }));
      if (opts.autoHeartbeat !== false && !timer) timer = setInterval(beat, rules.heartbeatIntervalMs);
    }
    function dispatch(m) {
      switch (m.t) {
        case MSG.PONG: lastPong = now(); break;
        case MSG.RESUME_OK: state.phase = m.instant ? 'playing' : 'loading'; emit('onResumeOk', m); break;
        case MSG.NEW_CHARACTER: state.phase = 'playing'; emit('onNewCharacter', m); break;
        case MSG.RESUME_DENIED: state.phase = 'closed'; stopTimer(); emit('onDenied', m); break;
        case MSG.KICKED_DUPLICATE: state.phase = 'closed'; stopTimer(); emit('onKicked', m); break;
        case MSG.SERVER_CLOSED: state.phase = 'closed'; stopTimer(); emit('onServerClosed', m); break;
        default: break;
      }
    }
    function receive(m) {
      if (!isPersistenceMessage(m)) return false;
      lastPong = now(); // qualquer mensagem do host prova que ele está vivo
      if (m.t === MSG.PART) { const full = reasm.feed(m); if (full) dispatch(full); return true; }
      dispatch(m);
      return true;
    }
    function sendReady() { state.phase = 'playing'; send({ t: MSG.RESUME_READY }); }
    function stop() { state.phase = 'closed'; stopTimer(); }
    return { start: start, receive: receive, sendReady: sendReady, stop: stop, state: state, _beat: beat };
  }

  // ════════════════════════════════════════════════════════════════
  //  LEDGER DE ITENS (anti-duplicação)
  // ════════════════════════════════════════════════════════════════
  const LOC = {
    world: function (chunkId) { return 'w:' + chunkId; },
    player: function (playerId) { return 'p:' + playerId; },
    container: function (id) { return 'c:' + id; },
    vehicle: function (id) { return 'v:' + id; },
    corpse: function (id) { return 'b:' + id; }
  };

  /**
   * Registra EM QUE DONO cada uid está (mundo/jogador/container/veículo/corpo). Cada uid só existe em um dono.
   * Mover entre donos é uma operação única: move(uid, from, to) → { ok, reason? }.
   * Mover dentro do mesmo dono (equipar, mochila) não precisa passar aqui.
   * uid desconhecido é aceito se `from` for mundo ('w:') ou jogador ('p:') — loot gerado pelo mapa nasce implícito no mundo.
   */
  class ItemLedger {
    constructor() { this._loc = new Map(); this._by = new Map(); }
    _add(uid, loc) { this._loc.set(uid, loc); let s = this._by.get(loc); if (!s) { s = new Set(); this._by.set(loc, s); } s.add(uid); }
    _del(uid) {
      const loc = this._loc.get(uid);
      if (loc === undefined) return;
      this._loc.delete(uid);
      const s = this._by.get(loc);
      if (s) { s.delete(uid); if (s.size === 0) this._by.delete(loc); }
    }
    has(uid) { return this._loc.has(String(uid)); }
    locationOf(uid) { return this._loc.get(String(uid)); }
    itemsAt(loc) { const s = this._by.get(loc); return s ? Array.from(s) : []; }
    size() { return this._loc.size; }
    register(uid, loc) { uid = String(uid); if (this._loc.has(uid)) return false; this._add(uid, loc); return true; }
    move(uid, from, to) {
      uid = String(uid);
      if (typeof to !== 'string' || to.length < 3) return { ok: false, reason: 'bad_destination' };
      const cur = this._loc.get(uid);
      if (cur === undefined) {
        if (typeof from === 'string' && (from.indexOf('w:') === 0 || from.indexOf('p:') === 0)) { this._add(uid, to); return { ok: true }; }
        return { ok: false, reason: 'unknown' };
      }
      const bothWorld = cur.indexOf('w:') === 0 && typeof from === 'string' && from.indexOf('w:') === 0;
      if (cur !== from && !bothWorld) return { ok: false, reason: 'wrong_source', at: cur };
      this._del(uid);
      this._add(uid, to);
      return { ok: true };
    }
    remove(uid) { this._del(String(uid)); }
    removeAllAt(loc) { for (const uid of this.itemsAt(loc)) this._del(uid); }
    clear() { this._loc.clear(); this._by.clear(); }
    /**
     * Antes de devolver um save ao jogador: item que o ledger diz estar em OUTRO lugar é duplicata → sai do save.
     * Item desconhecido é registrado como do jogador. Retorna { removed: [uids] }.
     */
    reconcilePlayerSave(save, playerId) {
      const mine = LOC.player(playerId);
      const removed = [];
      for (const uid of Object.keys(save.items)) {
        const cur = this._loc.get(uid);
        if (cur === undefined) this._add(uid, mine);
        else if (cur !== mine) removed.push(uid);
      }
      if (removed.length) {
        for (const uid of removed) delete save.items[uid];
        for (const slot of Object.keys(save.equipment)) if (removed.indexOf(save.equipment[slot]) >= 0) delete save.equipment[slot];
        for (const uid of Object.keys(save.items)) {
          const it = save.items[uid];
          if (Array.isArray(it.contains)) it.contains = it.contains.filter(function (x) { return removed.indexOf(x) < 0; });
        }
      }
      return { removed: removed };
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  MUNDO: diffs por chunkId (fora do chunk carregado!)
  // ════════════════════════════════════════════════════════════════
  const m2a = function (m) { return Array.from(m.entries()); };
  const a2m = function (a) { return new Map(Array.isArray(a) ? a : []); };

  /**
   * Guarda o que mudou no mundo, por chunkId, separado do chunk carregado.
   * Descarregar/recarregar um chunk NÃO perde nada: ao gerar o chunk, passe o loot gerado por applyLoot().
   * REQUISITO: o loot gerado pelo mapa precisa de uid estável e determinístico (ex.: `${seed}:${chunkId}:${i}`).
   */
  class WorldDiffStore {
    constructor(opts) {
      opts = opts || {};
      this.worldSeed = opts.worldSeed !== undefined ? String(opts.worldSeed) : '0';
      this._reset();
    }
    _reset() { this.chunks = new Map(); this.vehicles = new Map(); this.timers = new Map(); this.misc = new Map(); this.rev = 0; }
    reset(newSeed) { if (newSeed !== undefined) this.worldSeed = String(newSeed); this._reset(); }
    _chunk(id) {
      id = String(id);
      let c = this.chunks.get(id);
      if (!c) {
        c = { removed: new Map(), added: new Map(), doors: new Map(), containers: new Map(), placed: new Map(), bodies: new Map() };
        this.chunks.set(id, c);
      }
      return c;
    }
    _peek(id) { return this.chunks.get(String(id)) || null; }
    _touch() { this.rev++; }

    // — loot —
    /** Item do chão foi pego. opts.respawnAt (ms) faz o loot GERADO voltar depois dessa hora. */
    itemTaken(chunkId, uid, opts) {
      const c = this._chunk(chunkId); uid = String(uid);
      if (c.added.has(uid)) c.added.delete(uid);              // era um item largado por jogador
      else c.removed.set(uid, { respawnAt: (opts && opts.respawnAt) || 0 }); // era loot gerado pelo mapa
      this._touch();
    }
    /** Item foi largado/colocado no chão. item = { uid, type, x, y, z, ...estado (munição, durabilidade, attachments) } */
    itemDropped(chunkId, item) {
      if (!isObj(item) || item.uid === undefined || item.uid === null) throw new Error('itemDropped: item sem uid');
      this._chunk(chunkId).added.set(String(item.uid), clone(item));
      this._touch();
    }
    /** Atualiza um item largado (ex.: posição final depois da física). */
    updateDropped(chunkId, uid, patch) {
      const c = this._peek(chunkId);
      const it = c && c.added.get(String(uid));
      if (!it) return false;
      Object.assign(it, clone(patch)); this._touch(); return true;
    }
    /** Chame ao GERAR um chunk: devolve o loot gerado já filtrado + os itens largados por jogadores. */
    applyLoot(chunkId, generated, now) {
      const c = this._peek(chunkId);
      if (!c) return generated.slice();
      now = now === undefined ? Date.now() : now;
      const out = [];
      for (const it of generated) {
        const uid = String(it.uid);
        const r = c.removed.get(uid);
        if (r) {
          if (r.respawnAt && r.respawnAt <= now) { c.removed.delete(uid); this._touch(); if (c.added.has(uid)) continue; }
          else continue;
        }
        out.push(it);
      }
      for (const it of c.added.values()) out.push(clone(it));
      return out;
    }
    isLootTaken(chunkId, uid) { const c = this._peek(chunkId); return !!(c && c.removed.has(String(uid))); }

    // — portas, containers, objetos colocados, corpos —
    setDoor(chunkId, doorId, open) { this._chunk(chunkId).doors.set(String(doorId), !!open); this._touch(); }
    getDoor(chunkId, doorId) { const c = this._peek(chunkId); return c ? c.doors.get(String(doorId)) : undefined; }
    setContainer(chunkId, containerId, state) { this._chunk(chunkId).containers.set(String(containerId), clone(state)); this._touch(); }
    getContainer(chunkId, containerId) { const c = this._peek(chunkId); const v = c && c.containers.get(String(containerId)); return v === undefined ? undefined : clone(v); }
    placeObject(chunkId, id, obj) { this._chunk(chunkId).placed.set(String(id), clone(obj)); this._touch(); }
    removeObject(chunkId, id) { const c = this._peek(chunkId); if (c && c.placed.delete(String(id))) this._touch(); }
    getPlaced(chunkId) { const c = this._peek(chunkId); return c ? Array.from(c.placed.entries()).map(function (e) { return Object.assign({ id: e[0] }, clone(e[1])); }) : []; }
    addBody(chunkId, body) {
      if (!isObj(body) || body.id === undefined) throw new Error('addBody: corpo sem id');
      this._chunk(chunkId).bodies.set(String(body.id), clone(body)); this._touch();
    }
    removeBody(chunkId, id) { const c = this._peek(chunkId); if (c && c.bodies.delete(String(id))) this._touch(); }
    getBodies(chunkId) { const c = this._peek(chunkId); return c ? Array.from(c.bodies.values()).map(clone) : []; }

    // — veículos (globais, não presos a chunk) —
    saveVehicle(id, state) { this.vehicles.set(String(id), clone(state)); this._touch(); }
    getVehicle(id) { const v = this.vehicles.get(String(id)); return v === undefined ? undefined : clone(v); }
    removeVehicle(id) { if (this.vehicles.delete(String(id))) this._touch(); }
    allVehicles() { return Array.from(this.vehicles.entries()).map(function (e) { return Object.assign({ id: e[0] }, clone(e[1])); }); }

    // — timers (respawn de zumbis/loot, despawn de corpos) e extras (relógio, clima) —
    setTimer(key, atMs, payload) { this.timers.set(String(key), { at: atMs, payload: clone(payload) }); this._touch(); }
    clearTimer(key) { if (this.timers.delete(String(key))) this._touch(); }
    takeDueTimers(now) {
      now = now === undefined ? Date.now() : now;
      const due = [];
      for (const [k, v] of Array.from(this.timers.entries())) {
        if (v.at <= now) { due.push({ key: k, at: v.at, payload: v.payload }); this.timers.delete(k); }
      }
      if (due.length) this._touch();
      return due;
    }
    setMisc(key, value) { this.misc.set(String(key), clone(value)); this._touch(); }
    getMisc(key) { const v = this.misc.get(String(key)); return v === undefined ? undefined : clone(v); }

    // — snapshots —
    getChunkDiff(chunkId) {
      const c = this._peek(chunkId);
      if (!c) return null;
      return {
        removed: m2a(c.removed), added: m2a(c.added), doors: m2a(c.doors),
        containers: m2a(c.containers), placed: m2a(c.placed), bodies: m2a(c.bodies)
      };
    }
    /** Diffs de uma lista de chunks (ou de todos, se chunkIds for null) + veículos + extras. JSON-safe. */
    snapshotNear(chunkIds) {
      const ids = chunkIds ? chunkIds.map(String) : Array.from(this.chunks.keys());
      const chunks = {};
      for (const id of ids) { const d = this.getChunkDiff(id); if (d) chunks[id] = d; }
      const misc = {};
      for (const [k, v] of this.misc.entries()) misc[k] = clone(v);
      return { rev: this.rev, worldSeed: this.worldSeed, chunks: chunks, vehicles: m2a(this.vehicles), misc: misc };
    }
    pruneEmpty() {
      for (const [id, c] of Array.from(this.chunks.entries())) {
        if (!c.removed.size && !c.added.size && !c.doors.size && !c.containers.size && !c.placed.size && !c.bodies.size) this.chunks.delete(id);
      }
    }
    exportState() {
      const chunks = [];
      for (const [id] of this.chunks.entries()) chunks.push([id, this.getChunkDiff(id)]);
      return { v: 1, worldSeed: this.worldSeed, rev: this.rev, chunks: chunks, vehicles: m2a(this.vehicles), timers: m2a(this.timers), misc: m2a(this.misc) };
    }
    importState(st) {
      if (!isObj(st) || st.v !== 1) return false;
      this._reset();
      this.worldSeed = String(st.worldSeed);
      this.rev = isNum(st.rev) ? st.rev : 0;
      for (const [id, d] of (Array.isArray(st.chunks) ? st.chunks : [])) {
        const c = this._chunk(id);
        c.removed = a2m(d.removed); c.added = a2m(d.added); c.doors = a2m(d.doors);
        c.containers = a2m(d.containers); c.placed = a2m(d.placed); c.bodies = a2m(d.bodies);
      }
      this.vehicles = a2m(st.vehicles); this.timers = a2m(st.timers); this.misc = a2m(st.misc);
      return true;
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  HOST: saves de jogadores e ciclo de vida
  // ════════════════════════════════════════════════════════════════
  /**
   * Estados do registro de um jogador:
   *   joining   → conectou, ainda no loading/tela de spawn (corpo NÃO está no mundo)
   *   online    → jogando
   *   lingering → conexão caiu; corpo continua no mundo até o timer de logout (anti combat-log)
   *   offline   → corpo removido; save guardado
   *
   * hooks (todos opcionais, mas o jogo deve implementar os principais):
   *   send(connId, msg)                    envia (o módulo já divide mensagens grandes em partes)
   *   close(connId)                        fecha a conexão
   *   snapshotPlayer(playerId) → save      monta o save v1 do estado AUTORITATIVO do host
   *   chunksNear(pos) → [chunkId]          chunks ao redor de pos (para o snapshot do mundo)
   *   validatePosition(pos|null) → pos     ponto válido mais próximo (mesma função do spawn)
   *   exitVehicle(playerId) → pos|null     tira do veículo, se estiver dentro; devolve ponto livre ao lado
   *   removeBody(playerId, save)           remove o boneco do mundo e avisa os outros jogadores
   *   spawnBody(playerId, save)            cria o boneco no mundo a partir do save e avisa os outros
   *   reattachBody(playerId, connId)       religa o boneco que já está no mundo à nova conexão
   *   onLinger(playerId)                   (opcional) boneco entrou no timer de logout
   *   onDuplicateRemoved(playerId, uids)   (opcional) itens duplicados removidos de um save
   *   log(level, ...args)                  (opcional)
   */
  class HostPersistence {
    constructor(opts) {
      opts = opts || {};
      this.roomId = String(opts.roomId !== undefined ? opts.roomId : 'room');
      this.worldSeed = String(opts.worldSeed !== undefined ? opts.worldSeed : '0');
      this.rules = Object.assign({}, OFFLINE_RULES, opts.rules || {});
      this.hooks = opts.hooks || {};
      this.world = opts.world || new WorldDiffStore({ worldSeed: this.worldSeed });
      this.ledger = opts.ledger || new ItemLedger();
      this.localConnId = opts.localConnId || 'local';
      this.version = opts.version !== undefined ? opts.version : PROTOCOL_VERSION;
      this._now = opts.now || Date.now;
      this.players = new Map(); // playerId → registro
      this.conns = new Map();   // connId → { playerId, lastHeard }
      this.closed = false;
      this._timer = null;
      this._lastAutosave = 0;
      this._lastPrune = this._now();
    }

    // — ciclo do módulo —
    start(intervalMs) { if (!this._timer) this._timer = setInterval(() => this.tick(), intervalMs || 1000); }
    stop() { if (this._timer) { clearInterval(this._timer); this._timer = null; } }

    _log(level) {
      const f = this.hooks.log;
      const args = Array.prototype.slice.call(arguments, 1);
      if (typeof f === 'function') { try { f.apply(null, [level].concat(args)); } catch (e) { /* ignora */ } }
      else if (level !== 'debug' && G && G.console && G.console[level]) G.console[level].apply(G.console, ['[knox-persistence]'].concat(args));
    }
    _send(connId, msg) {
      if (typeof this.hooks.send !== 'function') return;
      let parts;
      try { parts = splitMessage(msg, this.rules.partChars || LIMITS.partChars); }
      catch (e) { this._log('error', 'mensagem não enviada:', e.message); return; }
      for (const p of parts) { try { this.hooks.send(connId, p); } catch (e) { this._log('warn', 'falha ao enviar', e && e.message); } }
    }
    _closeLater(connId) {
      if (typeof this.hooks.close !== 'function' || connId === this.localConnId) return;
      const doClose = () => { try { this.hooks.close(connId); } catch (e) { /* ignora */ } };
      if (this.rules.closeDelayMs > 0) setTimeout(doClose, this.rules.closeDelayMs); else doClose();
    }
    _deny(connId, reason) {
      this._send(connId, { t: MSG.RESUME_DENIED, reason: reason });
      this._closeLater(connId);
      return { ok: false, action: 'denied', reason: reason };
    }
    _kick(connId) {
      this.conns.delete(connId);
      this._send(connId, { t: MSG.KICKED_DUPLICATE });
      this._closeLater(connId);
    }
    _attach(rec, connId, now) {
      rec.connId = connId;
      rec.lastHeard = now;
      this.conns.set(connId, { playerId: rec.playerId, lastHeard: now });
    }
    _newRecord(playerId, tokenHash, nick, now) {
      this._makeRoom();
      const rec = {
        playerId: playerId, tokenHash: tokenHash, nick: nick || 'Sobrevivente', save: null, status: 'joining',
        connId: null, lastHeard: now, logoutDeadline: 0, lastSeen: now, offlineSince: 0, createdAt: now,
        dirty: false, dead: false, diedWhileOffline: false, deathInfo: null
      };
      this.players.set(playerId, rec);
      return rec;
    }
    _worldMsg(pos) {
      let ids = null;
      if (typeof this.hooks.chunksNear === 'function' && pos) { try { ids = this.hooks.chunksNear(pos); } catch (e) { ids = null; } }
      return this.world.snapshotNear(Array.isArray(ids) ? ids : null);
    }
    _newCharacter(rec, connId, reason, extra) {
      rec.save = null; rec.dead = false; rec.diedWhileOffline = false; rec.deathInfo = null;
      rec.status = 'joining'; rec.logoutDeadline = 0; rec.dirty = false;
      this._send(connId, Object.assign({ t: MSG.NEW_CHARACTER, reason: reason, worldSeed: this.worldSeed, roomId: this.roomId }, extra || {}));
    }

    /**
     * Chame para QUALQUER mensagem recebida de um cliente, antes do resto do jogo.
     * Retorna true se a mensagem era de persistência (já tratada) — nesse caso o jogo não deve processá-la.
     */
    handleMessage(connId, msg) {
      this.touch(connId);
      if (!isPersistenceMessage(msg)) return false;
      switch (msg.t) {
        case MSG.HELLO: this.handleHello(connId, msg).catch((e) => this._log('error', 'hello falhou:', e && e.message)); break;
        case MSG.PING: this._send(connId, { t: MSG.PONG, c: msg.c, s: this._now() }); break;
        case MSG.RESUME_READY: { const c = this.conns.get(connId); if (c) this.markReady(c.playerId); break; }
        default: break;
      }
      return true;
    }
    touch(connId) { const c = this.conns.get(connId); if (c) { c.lastHeard = this._now(); } }
    /** Retorna o playerId (fixo) da conexão, ou null se ela ainda não fez o handshake. */
    playerIdOf(connId) { const c = this.conns.get(connId); return c ? c.playerId : null; }
    connIdOf(playerId) { const r = this.players.get(playerId); return r ? r.connId : null; }
    statusOf(playerId) { const r = this.players.get(playerId); return r ? r.status : null; }
    getSave(playerId) { const r = this.players.get(playerId); return r && r.save ? clone(r.save) : null; }

    /** Handshake. Envia a resposta ao cliente sozinho. Retorna { ok, action, instant?, ... }. */
    async handleHello(connId, msg) {
      if (this.closed) return { ok: false, action: 'closed' };
      if (!isObj(msg) || msg.t !== MSG.HELLO) return this._deny(connId, 'bad_request');
      const playerId = msg.playerId, token = msg.token;
      if (!ID_RE.test(String(playerId || '')) || !TOKEN_RE.test(String(token || ''))) return this._deny(connId, 'bad_request');
      if (String(msg.version) !== String(this.version)) return this._deny(connId, 'version');
      const tokenHash = await sha256Hex(token);
      if (this.closed) return { ok: false, action: 'closed' };
      const now = this._now();
      const nick = sanitizeNick(msg.nick);
      let rec = this.players.get(playerId);

      // 1) jogador novo
      if (!rec) {
        rec = this._newRecord(playerId, tokenHash, nick, now);
        this._attach(rec, connId, now);
        this._newCharacter(rec, connId, 'first_time');
        return { ok: true, action: 'new_character', playerId: playerId };
      }
      // 2) token errado → não deixa assumir o personagem de outro
      if (!safeEqual(rec.tokenHash, tokenHash)) return this._deny(connId, 'bad_token');

      // 3) conexão duplicada (F5, duas abas): a nova assume, a antiga cai
      if (rec.connId && rec.connId !== connId) this._kick(rec.connId);
      if (nick) rec.nick = nick;
      const prev = rec.status;
      this._attach(rec, connId, now);

      // 4) morreu enquanto estava fora
      if (rec.diedWhileOffline) {
        const info = rec.deathInfo || null;
        this._newCharacter(rec, connId, 'died_offline', { diedWhileOffline: true, deathInfo: info });
        return { ok: true, action: 'new_character', playerId: playerId, diedWhileOffline: true };
      }
      // 5) morreu online e recarregou na tela de morte
      if (rec.dead) {
        this._newCharacter(rec, connId, 'dead');
        return { ok: true, action: 'new_character', playerId: playerId };
      }
      // 6) corpo ainda está no mundo (queda curta / F5 dentro do timer) → retoma na hora
      if (prev === 'online' || prev === 'lingering') {
        const save = this._snapshot(rec) || rec.save;
        if (save && save.alive) {
          rec.status = 'online'; rec.logoutDeadline = 0; rec.dirty = true;
          if (typeof this.hooks.reattachBody === 'function') {
            try { this.hooks.reattachBody(playerId, connId); } catch (e) { this._log('error', 'reattachBody falhou:', e && e.message); }
          }
          this._send(connId, { t: MSG.RESUME_OK, instant: true, save: clone(save), world: this._worldMsg(save.pos), worldSeed: this.worldSeed, roomId: this.roomId, serverTime: now });
          return { ok: true, action: 'resume', instant: true, playerId: playerId };
        }
        this._newCharacter(rec, connId, 'no_save');
        return { ok: true, action: 'new_character', playerId: playerId };
      }
      // 7) offline (ou joining) com save → retomar com loading
      if (!rec.save || !rec.save.alive || String(rec.save.worldSeed) !== this.worldSeed) {
        this._newCharacter(rec, connId, rec.save ? 'world_changed' : 'no_save');
        return { ok: true, action: 'new_character', playerId: playerId };
      }
      const r = sanitizeSave(rec.save, { playerId: playerId, worldSeed: this.worldSeed });
      if (!r.save) {
        this._log('error', 'save corrompido de', playerId, r.issues);
        this._newCharacter(rec, connId, 'corrupt_save');
        return { ok: true, action: 'new_character', playerId: playerId };
      }
      const save = r.save;
      if (this.rules.survivalDecayWhileOffline === 'running' && rec.offlineSince) {
        applyOfflineDecay(save, (now - rec.offlineSince) / 1000, this.rules);
      }
      if (typeof this.hooks.validatePosition === 'function') {
        try { const p = this.hooks.validatePosition(save.pos); if (p && isNum(p.x) && isNum(p.y) && isNum(p.z)) save.pos = { x: p.x, y: p.y, z: p.z }; } catch (e) { this._log('error', 'validatePosition falhou:', e && e.message); }
      }
      if (!save.pos) {
        this._newCharacter(rec, connId, 'bad_pos');
        return { ok: true, action: 'new_character', playerId: playerId };
      }
      const rr = this.ledger.reconcilePlayerSave(save, playerId);
      if (rr.removed.length) {
        this._log('warn', 'itens duplicados removidos do save de', playerId, rr.removed);
        if (typeof this.hooks.onDuplicateRemoved === 'function') { try { this.hooks.onDuplicateRemoved(playerId, rr.removed); } catch (e) { /* ignora */ } }
      }
      rec.save = save; rec.status = 'joining'; rec.dirty = false;
      this._send(connId, { t: MSG.RESUME_OK, instant: false, save: clone(save), world: this._worldMsg(save.pos), worldSeed: this.worldSeed, roomId: this.roomId, serverTime: now });
      return { ok: true, action: 'resume', instant: false, playerId: playerId };
    }

    /** Cliente terminou o loading → o host cria o boneco no mundo. */
    markReady(playerId) {
      const rec = this.players.get(playerId);
      if (!rec || rec.status !== 'joining' || !rec.save || !rec.connId) return false;
      rec.status = 'online'; rec.dirty = true;
      if (typeof this.hooks.spawnBody === 'function') {
        try { this.hooks.spawnBody(playerId, clone(rec.save)); } catch (e) { this._log('error', 'spawnBody falhou:', e && e.message); }
      }
      return true;
    }

    /** O jogo chama quando um personagem NOVO acabou de nascer (depois da tela de spawn). */
    onCharacterSpawned(playerId, save) {
      const rec = this.players.get(playerId);
      if (!rec) return false;
      rec.status = 'online'; rec.dead = false; rec.diedWhileOffline = false; rec.deathInfo = null; rec.logoutDeadline = 0; rec.dirty = true;
      if (save) {
        const r = sanitizeSave(save, { playerId: playerId, worldSeed: this.worldSeed });
        if (r.save) { r.save.lastSeen = this._now(); rec.save = r.save; this.ledger.reconcilePlayerSave(r.save, playerId); }
      } else this._snapshot(rec);
      return true;
    }

    /** Marca que o estado do jogador mudou (o autosave grava em até autosaveIntervalMs). */
    markDirty(playerId) { const r = this.players.get(playerId); if (r) r.dirty = true; }
    /** Grava agora (pegar/soltar/equipar/usar item, dano, sair de veículo, trocar de arma...). */
    saveNow(playerId) { const r = this.players.get(playerId); return r ? this._snapshot(r) : null; }

    _snapshot(rec) {
      if (typeof this.hooks.snapshotPlayer !== 'function') return rec.save;
      let raw;
      try { raw = this.hooks.snapshotPlayer(rec.playerId); } catch (e) { this._log('error', 'snapshotPlayer falhou:', e && e.message); return rec.save; }
      if (!raw) return rec.save;
      const r = sanitizeSave(raw, { playerId: rec.playerId, worldSeed: this.worldSeed });
      if (!r.save) { this._log('warn', 'snapshot inválido de', rec.playerId, r.issues); return rec.save; }
      r.save.lastSeen = this._now();
      rec.save = r.save; rec.dirty = false;
      return rec.save;
    }

    /** O jogo chama quando o corpo de um jogador morre (online ou dentro do timer de logout). */
    onPlayerDied(playerId, info) {
      const rec = this.players.get(playerId);
      if (!rec) return false;
      const now = this._now();
      const wasLinger = rec.status === 'lingering';
      rec.save = null; rec.dirty = false;
      this.ledger.removeAllAt(LOC.player(playerId)); // o loot agora é do corpo (o jogo já deve ter movido pelo ledger)
      if (wasLinger) {
        rec.diedWhileOffline = true; rec.deathInfo = info ? clone(info) : null;
        rec.status = 'offline'; rec.logoutDeadline = 0; rec.offlineSince = now; rec.lastSeen = now;
      } else rec.dead = true;
      return true;
    }

    /** O jogo (ou o PeerJS) avisa que a conexão caiu: close/error. O heartbeat também chama isto. */
    onConnectionLost(connId) {
      const c = this.conns.get(connId);
      if (!c) return;
      this.conns.delete(connId);
      const rec = this.players.get(c.playerId);
      if (!rec || rec.connId !== connId) return; // já foi substituída por outra conexão
      const now = this._now();
      rec.connId = null; rec.lastSeen = now;
      if (rec.status === 'online' && !rec.dead) {
        this._snapshot(rec);
        if (this.rules.logoutTimerSec > 0) {
          rec.status = 'lingering';
          rec.logoutDeadline = now + this.rules.logoutTimerSec * 1000;
          if (typeof this.hooks.onLinger === 'function') { try { this.hooks.onLinger(rec.playerId); } catch (e) { /* ignora */ } }
        } else this._finalizeLogout(rec, now);
      } else if (rec.status === 'joining' || rec.status === 'online') {
        rec.status = 'offline'; rec.offlineSince = now; // sem corpo no mundo (loading/tela de spawn/morto)
      }
    }
    onConnectionClosed(connId) { this.onConnectionLost(connId); }

    _finalizeLogout(rec, now) {
      let exitPos = null;
      if (typeof this.hooks.exitVehicle === 'function') {
        try { exitPos = this.hooks.exitVehicle(rec.playerId); } catch (e) { this._log('error', 'exitVehicle falhou:', e && e.message); }
      }
      const save = this._snapshot(rec) || rec.save;
      if (save && exitPos && isNum(exitPos.x) && isNum(exitPos.y) && isNum(exitPos.z)) save.pos = { x: exitPos.x, y: exitPos.y, z: exitPos.z };
      if (save) save.lastSeen = now;
      if (typeof this.hooks.removeBody === 'function') {
        try { this.hooks.removeBody(rec.playerId, save ? clone(save) : null); } catch (e) { this._log('error', 'removeBody falhou:', e && e.message); }
      }
      rec.status = 'offline'; rec.logoutDeadline = 0; rec.offlineSince = now; rec.lastSeen = now; rec.dirty = false;
    }

    /** Chame ~1x por segundo (ou use start()). Heartbeat, timers de logout, autosave e limpeza. */
    tick(nowArg) {
      if (this.closed) return;
      const now = nowArg !== undefined ? nowArg : this._now();
      for (const [connId, c] of Array.from(this.conns.entries())) {
        if (connId === this.localConnId) continue;
        const rec = this.players.get(c.playerId);
        const limit = this.rules.heartbeatTimeoutMs * (rec && rec.status === 'joining' ? 3 : 1);
        if (now - c.lastHeard > limit) { this.onConnectionLost(connId); this._closeLater(connId); }
      }
      for (const rec of Array.from(this.players.values())) {
        if (rec.status === 'lingering' && now >= rec.logoutDeadline) this._finalizeLogout(rec, now);
      }
      if (now - this._lastAutosave >= this.rules.autosaveIntervalMs) {
        this._lastAutosave = now;
        for (const rec of this.players.values()) if ((rec.status === 'online' || rec.status === 'lingering') && rec.dirty) this._snapshot(rec);
      }
      if (now - this._lastPrune >= 60000) { this._lastPrune = now; this.pruneExpired(now); }
    }

    _drop(rec) {
      this.ledger.removeAllAt(LOC.player(rec.playerId));
      this.players.delete(rec.playerId);
    }
    _makeRoom() {
      if (this.players.size < this.rules.maxSavesPerRoom) return;
      const offline = Array.from(this.players.values()).filter(function (r) { return r.status === 'offline'; })
        .sort(function (a, b) { return a.lastSeen - b.lastSeen; });
      if (offline.length) this._drop(offline[0]);
    }
    /** Remove saves de quem não volta há saveExpireHours e respeita maxSavesPerRoom. Nunca mexe em quem está jogando. */
    pruneExpired(nowArg) {
      const now = nowArg !== undefined ? nowArg : this._now();
      const maxAge = this.rules.saveExpireHours * 3600 * 1000;
      let removed = 0;
      for (const rec of Array.from(this.players.values())) {
        if (rec.status === 'offline' && now - (rec.lastSeen || rec.createdAt) > maxAge) { this._drop(rec); removed++; }
      }
      let excess = this.players.size - this.rules.maxSavesPerRoom;
      if (excess > 0) {
        const offline = Array.from(this.players.values()).filter(function (r) { return r.status === 'offline'; })
          .sort(function (a, b) { return a.lastSeen - b.lastSeen; });
        for (const rec of offline) { if (excess <= 0) break; this._drop(rec); excess--; removed++; }
      }
      this.world.pruneEmpty();
      return removed;
    }

    /**
     * Tecla N / reiniciar mundo: apaga TODO o progresso (peça confirmação ao jogador ANTES de chamar).
     * Quem está conectado vira "personagem novo" (recebe new_character reason 'world_reset').
     * O jogo continua responsável por regenerar o mapa com a nova seed.
     */
    invalidateAll(newSeed) {
      const cleared = this.players.size;
      const connected = [];
      for (const rec of Array.from(this.players.values())) {
        if (rec.connId && this.conns.has(rec.connId)) connected.push(rec);
        else this.players.delete(rec.playerId);
      }
      this.worldSeed = String(newSeed !== undefined ? newSeed : this.worldSeed);
      this.world.reset(this.worldSeed);
      this.ledger.clear();
      for (const rec of connected) this._newCharacter(rec, rec.connId, 'world_reset');
      return { clearedSaves: cleared, notifiedPlayers: connected.map(function (r) { return r.playerId; }) };
    }

    /** Servidor fechando: avisa todos os clientes (use em beforeunload do host). */
    closeServer() {
      if (this.closed) return;
      for (const connId of Array.from(this.conns.keys())) if (connId !== this.localConnId) this._send(connId, { t: MSG.SERVER_CLOSED });
      this.closed = true;
      this.stop();
    }

    stats() {
      const by = { joining: 0, online: 0, lingering: 0, offline: 0 };
      for (const r of this.players.values()) by[r.status] = (by[r.status] || 0) + 1;
      return { players: this.players.size, conns: this.conns.size, byStatus: by };
    }

    /** JSON-safe. Base para o item 11 (gravar no IndexedDB) — não usado automaticamente. */
    exportState() {
      const players = [];
      for (const r of this.players.values()) {
        players.push({ playerId: r.playerId, tokenHash: r.tokenHash, nick: r.nick, save: clone(r.save), lastSeen: r.lastSeen, createdAt: r.createdAt, diedWhileOffline: r.diedWhileOffline, deathInfo: clone(r.deathInfo) });
      }
      return { v: 1, roomId: this.roomId, worldSeed: this.worldSeed, players: players, world: this.world.exportState() };
    }
    importState(st) {
      if (!isObj(st) || st.v !== 1 || String(st.worldSeed) !== this.worldSeed) return false;
      this.players.clear(); this.conns.clear();
      for (const p of (Array.isArray(st.players) ? st.players : [])) {
        if (!isObj(p) || !ID_RE.test(String(p.playerId))) continue;
        this.players.set(p.playerId, {
          playerId: p.playerId, tokenHash: String(p.tokenHash), nick: sanitizeNick(p.nick) || 'Sobrevivente', save: p.save || null,
          status: 'offline', connId: null, lastHeard: 0, logoutDeadline: 0, lastSeen: p.lastSeen || 0, offlineSince: p.lastSeen || 0,
          createdAt: p.createdAt || 0, dirty: false, dead: false, diedWhileOffline: !!p.diedWhileOffline, deathInfo: p.deathInfo || null
        });
      }
      return this.world.importState(st.world);
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  API PÚBLICA
  // ════════════════════════════════════════════════════════════════
  return {
    PROTOCOL_VERSION: PROTOCOL_VERSION,
    SAVE_VERSION: SAVE_VERSION,
    MSG: MSG,
    OFFLINE_RULES: OFFLINE_RULES,
    LIMITS: LIMITS,
    LOC: LOC,
    isPersistenceMessage: isPersistenceMessage,
    splitMessage: splitMessage,
    Reassembler: Reassembler,
    createEmptySave: createEmptySave,
    sanitizeSave: sanitizeSave,
    migrateSave: migrateSave,
    repairIntegrity: repairIntegrity,
    applyOfflineDecay: applyOfflineDecay,
    createClientIdentity: createClientIdentity,
    createClientSession: createClientSession,
    ItemLedger: ItemLedger,
    WorldDiffStore: WorldDiffStore,
    HostPersistence: HostPersistence,
    makeSaveKey: makeSaveKey,
    sha256Hex: sha256Hex,
    _sha256Fallback: sha256Fallback,
    uuid: uuid
  };
});
