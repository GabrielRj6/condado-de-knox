/**
 * 🌲 CONDADO DE KNOX — Atualização 4: Módulo de Persistência
 * ============================================================================
 * Gerencia persistência de jogadores, anti-duplicação via ItemLedger,
 * diffs de mundo por chunk (WorldDiffStore), ciclo de vida (logout timer 30s),
 * reconexão instantânea vs loading, e handshake seguro.
 * ============================================================================
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.KnoxPersistence = factory();
  }
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const OFFLINE_RULES = {
    logoutTimerSec: 30,
    survivalDecayWhileOffline: 'paused',
    keepOfflineBodyVisible: false,
    saveExpireHours: 72,
    maxSavesPerRoom: 200
  };

  const MSG = Object.freeze({
    HELLO: 'hello',
    RESUME_OK: 'resume_ok',
    NEW_CHARACTER: 'new_character',
    RESUME_DENIED: 'resume_denied',
    KICKED_DUPLICATE: 'kicked_duplicate',
    SERVER_CLOSED: 'server_closed',
    PING: 'ping',
    PONG: 'pong',
    RESUME_READY: 'resume_ready',
    PART: 'part'
  });

  const LOC = Object.freeze({
    world: (chunkId) => `world:${chunkId}`,
    player: (id) => `player:${id}`,
    container: (id) => `container:${id}`,
    vehicle: (id) => `vehicle:${id}`,
    corpse: (id) => `corpse:${id}`
  });

  function isPersistenceMessage(msg) {
    if (!msg || typeof msg !== 'object') return false;
    const t = msg.t;
    return typeof t === 'string' && Object.values(MSG).includes(t);
  }

  function createEmptySave(opts = {}) {
    return {
      v: 1,
      playerId: opts.playerId || '',
      nick: opts.nick || '',
      color: opts.color || '#e0d8cc',
      alive: opts.alive !== false,
      pos: opts.pos ? { x: Number(opts.pos.x) || 0, y: Number(opts.pos.y) || 0, z: Number(opts.pos.z) || 0 } : { x: 0, y: 0, z: 0 },
      yaw: Number(opts.yaw) || 0,
      stance: ['stand', 'crouch', 'prone'].includes(opts.stance) ? opts.stance : 'stand',
      stats: {
        hp: Math.max(0, Math.min(100, opts.stats?.hp ?? 100)),
        food: Math.max(0, Math.min(100, opts.stats?.food ?? 80)),
        water: Math.max(0, Math.min(100, opts.stats?.water ?? 70)),
        stamina: Math.max(0, Math.min(100, opts.stats?.stamina ?? 100)),
        temp: Number(opts.stats?.temp) || 36.6
      },
      conditions: Array.isArray(opts.conditions) ? opts.conditions.slice() : [],
      equipment: opts.equipment && typeof opts.equipment === 'object'
        ? { hands: opts.equipment.hands || null, back: opts.equipment.back || null, body: opts.equipment.body || null }
        : { hands: null, back: null, body: null },
      items: opts.items && typeof opts.items === 'object' ? JSON.parse(JSON.stringify(opts.items)) : {},
      squad: Array.isArray(opts.squad) ? opts.squad.slice() : [],
      spawnRegion: opts.spawnRegion || '',
      lastSeen: opts.lastSeen || Date.now()
    };
  }

  function sanitizeSave(raw) {
    const issues = [];
    if (!raw || typeof raw !== 'object') {
      return { save: createEmptySave(), issues: ['invalid_save_object'] };
    }
    const save = { ...raw };
    save.v = 1;
    if (!save.playerId || typeof save.playerId !== 'string') {
      save.playerId = 'anon_' + Math.random().toString(36).slice(2, 10);
      issues.push('missing_player_id');
    }
    save.nick = typeof save.nick === 'string' ? save.nick.slice(0, 32) : 'Sobrevivente';
    save.alive = Boolean(save.alive);
    save.pos = save.pos && typeof save.pos === 'object'
      ? { x: Number(save.pos.x) || 0, y: Number(save.pos.y) || 0, z: Number(save.pos.z) || 0 }
      : { x: 0, y: 0, z: 0 };
    save.yaw = Number(save.yaw) || 0;
    save.stance = ['stand', 'crouch', 'prone'].includes(save.stance) ? save.stance : 'stand';
    save.stats = save.stats && typeof save.stats === 'object' ? save.stats : {};
    save.stats.hp = Math.max(0, Math.min(100, Number(save.stats.hp) ?? 100));
    save.stats.food = Math.max(0, Math.min(100, Number(save.stats.food) ?? 80));
    save.stats.water = Math.max(0, Math.min(100, Number(save.stats.water) ?? 70));
    save.stats.stamina = Math.max(0, Math.min(100, Number(save.stats.stamina) ?? 100));
    save.stats.temp = Number(save.stats.temp) || 36.6;
    if (!Array.isArray(save.conditions)) save.conditions = [];
    if (!save.equipment || typeof save.equipment !== 'object') save.equipment = { hands: null, back: null, body: null };
    if (!save.items || typeof save.items !== 'object') save.items = {};
    if (!Array.isArray(save.squad)) save.squad = [];
    save.lastSeen = Number(save.lastSeen) || Date.now();
    return { save, issues };
  }

  // Hash SHA-256 (compatível com Browser crypto.subtle e Node.js)
  async function hashToken(token) {
    const str = String(token || '');
    if (typeof globalThis !== 'undefined' && globalThis.crypto && globalThis.crypto.subtle) {
      const data = new TextEncoder().encode(str);
      const digest = await globalThis.crypto.subtle.digest('SHA-256', data);
      return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('');
    }
    // Fallback síncrono/Node.js sem SubtleCrypto
    try {
      const nodeCrypto = await import('crypto');
      return nodeCrypto.createHash('sha256').update(str).digest('hex');
    } catch (_) {
      let h1 = 0xdeadbeef ^ str.length, h2 = 0x41c6ceed ^ str.length;
      for (let i = 0, ch; i < str.length; i++) {
        ch = str.charCodeAt(i);
        h1 = Math.imul(h1 ^ ch, 2654435761);
        h2 = Math.imul(h2 ^ ch, 1597334677);
      }
      h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
      h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
      return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(16).padStart(16, '0');
    }
  }

  function randomToken(len = 32) {
    if (typeof globalThis !== 'undefined' && globalThis.crypto && globalThis.crypto.getRandomValues) {
      const arr = new Uint8Array(len);
      globalThis.crypto.getRandomValues(arr);
      return Array.from(arr).map(b => b.toString(16).padStart(2, '0')).join('').slice(0, len);
    }
    let res = '';
    while (res.length < len) {
      res += Math.random().toString(36).slice(2);
    }
    return res.slice(0, len);
  }

  function randomUUID() {
    if (typeof globalThis !== 'undefined' && globalThis.crypto && typeof globalThis.crypto.randomUUID === 'function') {
      return globalThis.crypto.randomUUID();
    }
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  /**
   * Identidade persistente única do jogador no cliente (localStorage)
   */
  function createClientIdentity(opts = {}) {
    const profile = opts.profile ? `:${opts.profile}` : '';
    const key = `knox.identity.v1${profile}`;
    let stored = null;
    try {
      if (typeof localStorage !== 'undefined') {
        const raw = localStorage.getItem(key);
        if (raw) stored = JSON.parse(raw);
      }
    } catch (_) {}

    if (!stored || !stored.playerId || !stored.token) {
      stored = {
        playerId: randomUUID(),
        token: randomToken(32),
        createdAt: Date.now()
      };
      try {
        if (typeof localStorage !== 'undefined') {
          localStorage.setItem(key, JSON.stringify(stored));
        }
      } catch (_) {}
    }

    return {
      playerId: stored.playerId,
      token: stored.token,
      buildHello({ nick = '' } = {}) {
        return {
          t: MSG.HELLO,
          playerId: stored.playerId,
          token: stored.token,
          nick: String(nick || '').slice(0, 32),
          version: 1
        };
      }
    };
  }

  /**
   * Sessão do cliente gerenciando handshake e respostas do host
   */
  function createClientSession(opts = {}) {
    const identity = opts.identity || createClientIdentity();
    const getNick = typeof opts.nick === 'function' ? opts.nick : () => (opts.nick || 'Sobrevivente');
    const send = typeof opts.send === 'function' ? opts.send : () => {};
    const handlers = opts.handlers || {};

    let pingTimer = null;
    let timeoutTimer = null;
    let started = false;

    function resetTimeout() {
      if (timeoutTimer) clearTimeout(timeoutTimer);
      timeoutTimer = setTimeout(() => {
        if (handlers.onTimeout) handlers.onTimeout();
      }, 15000);
      if (timeoutTimer && typeof timeoutTimer.unref === 'function') timeoutTimer.unref();
    }

    function start() {
      started = true;
      const hello = identity.buildHello({ nick: getNick() });
      send(hello);
      resetTimeout();
      if (!pingTimer) {
        pingTimer = setInterval(() => {
          if (started) send({ t: MSG.PING });
        }, 5000);
        if (pingTimer && typeof pingTimer.unref === 'function') pingTimer.unref();
      }
    }

    function stop() {
      started = false;
      if (pingTimer) { clearInterval(pingTimer); pingTimer = null; }
      if (timeoutTimer) { clearTimeout(timeoutTimer); timeoutTimer = null; }
    }

    function sendReady() {
      send({ t: MSG.RESUME_READY, playerId: identity.playerId });
    }

    function receive(msg) {
      if (!isPersistenceMessage(msg)) return false;
      resetTimeout();

      switch (msg.t) {
        case MSG.RESUME_OK:
          if (handlers.onResumeOk) handlers.onResumeOk(msg);
          return true;
        case MSG.NEW_CHARACTER:
          if (handlers.onNewCharacter) handlers.onNewCharacter(msg);
          return true;
        case MSG.RESUME_DENIED:
          if (handlers.onDenied) handlers.onDenied(msg);
          return true;
        case MSG.KICKED_DUPLICATE:
          stop();
          if (handlers.onKicked) handlers.onKicked(msg);
          return true;
        case MSG.SERVER_CLOSED:
          stop();
          if (handlers.onServerClosed) handlers.onServerClosed(msg);
          return true;
        case MSG.PING:
          send({ t: MSG.PONG });
          return true;
        case MSG.PONG:
          return true;
      }
      return false;
    }

    return {
      identity,
      start,
      stop,
      sendReady,
      receive
    };
  }

  /**
   * ItemLedger: Controle rigoroso de posse e prevenção de duplicação
   */
  class ItemLedger {
    constructor() {
      this._locations = new Map(); // uid -> locationString
      this._items = new Map();     // locationString -> Set<uid>
      this._meta = new Map();      // uid -> metadata (type, ammo, attachments, etc.)
    }

    register(uid, loc, meta = null) {
      if (!uid || !loc) return false;
      const oldLoc = this._locations.get(uid);
      if (oldLoc) {
        const oldSet = this._items.get(oldLoc);
        if (oldSet) oldSet.delete(uid);
      }
      this._locations.set(uid, loc);
      let set = this._items.get(loc);
      if (!set) {
        set = new Set();
        this._items.set(loc, set);
      }
      set.add(uid);
      if (meta) this._meta.set(uid, meta);
      return true;
    }

    move(uid, from, to) {
      if (!uid || !to) return { ok: false, reason: 'missing_arguments' };
      const cur = this._locations.get(uid);
      if (from !== undefined && from !== null && cur !== from) {
        return { ok: false, reason: 'location_mismatch', actual: cur || null };
      }
      if (cur) {
        const oldSet = this._items.get(cur);
        if (oldSet) oldSet.delete(uid);
      }
      this._locations.set(uid, to);
      let newSet = this._items.get(to);
      if (!newSet) {
        newSet = new Set();
        this._items.set(to, newSet);
      }
      newSet.add(uid);
      return { ok: true };
    }

    locationOf(uid) {
      return this._locations.get(uid) || null;
    }

    itemsAt(loc) {
      const set = this._items.get(loc);
      return set ? Array.from(set) : [];
    }

    metaOf(uid) {
      return this._meta.get(uid) || null;
    }

    remove(uid) {
      const loc = this._locations.get(uid);
      if (loc) {
        const set = this._items.get(loc);
        if (set) set.delete(uid);
      }
      this._locations.delete(uid);
      this._meta.delete(uid);
    }

    clear() {
      this._locations.clear();
      this._items.clear();
      this._meta.clear();
    }
  }

  /**
   * WorldDiffStore: Store global por chunkId separado dos chunks carregados na GPU/cena
   */
  class WorldDiffStore {
    constructor(opts = {}) {
      this.worldSeed = opts.worldSeed || 0;
      this._chunks = new Map();   // chunkId -> { takenLoot: Set, droppedLoot: Map, doors: Map, containers: Map, bodies: Map, objects: Map }
      this._vehicles = new Map(); // id -> vehicleState
      this._timers = new Map();   // key -> { dueAt, payload }
      this._misc = new Map();     // key -> value (ex: clock, weather)
    }

    _getChunk(chunkId) {
      let c = this._chunks.get(chunkId);
      if (!c) {
        c = {
          takenLoot: new Set(),
          droppedLoot: new Map(), // uid -> itemObject
          doors: new Map(),       // doorId -> isOpen (boolean)
          containers: new Map(),  // containerId -> state
          bodies: new Map(),      // id -> bodyObject
          objects: new Map()      // id -> placedObject
        };
        this._chunks.set(chunkId, c);
      }
      return c;
    }

    itemTaken(chunkId, uid, opts = null) {
      if (!chunkId || !uid) return;
      const c = this._getChunk(chunkId);
      c.takenLoot.add(uid);
      c.droppedLoot.delete(uid);
      if (opts && opts.respawnAt) {
        this.setTimer(`loot_respawn:${chunkId}:${uid}`, opts.respawnAt, { chunkId, uid });
      }
    }

    itemDropped(chunkId, item) {
      if (!chunkId || !item || !item.uid) return;
      const c = this._getChunk(chunkId);
      c.droppedLoot.set(item.uid, { ...item });
      c.takenLoot.delete(item.uid);
    }

    applyLoot(chunkId, generatedLoot) {
      const c = this._getChunk(chunkId);
      const res = [];
      if (Array.isArray(generatedLoot)) {
        for (const item of generatedLoot) {
          if (!item || !item.uid) continue;
          if (!c.takenLoot.has(item.uid)) {
            res.push(item);
          }
        }
      }
      for (const dropped of c.droppedLoot.values()) {
        res.push(dropped);
      }
      return res;
    }

    setDoor(chunkId, doorId, isOpen) {
      this._getChunk(chunkId).doors.set(doorId, Boolean(isOpen));
    }

    getDoor(chunkId, doorId) {
      const c = this._chunks.get(chunkId);
      if (!c) return null;
      return c.doors.has(doorId) ? c.doors.get(doorId) : null;
    }

    setContainer(chunkId, containerId, state) {
      this._getChunk(chunkId).containers.set(containerId, JSON.parse(JSON.stringify(state)));
    }

    getContainer(chunkId, containerId) {
      const c = this._chunks.get(chunkId);
      if (!c || !c.containers.has(containerId)) return null;
      return JSON.parse(JSON.stringify(c.containers.get(containerId)));
    }

    addBody(chunkId, body) {
      if (!body || !body.id) return;
      this._getChunk(chunkId).bodies.set(body.id, { ...body });
    }

    removeBody(chunkId, bodyId) {
      const c = this._chunks.get(chunkId);
      if (c) c.bodies.delete(bodyId);
    }

    placeObject(chunkId, obj) {
      if (!obj || !obj.id) return;
      this._getChunk(chunkId).objects.set(obj.id, { ...obj });
    }

    removeObject(chunkId, objId) {
      const c = this._chunks.get(chunkId);
      if (c) c.objects.delete(objId);
    }

    saveVehicle(id, state) {
      if (!id || !state) return;
      this._vehicles.set(id, JSON.parse(JSON.stringify(state)));
    }

    getVehicle(id) {
      const v = this._vehicles.get(id);
      return v ? JSON.parse(JSON.stringify(v)) : null;
    }

    getAllVehicles() {
      const res = {};
      for (const [id, v] of this._vehicles.entries()) {
        res[id] = JSON.parse(JSON.stringify(v));
      }
      return res;
    }

    setTimer(key, timestamp, payload = null) {
      this._timers.set(key, { dueAt: Number(timestamp) || Date.now(), payload });
    }

    takeDueTimers(now = Date.now()) {
      const due = [];
      for (const [key, t] of this._timers.entries()) {
        if (t.dueAt <= now) {
          due.push({ key, payload: t.payload });
          this._timers.delete(key);
        }
      }
      return due;
    }

    setMisc(key, val) {
      this._misc.set(key, JSON.parse(JSON.stringify(val)));
    }

    getMisc(key) {
      const v = this._misc.get(key);
      return v !== undefined ? JSON.parse(JSON.stringify(v)) : null;
    }

    snapshotNear(chunkIds = []) {
      const chunksData = {};
      for (const cid of chunkIds) {
        const c = this._chunks.get(cid);
        if (c) {
          chunksData[cid] = {
            takenLoot: Array.from(c.takenLoot),
            droppedLoot: Array.from(c.droppedLoot.values()),
            doors: Object.fromEntries(c.doors.entries()),
            containers: Object.fromEntries(c.containers.entries()),
            bodies: Array.from(c.bodies.values()),
            objects: Array.from(c.objects.values())
          };
        }
      }
      return {
        chunks: chunksData,
        vehicles: this.getAllVehicles(),
        misc: Object.fromEntries(this._misc.entries())
      };
    }

    clear() {
      this._chunks.clear();
      this._vehicles.clear();
      this._timers.clear();
      this._misc.clear();
    }
  }

  /**
   * HostPersistence: Motor autoritativo do host para saves, ciclo de vida e sessões
   */
  class HostPersistence {
    constructor(opts = {}) {
      this.roomId = opts.roomId || 'local';
      this.worldSeed = opts.worldSeed || 0;
      this.world = opts.world || new WorldDiffStore({ worldSeed: this.worldSeed });
      this.ledger = opts.ledger || new ItemLedger();
      this.localConnId = opts.localConnId || 'local';
      this.hooks = opts.hooks || {};

      this._saves = new Map();         // playerId -> { tokenHash, nick, save, connId, status, disconnectTimer, deathInfo, dirty, lastSeen }
      this._connToPlayer = new Map();  // connId -> playerId
      this._interval = null;
    }

    start() {
      if (this._interval) return;
      this._interval = setInterval(() => {
        this._tick();
      }, 1000);
      if (this._interval && typeof this._interval.unref === 'function') this._interval.unref();
    }

    stop() {
      if (this._interval) {
        clearInterval(this._interval);
        this._interval = null;
      }
    }

    playerIdOf(connId) {
      return this._connToPlayer.get(connId) || null;
    }

    statusOf(playerId) {
      const r = this._saves.get(playerId);
      return r ? r.status : null;
    }

    stats() {
      return {
        totalSaves: this._saves.size,
        activePlayers: Array.from(this._saves.values()).filter(s => s.status === 'online').length,
        disconnecting: Array.from(this._saves.values()).filter(s => s.status === 'disconnecting').length
      };
    }

    async handleHello(connId, msg) {
      if (!msg || msg.t !== MSG.HELLO) return false;
      const playerId = String(msg.playerId || '').trim();
      const token = String(msg.token || '');
      const nick = String(msg.nick || 'Sobrevivente').slice(0, 32);

      if (!playerId || !token) {
        this._send(connId, { t: MSG.RESUME_DENIED, reason: 'missing_credentials' });
        return true;
      }

      const tHash = await hashToken(token);
      let record = this._saves.get(playerId);

      // 1. Jogador Novo
      if (!record) {
        if (this._saves.size >= OFFLINE_RULES.maxSavesPerRoom) {
          this._pruneOldestSave();
        }
        const empty = createEmptySave({ playerId, nick });
        record = {
          tokenHash: tHash,
          nick,
          save: empty,
          connId,
          status: 'pending_spawn',
          disconnectTimer: null,
          deathInfo: null,
          dirty: false,
          lastSeen: Date.now()
        };
        this._saves.set(playerId, record);
        this._connToPlayer.set(connId, playerId);
        this._send(connId, { t: MSG.NEW_CHARACTER, playerId });
        return true;
      }

      // 2. Jogador Conhecido -> Validação rigorosa de token ANTES de qualquer ação
      if (record.tokenHash !== tHash) {
        this._send(connId, { t: MSG.RESUME_DENIED, reason: 'invalid_token' });
        return true;
      }

      // Conexão duplicada autorizada (mesma conta em outra aba ou F5 rápido) -> derruba a conexão antiga
      if (record.connId && record.connId !== connId) {
        this._send(record.connId, { t: MSG.KICKED_DUPLICATE });
        if (this.hooks.close) {
          try { this.hooks.close(record.connId); } catch (e) { console.warn('Host close hook error:', e); }
        }
        this._connToPlayer.delete(record.connId);
      }

      // Atualiza vínculo de conexão
      this._connToPlayer.set(connId, playerId);
      record.connId = connId;
      record.lastSeen = Date.now();
      if (nick) record.nick = nick;

      // Se morreu enquanto estava offline
      if (!record.save.alive) {
        record.status = 'pending_spawn';
        this._send(connId, {
          t: MSG.NEW_CHARACTER,
          playerId,
          diedWhileOffline: true,
          deathInfo: record.deathInfo || null
        });
        return true;
      }

      // Retomada: se o boneco ainda está no mundo (online ou nos 30s de logout) -> instantâneo
      const bonecoInWorld = record.status === 'online' || record.status === 'disconnecting';
      if (record.disconnectTimer) {
        clearTimeout(record.disconnectTimer);
        record.disconnectTimer = null;
      }
      record.status = 'online';

      const pos = record.save.pos;
      const chunks = this.hooks.chunksNear ? (this.hooks.chunksNear(pos) || []) : [];
      const worldSnap = this.world.snapshotNear(chunks);

      if (bonecoInWorld) {
        // O boneco ainda está no mundo: religa conexão diretamente sem reload de chunks
        if (this.hooks.reattachBody) {
          try { this.hooks.reattachBody(playerId, connId); } catch (e) { console.warn('reattachBody error:', e); }
        }
        this._send(connId, {
          t: MSG.RESUME_OK,
          save: record.save,
          world: worldSnap,
          instant: true
        });
      } else {
        // Boneco estava descarregado (offline após os 30s): cliente pré-carrega chunks e envia resume_ready
        this._send(connId, {
          t: MSG.RESUME_OK,
          save: record.save,
          world: worldSnap,
          instant: false
        });
      }
      return true;
    }

    handleMessage(connId, msg) {
      if (!msg || typeof msg !== 'object') return false;
      const t = msg.t;
      if (!isPersistenceMessage(msg)) return false;

      if (t === MSG.HELLO) {
        this.handleHello(connId, msg);
        return true;
      }

      const playerId = this._connToPlayer.get(connId);
      if (!playerId) return true; // Ignora se não autenticado

      const record = this._saves.get(playerId);
      if (record) record.lastSeen = Date.now();

      if (t === MSG.RESUME_READY) {
        if (record && record.status === 'online' && record.save.alive) {
          if (this.hooks.spawnBody) {
            try { this.hooks.spawnBody(playerId, record.save); } catch (e) { console.warn('spawnBody error:', e); }
          }
        }
        return true;
      }

      if (t === MSG.PING) {
        this._send(connId, { t: MSG.PONG });
        return true;
      }

      if (t === MSG.PONG) {
        return true;
      }

      if (t === MSG.PART) {
        this.onConnectionLost(connId);
        return true;
      }

      return false;
    }

    onConnectionLost(connId) {
      const playerId = this._connToPlayer.get(connId);
      if (!playerId) return;
      this._connToPlayer.delete(connId);

      const record = this._saves.get(playerId);
      if (!record || record.status !== 'online') return;

      this.saveNow(playerId);
      record.status = 'disconnecting';
      record.connId = null;

      // Timer de logout de 30s para evitar "combat log"
      record.disconnectTimer = setTimeout(() => {
        this._finalizeLogout(playerId);
      }, OFFLINE_RULES.logoutTimerSec * 1000);
      if (record.disconnectTimer && typeof record.disconnectTimer.unref === 'function') {
        record.disconnectTimer.unref();
      }
    }

    _finalizeLogout(playerId) {
      const record = this._saves.get(playerId);
      if (!record || record.status !== 'disconnecting') return;
      record.disconnectTimer = null;
      record.status = 'offline';

      // Se estava em veículo, ejeta para posição livre segura
      if (this.hooks.exitVehicle) {
        try {
          const freePos = this.hooks.exitVehicle(playerId);
          if (freePos && record.save) {
            record.save.pos = { x: freePos.x, y: freePos.y, z: freePos.z };
          }
        } catch (e) { console.warn('exitVehicle error:', e); }
      }

      // Valida posição antes de persistir
      if (this.hooks.validatePosition && record.save) {
        try {
          const valid = this.hooks.validatePosition(record.save.pos);
          if (valid) record.save.pos = { x: valid.x, y: valid.y, z: valid.z };
        } catch (e) { console.warn('validatePosition error:', e); }
      }

      // Remove boneco do mundo
      if (this.hooks.removeBody) {
        try { this.hooks.removeBody(playerId, record.save); } catch (e) { console.warn('removeBody error:', e); }
      }

      this.saveNow(playerId);
    }

    onCharacterSpawned(playerId) {
      const record = this._saves.get(playerId);
      if (!record) return;
      record.status = 'online';
      record.save.alive = true;
      this.saveNow(playerId);
    }

    onPlayerDied(playerId, info = null) {
      const record = this._saves.get(playerId);
      if (!record) return;
      record.deathInfo = info || { by: 'unknown', at: { ...record.save.pos } };
      record.save.alive = false;
      this.saveNow(playerId);
    }

    saveNow(playerId) {
      const record = this._saves.get(playerId);
      if (!record) return;
      if (this.hooks.snapshotPlayer) {
        try {
          const snap = this.hooks.snapshotPlayer(playerId);
          if (snap) {
            const { save } = sanitizeSave(snap);
            record.save = save;
          }
        } catch (e) { console.warn('snapshotPlayer error:', e); }
      }
      record.dirty = false;
      record.lastSeen = Date.now();
    }

    markDirty(playerId) {
      const record = this._saves.get(playerId);
      if (record) record.dirty = true;
    }

    invalidateAll(newSeed) {
      this.worldSeed = newSeed || 0;
      this.world.clear();
      this.ledger.clear();
      for (const record of this._saves.values()) {
        if (record.disconnectTimer) clearTimeout(record.disconnectTimer);
      }
      this._saves.clear();
      this._connToPlayer.clear();
    }

    closeServer() {
      for (const connId of this._connToPlayer.keys()) {
        this._send(connId, { t: MSG.SERVER_CLOSED });
      }
      this.stop();
    }

    _send(connId, msg) {
      if (this.hooks.send) {
        try { this.hooks.send(connId, msg); } catch (e) { console.warn('send hook error:', e); }
      }
    }

    _tick() {
      const now = Date.now();
      const expireMs = OFFLINE_RULES.saveExpireHours * 3600 * 1000;

      for (const [playerId, record] of this._saves.entries()) {
        if (record.dirty && record.status === 'online') {
          this.saveNow(playerId);
        }
        if (record.status === 'offline' && now - record.lastSeen > expireMs) {
          this._saves.delete(playerId);
        }
      }
    }

    _pruneOldestSave() {
      let oldestId = null;
      let oldestTime = Infinity;
      for (const [id, rec] of this._saves.entries()) {
        if (rec.status === 'offline' && rec.lastSeen < oldestTime) {
          oldestTime = rec.lastSeen;
          oldestId = id;
        }
      }
      if (oldestId) this._saves.delete(oldestId);
    }
  }

  return {
    OFFLINE_RULES,
    MSG,
    LOC,
    isPersistenceMessage,
    createEmptySave,
    sanitizeSave,
    hashToken,
    createClientIdentity,
    createClientSession,
    ItemLedger,
    WorldDiffStore,
    HostPersistence
  };
});
