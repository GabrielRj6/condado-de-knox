import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const KP = require('../knox-persistence.js');

test('KP: constants and OFFLINE_RULES', () => {
  assert.equal(KP.OFFLINE_RULES.logoutTimerSec, 30);
  assert.equal(KP.OFFLINE_RULES.survivalDecayWhileOffline, 'paused');
  assert.equal(KP.OFFLINE_RULES.keepOfflineBodyVisible, false);
  assert.equal(KP.OFFLINE_RULES.saveExpireHours, 72);
  assert.equal(KP.OFFLINE_RULES.maxSavesPerRoom, 200);
  assert.equal(KP.MSG.HELLO, 'hello');
  assert.equal(KP.MSG.RESUME_OK, 'resume_ok');
  assert.equal(KP.MSG.SERVER_CLOSED, 'server_closed');
});

test('KP.LOC helpers', () => {
  assert.equal(KP.LOC.world('0,0'), 'world:0,0');
  assert.equal(KP.LOC.player('p1'), 'player:p1');
  assert.equal(KP.LOC.container('c1'), 'container:c1');
  assert.equal(KP.LOC.vehicle('v1'), 'vehicle:v1');
  assert.equal(KP.LOC.corpse('dead1'), 'corpse:dead1');
});

test('KP.isPersistenceMessage detects valid messages and ignores others', () => {
  assert.equal(KP.isPersistenceMessage({ t: 'hello' }), true);
  assert.equal(KP.isPersistenceMessage({ t: 'resume_ok' }), true);
  assert.equal(KP.isPersistenceMessage({ t: 'server_closed' }), true);
  assert.equal(KP.isPersistenceMessage({ t: 'pos', x: 0 }), false);
  assert.equal(KP.isPersistenceMessage(null), false);
  assert.equal(KP.isPersistenceMessage('hello'), false);
});

test('KP.createEmptySave and sanitizeSave', () => {
  const empty = KP.createEmptySave({ playerId: 'test-1', nick: 'Survivor' });
  assert.equal(empty.v, 1);
  assert.equal(empty.playerId, 'test-1');
  assert.equal(empty.nick, 'Survivor');
  assert.equal(empty.alive, true);
  assert.equal(empty.stats.hp, 100);

  const { save, issues } = KP.sanitizeSave({
    playerId: 'p2',
    stats: { hp: 150, food: -10 },
    stance: 'invalid_stance'
  });
  assert.equal(save.stats.hp, 100);
  assert.equal(save.stats.food, 0);
  assert.equal(save.stance, 'stand');
  assert.equal(issues.length, 0);

  const invalid = KP.sanitizeSave(null);
  assert.ok(invalid.issues.includes('invalid_save_object'));
});

test('KP.hashToken returns stable SHA-256 hash', async () => {
  const h1 = await KP.hashToken('my-secret-token');
  const h2 = await KP.hashToken('my-secret-token');
  const h3 = await KP.hashToken('different-token');
  assert.equal(typeof h1, 'string');
  assert.equal(h1.length, 64);
  assert.equal(h1, h2);
  assert.notEqual(h1, h3);
});

test('ItemLedger: atomic move and anti-duplication', () => {
  const ledger = new KP.ItemLedger();
  const uid = 'item_m4a1_01';
  const worldLoc = KP.LOC.world('0,0');
  const playerLoc = KP.LOC.player('p_alpha');
  const player2Loc = KP.LOC.player('p_beta');

  ledger.register(uid, worldLoc, { type: 'm4a1', ammo: 30 });
  assert.equal(ledger.locationOf(uid), worldLoc);
  assert.deepEqual(ledger.itemsAt(worldLoc), [uid]);

  // Pegar do chão para jogador
  const r1 = ledger.move(uid, worldLoc, playerLoc);
  assert.equal(r1.ok, true);
  assert.equal(ledger.locationOf(uid), playerLoc);
  assert.deepEqual(ledger.itemsAt(worldLoc), []);
  assert.deepEqual(ledger.itemsAt(playerLoc), [uid]);

  // Tentativa de duplicar: segundo jogador tenta pegar do chão de onde já saiu
  const rDup = ledger.move(uid, worldLoc, player2Loc);
  assert.equal(rDup.ok, false);
  assert.equal(rDup.reason, 'location_mismatch');
  assert.equal(rDup.actual, playerLoc);
  assert.equal(ledger.locationOf(uid), playerLoc);

  // Mover do jogador para o outro jogador
  const r2 = ledger.move(uid, playerLoc, player2Loc);
  assert.equal(r2.ok, true);
  assert.equal(ledger.locationOf(uid), player2Loc);
});

test('WorldDiffStore: loot diffs across unload and reload', () => {
  const store = new KP.WorldDiffStore({ worldSeed: 4242 });
  const cid = '1,2';
  const item1 = { uid: '4242:1,2:0', type: 'knife' };
  const item2 = { uid: '4242:1,2:1', type: 'canteen' };

  // Loot gerado inicial do chunk
  const initial = store.applyLoot(cid, [item1, item2]);
  assert.equal(initial.length, 2);

  // Jogador pega item 1
  store.itemTaken(cid, item1.uid);
  const afterTake = store.applyLoot(cid, [item1, item2]);
  assert.equal(afterTake.length, 1);
  assert.equal(afterTake[0].uid, item2.uid);

  // Jogador larga uma arma que trouxe de outro lugar
  const droppedGun = { uid: 'player_drop_99', type: 'ak47', x: 10, y: 0, z: 12 };
  store.itemDropped(cid, droppedGun);

  // Recarregando o chunk do zero com a seed: o item pego continua fora e o largado continua lá
  const reloaded = store.applyLoot(cid, [item1, item2]);
  assert.equal(reloaded.length, 2);
  const uids = reloaded.map(i => i.uid);
  assert.ok(uids.includes(item2.uid));
  assert.ok(uids.includes(droppedGun.uid));
  assert.ok(!uids.includes(item1.uid));
});

test('WorldDiffStore: doors, containers, vehicles and snapshotNear', () => {
  const store = new KP.WorldDiffStore({ worldSeed: 777 });
  store.setDoor('0,0', 'door_house_1', true);
  assert.equal(store.getDoor('0,0', 'door_house_1'), true);

  store.setContainer('0,0', 'chest_1', { items: ['bandage'] });
  assert.deepEqual(store.getContainer('0,0', 'chest_1'), { items: ['bandage'] });

  store.saveVehicle('veh_jeep', { x: 50, z: -20, fuel: 85 });
  assert.equal(store.getVehicle('veh_jeep').fuel, 85);

  const snap = store.snapshotNear(['0,0']);
  assert.equal(snap.chunks['0,0'].doors['door_house_1'], true);
  assert.equal(snap.vehicles['veh_jeep'].fuel, 85);
});

test('HostPersistence: handshake, new player, and token validation', async () => {
  const sent = [];
  const closed = [];
  const persist = new KP.HostPersistence({
    roomId: 'room1',
    worldSeed: 1234,
    hooks: {
      send: (connId, msg) => sent.push({ connId, msg }),
      close: (connId) => closed.push(connId)
    }
  });

  // 1. Novo jogador
  await persist.handleHello('conn_1', {
    t: KP.MSG.HELLO,
    playerId: 'p_hero',
    token: 'secret123',
    nick: 'Hero'
  });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].msg.t, KP.MSG.NEW_CHARACTER);
  assert.equal(sent[0].msg.playerId, 'p_hero');
  assert.equal(persist.playerIdOf('conn_1'), 'p_hero');

  // Spawn do personagem
  persist.onCharacterSpawned('p_hero');

  // 2. Reconectar com token errado deve ser negado
  sent.length = 0;
  await persist.handleHello('conn_2', {
    t: KP.MSG.HELLO,
    playerId: 'p_hero',
    token: 'wrong-token'
  });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].msg.t, KP.MSG.RESUME_DENIED);

  // 3. Reconectar com token correto retoma e derruba a conexão antiga
  sent.length = 0;
  await persist.handleHello('conn_3', {
    t: KP.MSG.HELLO,
    playerId: 'p_hero',
    token: 'secret123'
  });
  const kicked = sent.find(s => s.connId === 'conn_1');
  const resumed = sent.find(s => s.connId === 'conn_3');
  assert.ok(kicked, 'Conexão antiga deve ser derrubada com kicked_duplicate');
  assert.equal(kicked.msg.t, KP.MSG.KICKED_DUPLICATE);
  assert.ok(resumed, 'Conexão nova deve receber resume_ok');
  assert.equal(resumed.msg.t, KP.MSG.RESUME_OK);
  assert.equal(resumed.msg.instant, true);
});

test('HostPersistence: duplicate session kicks previous connection', async () => {
  const sent = [];
  const persist = new KP.HostPersistence({
    roomId: 'room1',
    hooks: {
      send: (connId, msg) => sent.push({ connId, msg }),
      close: () => {}
    }
  });

  await persist.handleHello('conn_tab1', { t: KP.MSG.HELLO, playerId: 'p1', token: 'tok1' });
  persist.onCharacterSpawned('p1');

  sent.length = 0;
  // Mesma conta conecta em outra aba
  await persist.handleHello('conn_tab2', { t: KP.MSG.HELLO, playerId: 'p1', token: 'tok1' });
  const kicked = sent.find(s => s.connId === 'conn_tab1');
  assert.ok(kicked, 'Aba 1 deve receber kicked_duplicate');
  assert.equal(kicked.msg.t, KP.MSG.KICKED_DUPLICATE);
});

test('HostPersistence: disconnect, 30s timer, offline removal, and died offline', async () => {
  let bodyRemoved = false;
  const sent = [];
  const persist = new KP.HostPersistence({
    roomId: 'room1',
    hooks: {
      send: (connId, msg) => sent.push({ connId, msg }),
      removeBody: () => { bodyRemoved = true; }
    }
  });

  await persist.handleHello('conn_a', { t: KP.MSG.HELLO, playerId: 'p_combater', token: 'tok99' });
  persist.onCharacterSpawned('p_combater');

  // Jogador desconecta
  persist.onConnectionLost('conn_a');
  assert.equal(persist.statusOf('p_combater'), 'disconnecting');
  assert.equal(bodyRemoved, false, 'Boneco continua no mundo durante os 30s');

  // Morte enquanto desconectando
  persist.onPlayerDied('p_combater', { by: 'zombie', at: { x: 5, y: 0, z: 5 } });

  // Ao reconectar, recebe new_character com diedWhileOffline = true
  sent.length = 0;
  await persist.handleHello('conn_b', { t: KP.MSG.HELLO, playerId: 'p_combater', token: 'tok99' });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].msg.t, KP.MSG.NEW_CHARACTER);
  assert.equal(sent[0].msg.diedWhileOffline, true);
});

test('HostPersistence: invalidateAll and closeServer', async () => {
  const sent = [];
  const persist = new KP.HostPersistence({
    roomId: 'room1',
    hooks: { send: (connId, msg) => sent.push({ connId, msg }) }
  });

  await persist.handleHello('conn_1', { t: KP.MSG.HELLO, playerId: 'p1', token: 't1' });
  persist.closeServer();
  assert.ok(sent.some(s => s.msg.t === KP.MSG.SERVER_CLOSED));

  persist.invalidateAll(9999);
  assert.equal(persist.stats().totalSaves, 0);
});

test('KP.createClientIdentity creates unique ID and builds hello', () => {
  const id1 = KP.createClientIdentity({ profile: 'test1' });
  const id2 = KP.createClientIdentity({ profile: 'test2' });
  assert.ok(id1.playerId);
  assert.ok(id1.token);
  assert.notEqual(id1.playerId, id2.playerId);

  const hello = id1.buildHello({ nick: 'Warrior' });
  assert.equal(hello.t, KP.MSG.HELLO);
  assert.equal(hello.playerId, id1.playerId);
  assert.equal(hello.token, id1.token);
  assert.equal(hello.nick, 'Warrior');
  assert.equal(hello.version, 1);
});

test('KP.createClientSession lifecycle: start, receive, sendReady, stop', () => {
  const sent = [];
  let resumed = null;
  let kicked = false;

  const session = KP.createClientSession({
    identity: { playerId: 'p_sess', token: 'tok_sess', buildHello: (o) => ({ t: 'hello', ...o }) },
    nick: 'TestPlayer',
    send: (msg) => sent.push(msg),
    handlers: {
      onResumeOk: (m) => { resumed = m; },
      onKicked: () => { kicked = true; }
    }
  });

  session.start();
  assert.equal(sent.length, 1);
  assert.equal(sent[0].t, 'hello');

  // Recebe mensagem do jogo não persistência -> receive devolve false
  assert.equal(session.receive({ t: 'chat', text: 'hi' }), false);

  // Recebe resume_ok -> receive devolve true e dispara callback
  assert.equal(session.receive({ t: KP.MSG.RESUME_OK, instant: true }), true);
  assert.ok(resumed);
  assert.equal(resumed.instant, true);

  // Envia resume_ready
  session.sendReady();
  assert.equal(sent[1].t, KP.MSG.RESUME_READY);

  // Recebe kicked_duplicate -> para a sessão
  assert.equal(session.receive({ t: KP.MSG.KICKED_DUPLICATE }), true);
  assert.equal(kicked, true);

  session.stop();
});

test('ItemLedger: remove and clear', () => {
  const ledger = new KP.ItemLedger();
  ledger.register('u1', 'player:p1');
  assert.equal(ledger.locationOf('u1'), 'player:p1');
  ledger.remove('u1');
  assert.equal(ledger.locationOf('u1'), null);

  ledger.register('u2', 'world:0,0');
  ledger.clear();
  assert.equal(ledger.locationOf('u2'), null);
  assert.deepEqual(ledger.itemsAt('world:0,0'), []);
});

test('WorldDiffStore: objects, bodies, timers, misc, clear', () => {
  const store = new KP.WorldDiffStore({ worldSeed: 101 });
  const cid = '2,2';

  store.placeObject(cid, { id: 'campfire_1', x: 5, z: 10 });
  const snap1 = store.snapshotNear([cid]);
  assert.equal(snap1.chunks[cid].objects.length, 1);
  store.removeObject(cid, 'campfire_1');
  assert.equal(store.snapshotNear([cid]).chunks[cid].objects.length, 0);

  store.addBody(cid, { id: 'corpse_9', loot: ['item1'] });
  assert.equal(store.snapshotNear([cid]).chunks[cid].bodies.length, 1);
  store.removeBody(cid, 'corpse_9');
  assert.equal(store.snapshotNear([cid]).chunks[cid].bodies.length, 0);

  const tNow = Date.now();
  store.setTimer('test_timer_due', tNow - 100, { action: 'despawn' });
  store.setTimer('test_timer_future', tNow + 10000, { action: 'future' });
  const due = store.takeDueTimers(tNow);
  assert.equal(due.length, 1);
  assert.equal(due[0].key, 'test_timer_due');

  store.setMisc('clock', { time: '14:30', weather: 'sunny' });
  assert.deepEqual(store.getMisc('clock'), { time: '14:30', weather: 'sunny' });

  store.clear();
  assert.equal(store.getMisc('clock'), null);
});

test('HostPersistence: markDirty, saveNow and hooks', async () => {
  let snapCalled = false;
  const persist = new KP.HostPersistence({
    roomId: 'room_hook',
    hooks: {
      send: () => {},
      snapshotPlayer: (pid) => {
        snapCalled = true;
        return { playerId: pid, stats: { hp: 85 } };
      }
    }
  });

  await persist.handleHello('c1', { t: KP.MSG.HELLO, playerId: 'p_snap', token: 'tok_snap' });
  persist.onCharacterSpawned('p_snap');

  persist.markDirty('p_snap');
  persist.saveNow('p_snap');
  assert.equal(snapCalled, true);
  assert.equal(persist.statusOf('p_snap'), 'online');
});
