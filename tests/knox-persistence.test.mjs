import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const KP = require('../knox-persistence.js');

const VALID_PID_1 = 'player_alpha_001';
const VALID_PID_2 = 'player_beta_0002';
const VALID_TOK_1 = '0123456789abcdef0123456789abcdef';
const VALID_TOK_2 = 'fedcba9876543210fedcba9876543210';

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
  assert.equal(KP.LOC.world('0,0'), 'w:0,0');
  assert.equal(KP.LOC.player('p1'), 'p:p1');
  assert.equal(KP.LOC.container('c1'), 'c:c1');
  assert.equal(KP.LOC.vehicle('v1'), 'v:v1');
  assert.equal(KP.LOC.corpse('dead1'), 'b:dead1');
});

test('KP.isPersistenceMessage detects valid messages and ignores others', () => {
  assert.equal(KP.isPersistenceMessage({ t: 'hello' }), true);
  assert.equal(KP.isPersistenceMessage({ t: 'resume_ok' }), true);
  assert.equal(KP.isPersistenceMessage({ t: 'server_closed' }), true);
  assert.equal(KP.isPersistenceMessage({ t: 'pos', x: 0 }), false);
  assert.equal(KP.isPersistenceMessage(null), false);
  assert.equal(KP.isPersistenceMessage('hello'), false);
});

test('KP.createEmptySave and sanitizeSave preserve appearance.characterId', () => {
  const empty = KP.createEmptySave({
    playerId: VALID_PID_1,
    nick: 'Survivor',
    appearance: { characterId: 'swat' }
  });
  assert.equal(empty.v, 1);
  assert.equal(empty.playerId, VALID_PID_1);
  assert.equal(empty.nick, 'Survivor');
  assert.equal(empty.alive, true);
  assert.equal(empty.stats.hp, 100);
  assert.equal(empty.appearance.characterId, 'swat');

  const { save, issues } = KP.sanitizeSave({
    v: 1,
    playerId: VALID_PID_2,
    pos: { x: 10, y: 2, z: -5 },
    stats: { hp: -5, food: 40 },
    stance: 'INVALID STANCE!',
    appearance: { characterId: 'adventurer' }
  });
  assert.ok(save);
  assert.equal(save.stats.hp, 0);
  assert.equal(save.stats.food, 40);
  assert.equal(save.stance, 'stand');
  assert.equal(save.appearance.characterId, 'adventurer');
  assert.equal(issues.length, 0);

  const invalid = KP.sanitizeSave(null);
  assert.equal(invalid.save, null);
  assert.ok(invalid.issues.includes('not_object'));
});

test('KP.sha256Hex returns stable SHA-256 hash', async () => {
  const h1 = await KP.sha256Hex('my-secret-token');
  const h2 = await KP.sha256Hex('my-secret-token');
  const h3 = await KP.sha256Hex('different-token');
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

  ledger.register(uid, worldLoc);
  assert.equal(ledger.locationOf(uid), worldLoc);
  assert.deepEqual(ledger.itemsAt(worldLoc), [uid]);

  const r1 = ledger.move(uid, worldLoc, playerLoc);
  assert.equal(r1.ok, true);
  assert.equal(ledger.locationOf(uid), playerLoc);
  assert.deepEqual(ledger.itemsAt(worldLoc), []);
  assert.deepEqual(ledger.itemsAt(playerLoc), [uid]);

  const rDup = ledger.move(uid, worldLoc, player2Loc);
  assert.equal(rDup.ok, false);
  assert.equal(rDup.reason, 'wrong_source');
  assert.equal(rDup.at, playerLoc);
  assert.equal(ledger.locationOf(uid), playerLoc);

  const r2 = ledger.move(uid, playerLoc, player2Loc);
  assert.equal(r2.ok, true);
  assert.equal(ledger.locationOf(uid), player2Loc);
});

test('WorldDiffStore: loot diffs, doors, containers, vehicles and snapshotNear', () => {
  const store = new KP.WorldDiffStore({ worldSeed: 4242 });
  const cid = '1,2';
  const item1 = { uid: '4242:1,2:0', type: 'knife' };
  const item2 = { uid: '4242:1,2:1', type: 'canteen' };

  assert.equal(store.applyLoot(cid, [item1, item2]).length, 2);

  store.itemTaken(cid, item1.uid);
  const afterTake = store.applyLoot(cid, [item1, item2]);
  assert.equal(afterTake.length, 1);
  assert.equal(afterTake[0].uid, item2.uid);

  const droppedGun = { uid: 'player_drop_99', type: 'ak47', x: 10, y: 0, z: 12 };
  store.itemDropped(cid, droppedGun);
  const reloaded = store.applyLoot(cid, [item1, item2]);
  assert.equal(reloaded.length, 2);

  store.setDoor(cid, 'door_house_1', true);
  assert.equal(store.getDoor(cid, 'door_house_1'), true);
  store.setContainer(cid, 'chest_1', { items: ['bandage'] });
  assert.deepEqual(store.getContainer(cid, 'chest_1'), { items: ['bandage'] });
  store.saveVehicle('veh_jeep', { x: 50, z: -20, fuel: 85 });
  assert.equal(store.getVehicle('veh_jeep').fuel, 85);

  const snap = store.snapshotNear([cid]);
  assert.ok(snap.chunks[cid]);
  assert.deepEqual(snap.chunks[cid].doors, [['door_house_1', true]]);
  assert.equal(snap.vehicles[0][0], 'veh_jeep');
});

test('HostPersistence: handshake, token validation, duplicate kick, linger and died offline', async () => {
  const sent = [];
  let bodyRemoved = false;
  const persist = new KP.HostPersistence({
    roomId: 'room1',
    worldSeed: '1234',
    rules: { closeDelayMs: 0 },
    hooks: {
      send: (connId, msg) => sent.push({ connId, msg }),
      close: () => {},
      removeBody: () => { bodyRemoved = true; },
      snapshotPlayer: (pid) => KP.createEmptySave({
        playerId: pid,
        worldSeed: '1234',
        pos: { x: 12, y: 1, z: -8 },
        appearance: { characterId: 'swat' }
      })
    }
  });

  await persist.handleHello('conn_1', {
    t: KP.MSG.HELLO,
    playerId: VALID_PID_1,
    token: VALID_TOK_1,
    nick: 'Hero',
    version: 1
  });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].msg.t, KP.MSG.NEW_CHARACTER);

  persist.onCharacterSpawned(VALID_PID_1);

  // Wrong token denied
  sent.length = 0;
  await persist.handleHello('conn_2', {
    t: KP.MSG.HELLO,
    playerId: VALID_PID_1,
    token: VALID_TOK_2,
    version: 1
  });
  assert.equal(sent[0].msg.t, KP.MSG.RESUME_DENIED);

  // Duplicate tab kicks conn_1 and resumes conn_3 instantly with appearance preserved
  sent.length = 0;
  await persist.handleHello('conn_3', {
    t: KP.MSG.HELLO,
    playerId: VALID_PID_1,
    token: VALID_TOK_1,
    version: 1
  });
  assert.ok(sent.some(s => s.connId === 'conn_1' && s.msg.t === KP.MSG.KICKED_DUPLICATE));
  const resumed = sent.find(s => s.connId === 'conn_3' && s.msg.t === KP.MSG.RESUME_OK);
  assert.ok(resumed);
  assert.equal(resumed.msg.instant, true);
  assert.equal(resumed.msg.save.appearance.characterId, 'swat');

  // Connection lost -> lingering -> died offline
  persist.onConnectionLost('conn_3');
  assert.equal(persist.players.get(VALID_PID_1).status, 'lingering');
  assert.equal(bodyRemoved, false);

  persist.onPlayerDied(VALID_PID_1, { by: 'zombie' });
  sent.length = 0;
  await persist.handleHello('conn_4', {
    t: KP.MSG.HELLO,
    playerId: VALID_PID_1,
    token: VALID_TOK_1,
    version: 1
  });
  assert.equal(sent[0].msg.t, KP.MSG.NEW_CHARACTER);
  assert.equal(sent[0].msg.diedWhileOffline, true);

  persist.closeServer();
  persist.invalidateAll('9999');
  assert.equal(persist.stats().players, 1); // conn_4 connected gets world_reset
});

test('KP.createClientIdentity and createClientSession', () => {
  const id1 = KP.createClientIdentity({ profile: 'test1', storage: null });
  const id2 = KP.createClientIdentity({ profile: 'test2', storage: null });
  assert.ok(id1.playerId);
  assert.ok(id1.token);
  assert.notEqual(id1.playerId, id2.playerId);

  const sent = [];
  let resumed = null;
  const session = KP.createClientSession({
    identity: id1,
    nick: 'Tester',
    autoHeartbeat: false,
    send: (m) => sent.push(m),
    handlers: { onResumeOk: (m) => { resumed = m; } }
  });
  session.start();
  assert.equal(sent[0].t, KP.MSG.HELLO);
  assert.equal(session.receive({ t: 'chat' }), false);
  assert.equal(session.receive({ t: KP.MSG.RESUME_OK, instant: true }), true);
  assert.ok(resumed);
  session.sendReady();
  assert.equal(sent[1].t, KP.MSG.RESUME_READY);
  session.stop();
});
