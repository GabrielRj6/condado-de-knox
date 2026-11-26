import test from 'node:test';
import assert from 'node:assert/strict';
import {
  shouldShowPlayerOnMap,
  getVehicleSeatsList,
  getVehicleSeatMeta,
  getVehiclePhysicsSpec,
  sweptVehicleContact,
  stepVehicleLongitudinalSpeed,
  computeVehicleGroundAlignment,
  computeVehicleColliderBounds,
  selectNightStreetLamps,
  buildRoadGraph,
  computeRoadRoute,
  computeSpatialAudioParams,
  computeVehicleEngineProfile,
  mergeAndPrioritizeRoads,
  synthesizeCondoAccessRoads,
  generateWorldMacroMap,
  sampleMacroTerrain,
  generateChunkBlueprint,
  validateSpawnPoint,
  isWithinAOI,
  FILL_RULES,
  POI_MERGE,
  PVP_CONFIG,
  VEHICLE_SHOOTING,
  mergeNearbyMedicalPois,
  synthesizeStreetOnlyBuildings,
  clampVehicleAimAngles,
  stepSpringRecoil,
  selectContextualDeathStyle,
  computeBallisticDrop
} from '../public/js/tactical-logic.js';

test('team-only map visibility hides players without team or on different teams', () => {
  assert.equal(shouldShowPlayerOnMap('team-alpha', 'team-alpha'), true);
  assert.equal(shouldShowPlayerOnMap('team-alpha', 'team-bravo'), false);
  assert.equal(shouldShowPlayerOnMap(null, 'team-alpha'), false);
  assert.equal(shouldShowPlayerOnMap('team-alpha', null), false);
  assert.equal(shouldShowPlayerOnMap(null, null), false);
  assert.equal(shouldShowPlayerOnMap('', ''), false);
});

test('vehicle specs and seat metadata distinguish cars (4 seats) from motorcycles (Piloto + Garupa)', () => {
  const carSpec = getVehiclePhysicsSpec(false);
  const motoSpec = getVehiclePhysicsSpec(true);

  assert.equal(carSpec.maxSeats, 4);
  assert.equal(motoSpec.maxSeats, 2);
  assert.ok(motoSpec.width < carSpec.width);
  assert.ok(motoSpec.capRadius < carSpec.capRadius);
  assert.ok(motoSpec.maxReverse > 0 && carSpec.maxReverse > 0, 'maxReverse must be positive magnitude');
  assert.ok(motoSpec.stepClearance < carSpec.stepClearance);

  assert.equal(getVehicleSeatsList(true).length, 2);
  const pilotSeat = getVehicleSeatMeta(true, 0);
  const garupaSeat = getVehicleSeatMeta(true, 1);
  assert.equal(pilotSeat.label, 'PILOTO');
  assert.equal(garupaSeat.label, 'GARUPA');
  assert.ok(pilotSeat.z > 0, 'Pilot must sit behind fuel tank');
  assert.ok(garupaSeat.z > pilotSeat.z + 0.35, 'Garupa must sit clearly behind Pilot');
  assert.ok(garupaSeat.y > pilotSeat.y, 'Garupa saddle sits higher than Pilot saddle');
  assert.equal(getVehicleSeatMeta(false, 0).label, 'MOTORISTA');

  // Rotated AABB swaps width and length at 90 degrees
  const bounds0 = computeVehicleColliderBounds(10, 20, 0, motoSpec.width, motoSpec.length, 0, motoSpec.height);
  const bounds90 = computeVehicleColliderBounds(10, 20, Math.PI / 2, motoSpec.width, motoSpec.length, 0, motoSpec.height);
  assert.ok(Math.abs((bounds0.maxX - bounds0.minX) - motoSpec.width) < 1e-6);
  assert.ok(Math.abs((bounds90.maxX - bounds90.minX) - motoSpec.length) < 1e-6);
});

test('motorcycle and car stay at 0 km/h when idle, brake cleanly to 0, and reverse smoothly', () => {
  const moto = getVehiclePhysicsSpec(true);
  // Idle mounted moto must stay at exact 0 (never creep to 15 km/h!)
  let v = 0;
  for (let i = 0; i < 30; i++) {
    v = stepVehicleLongitudinalSpeed(v, 0, false, 1 / 60, 22.5, 33.5, moto.maxReverse, true);
  }
  assert.equal(v, 0);

  // Accelerate then brake to complete stop with S
  v = 18;
  for (let i = 0; i < 60; i++) {
    v = stepVehicleLongitudinalSpeed(v, -1, false, 1 / 60, 22.5, 33.5, moto.maxReverse, true);
    if (v === 0) break;
  }
  assert.equal(v, 0, 'Braking with S must cleanly reach exact 0 m/s');

  // Handbrake from moving speed stops cleanly at exact 0
  v = 12;
  for (let i = 0; i < 180; i++) {
    v = stepVehicleLongitudinalSpeed(v, 0, true, 1 / 60, 22.5, 33.5, moto.maxReverse, true);
  }
  assert.equal(v, 0, 'Handbrake must reach exact 0 m/s');

  // Holding S while stopped reverses gently up to -maxReverse
  v = 0;
  for (let i = 0; i < 120; i++) {
    v = stepVehicleLongitudinalSpeed(v, -1, false, 1 / 60, 22.5, 33.5, moto.maxReverse, true);
  }
  assert.ok(v < 0 && v >= -moto.maxReverse, `Expected smooth reverse in [-${moto.maxReverse}, 0), got ${v}`);
});

test('motorcycle ground alignment keeps tires flush on flat and sloped surfaces without floating', () => {
  const flat = computeVehicleGroundAlignment(true, 1.2, 1.2, 1.2, 1.2, 1.2, 0.78, 0.24);
  assert.equal(flat.targetY, 1.2);
  assert.equal(flat.pitchSlope, 0);
  assert.equal(flat.rollSlope, 0);

  // Uphill slope: front wheel at 2.0m, rear wheel at 1.6m -> midpoint 1.8m, positive pitch, zero roll
  const uphill = computeVehicleGroundAlignment(true, 1.8, 2.0, 2.0, 1.6, 1.6, 0.78, 0.24);
  assert.ok(Math.abs(uphill.targetY - 1.8) < 1e-6);
  assert.ok(uphill.pitchSlope > 0.2);
  assert.equal(uphill.rollSlope, 0);
});

test('night streetlight selector caps point lights and forward cones for zero overdraw', () => {
  const lamps = [];
  for (let i = 0; i < 80; i++) {
    lamps.push({ lx: (i - 40) * 5, ly: 6, lz: -25 });
  }
  const { lightLamps, coneLamps } = selectNightStreetLamps(lamps, 0, 0, 0, -1, {
    maxLights: 4,
    maxCones: 20,
    lightRange: 64,
    coneRange: 92,
    coneMinCos: 0.2
  });

  assert.equal(lightLamps.length, 4);
  assert.ok(coneLamps.length <= 20 && coneLamps.length > 0);
  // Nearest lamp to (0, 0) along z=-25 is at lx=0 (d2 = 625)
  assert.equal(lightLamps[0].lm.lx, 0);

  // Behind camera (> nearAlwaysDist) lamps are excluded from cones
  const behindOnly = [{ lx: 0, ly: 6, lz: 50 }];
  const resBehind = selectNightStreetLamps(behindOnly, 0, 0, 0, -1);
  assert.equal(resBehind.coneLamps.length, 0);
});

test('road graph and A* router compute shortest connected road path with distance and ETA', () => {
  const roads = [
    { name: 'Av Principal', roadClass: 'avenue', pts: [[0, 0], [50, 0], [100, 0]] },
    { name: 'Rua Transversal', roadClass: 'street', pts: [[100, 0], [100, 50], [100, 100]] },
    { name: 'Rua Longa', roadClass: 'passage', pts: [[0, 0], [0, 120], [100, 120], [100, 100]] }
  ];
  const graph = buildRoadGraph(roads);
  const route = computeRoadRoute(graph, 2, 1, 98, 99, 20);

  assert.equal(route.viaRoads, true);
  assert.ok(route.points.length >= 4);
  assert.ok(route.totalMeters >= 190 && route.totalMeters <= 215, `Expected ~200m route, got ${route.totalMeters}`);
  assert.ok(route.etaSeconds >= 8 && route.etaSeconds <= 12);
});

test('road router falls back cleanly when road graph is empty or destination is far off-road', () => {
  const emptyGraph = buildRoadGraph([]);
  const route = computeRoadRoute(emptyGraph, 0, 0, 100, 0, 20);
  assert.equal(route.viaRoads, false);
  assert.equal(route.totalMeters, 100);
  assert.equal(route.points.length, 2);
});

test('3D spatial acoustics resolve left/right/front/back and preserve direction at long distances', () => {
  const listenerPos = { x: 0, y: 1.6, z: 0 };
  const listenerFwd = { x: 0, y: 0, z: -1 };  // Looking North (-Z)
  const listenerRight = { x: 1, y: 0, z: 0 }; // Right is East (+X)

  const leftShot = computeSpatialAudioParams(listenerPos, listenerFwd, listenerRight, { x: -30, y: 1.6, z: 0 }, { maxDist: 440 });
  const rightShot = computeSpatialAudioParams(listenerPos, listenerFwd, listenerRight, { x: 30, y: 1.6, z: 0 }, { maxDist: 440 });
  const frontShot = computeSpatialAudioParams(listenerPos, listenerFwd, listenerRight, { x: 0, y: 1.6, z: -30 }, { maxDist: 440 });
  const backShot = computeSpatialAudioParams(listenerPos, listenerFwd, listenerRight, { x: 0, y: 1.6, z: 30 }, { maxDist: 440 });

  assert.equal(leftShot.direction, 'left');
  assert.ok(leftShot.pan < -0.95);
  assert.equal(rightShot.direction, 'right');
  assert.ok(rightShot.pan > 0.95);
  assert.equal(frontShot.direction, 'front');
  assert.ok(frontShot.frontDot > 0.95);
  assert.equal(backShot.direction, 'back');
  assert.ok(backShot.frontDot < -0.95);

  // Perceptual front-vs-back pinna darkening makes rear shots noticeably darker in timbre
  assert.ok(backShot.lowpassHz < frontShot.lowpassHz * 0.65, 'Rear gunshot must have lower pinna lowpass cutoff than front gunshot');

  // Far gunshot (260m to the right) is quieter than close gunshot, still audible, darker, and still panned right
  const farRightShot = computeSpatialAudioParams(listenerPos, listenerFwd, listenerRight, { x: 260, y: 1.6, z: 0 }, { maxDist: 440, useSpeedOfSound: true });
  assert.equal(farRightShot.audible, true);
  assert.equal(farRightShot.direction, 'right');
  assert.ok(farRightShot.pan > 0.95);
  assert.ok(farRightShot.gain > 0.02 && farRightShot.gain < rightShot.gain * 0.45);
  assert.ok(farRightShot.lowpassHz < rightShot.lowpassHz);
  assert.ok(farRightShot.delaySec > 0.5);
});

test('vehicle engine profiles distinguish car, trail moto, and street moto and silence when idle unoccupied', () => {
  const parkedCar = computeVehicleEngineProfile(false, null, 0, 0, false, 28);
  assert.equal(parkedCar.active, false);
  assert.equal(parkedCar.gain, 0);

  const carIdle = computeVehicleEngineProfile(false, null, 0, 0, true, 28);
  const carFast = computeVehicleEngineProfile(false, null, 24, 1, true, 28);
  const motoTrail = computeVehicleEngineProfile(true, 'trail', 18, 1, true, 33.5);
  const motoStreet = computeVehicleEngineProfile(true, 'street', 22, 1, true, 36);

  assert.equal(carIdle.active, true);
  assert.ok(carFast.baseFreq > carIdle.baseFreq);
  assert.ok(carFast.gear > carIdle.gear);
  assert.ok(motoStreet.baseFreq > motoTrail.baseFreq, 'Street 600 must rev higher than Trail 450');
  assert.ok(motoTrail.baseFreq > carIdle.baseFreq, 'Trail 450 revs higher than idle car');
});

test('condo road synthesizer connects unmapped house clusters to external roads without leaving orphan blocks', () => {
  // Simulates an external avenue at x = 0 and a gated community of 16 houses sitting 60..140m away with ZERO internal OSM roads
  const extRoads = [
    { name: 'Av. Turmalina', roadClass: 'avenue', width: 12.4, oneway: 0, pts: [[0, -150], [0, 150]] }
  ];
  const condoHouses = [];
  for (let row = 0; row < 4; row++) {
    for (let col = 0; col < 4; col++) {
      condoHouses.push({ x: 65 + col * 24, z: -45 + row * 28, prefab: 'house' });
    }
  }
  const merged = mergeAndPrioritizeRoads(extRoads, 950);
  const res = synthesizeCondoAccessRoads(merged, condoHouses, { halfM: 500 });

  assert.equal(res.clusterCount, 1);
  assert.equal(res.orphanCount, 16);
  assert.ok(res.addedRoads.length >= 3, `Expected internal lanes + connector, got ${res.addedRoads.length}`);
  assert.ok(res.roads.length > extRoads.length);
  // Every synthesized road has valid coordinates inside bounds and at least 2 points
  for (const r of res.addedRoads) {
    assert.ok(r.pts.length >= 2);
    assert.equal(r.synthesized, true);
  }
  // Road graph built with synthesized roads should route from the external avenue right into the condo!
  const graph = buildRoadGraph(res.roads);
  const route = computeRoadRoute(graph, 2, 0, 130, 35, 18);
  assert.equal(route.viaRoads, true, 'GPS A* router must reach inside the synthesized condo streets');
});

test('Fase 2 deterministic macro-map and chunk blueprints generate identical worlds across calls for same seed', () => {
  const m1 = generateWorldMacroMap(4242, 'medium', 64);
  const m2 = generateWorldMacroMap(4242, 'medium', 64);
  const mDiff = generateWorldMacroMap(9999, 'medium', 64);

  assert.deepEqual(m1.cities, m2.cities);
  assert.deepEqual(m1.highways, m2.highways);
  assert.deepEqual(m1.lakes, m2.lakes);
  assert.notDeepEqual(m1.cities, mDiff.cities);
  assert.equal(m1.sizeMeters, 8192);
  assert.equal(m1.cities.length, 9);

  // Two players in the same chunk get bit-for-bit identical chunk blueprints
  const cA = generateChunkBlueprint(m1, 2, -3);
  const cB = generateChunkBlueprint(m2, 2, -3);
  assert.deepEqual(cA, cB);

  // Spawn validation avoids water and respects enemy minimum distance
  const lake = m1.lakes[0];
  if (lake) {
    const fixed = validateSpawnPoint(m1, lake.x, lake.z);
    assert.equal(fixed.adjusted, true);
    assert.equal(sampleMacroTerrain(m1, fixed.x, fixed.z).isWater, false);
  }
  const city0 = m1.cities[0];
  const spEnemy = validateSpawnPoint(m1, city0.x, city0.z, {
    enemySpawns: [{ x: city0.x, z: city0.z }],
    minEnemyDist: 120
  });
  assert.ok(Math.hypot(spEnemy.x - city0.x, spEnemy.z - city0.z) >= 119);

  // AOI check
  assert.equal(isWithinAOI(0, 0, 3, -3, 4), true);
  assert.equal(isWithinAOI(0, 0, 10, 0, 4), false);
});

test('Atualização 2: deterministic medical POI merging fuses >=3 nearby hospitals/pharmacies and preserves isolated units', () => {
  const pois = [
    { x: 10, z: 10, prefab: 'hospital', name: 'Hospital A', floors: 2 },
    { x: 40, z: 20, prefab: 'hospital', name: 'Hospital Central', floors: 3 },
    { x: 65, z: 25, prefab: 'hospital', name: 'UPA Leste', floors: 1 },
    // Distant pair of hospitals (< minCount 3) must stay untouched
    { x: 500, z: 500, prefab: 'hospital', name: 'Posto Médico Sul', floors: 1 },
    { x: 540, z: 510, prefab: 'hospital', name: 'Clínica Sul', floors: 1 },
    // Cluster of 3 pharmacies within 120m
    { x: -100, z: -100, prefab: 'pharmacy', name: 'Farmácia 1' },
    { x: -130, z: -115, prefab: 'pharmacy', name: 'Drogaria Central' },
    { x: -115, z: -140, prefab: 'pharmacy', name: 'Farmácia 3' },
    // Non-medical building stays untouched
    { x: 25, z: 15, prefab: 'house', name: '' }
  ];

  const resA = mergeNearbyMedicalPois(pois);
  const resB = mergeNearbyMedicalPois([...pois].reverse());

  assert.equal(resA.mergedGroups, 2);
  assert.equal(resA.absorbedCount, 4);
  // 9 initial - 4 absorbed = 5 remaining (1 merged hospital + 2 distant hospitals + 1 merged pharmacy + 1 house)
  assert.equal(resA.buildings.length, 5);
  const mergedHosp = resA.buildings.find((b) => b.prefab === 'hospital' && b.mergedCount === 3);
  const mergedPharm = resA.buildings.find((b) => b.prefab === 'pharmacy' && b.mergedCount === 3);
  assert.ok(mergedHosp && mergedHosp.poiScale > 1 && mergedHosp.poiScale <= POI_MERGE.hospital.maxScale);
  assert.ok(mergedPharm && mergedPharm.poiScale > 1 && mergedPharm.poiScale <= POI_MERGE.pharmacy.maxScale);
  // Deterministic across input orderings
  const mergedHospB = resB.buildings.find((b) => b.prefab === 'hospital' && b.mergedCount === 3);
  assert.equal(mergedHosp.x, mergedHospB.x);
  assert.equal(mergedHosp.z, mergedHospB.z);
});

test('Atualização 2: street-only OSM infill fills empty road cells deterministically and leaves OSM-mapped cells untouched', () => {
  const roads = [
    // Cell (0, 0): 90m street with ZERO OSM buildings -> should be filled
    { name: 'Rua Vazia', roadClass: 'residential', width: 8, pts: [[5, 50], [95, 50]] },
    // Cell (2, 0): 90m street WITH an existing OSM house -> must stay untouched
    { name: 'Rua Mapeada', roadClass: 'residential', width: 8, pts: [[205, 50], [295, 50]] },
    // Cell (-2, 0): highway -> must be ignored
    { name: 'BR-163', roadClass: 'highway', width: 12, pts: [[-195, 50], [-105, 50]] }
  ];
  const osmBuildings = [
    { x: 250, z: 32, r: 7, prefab: 'house' }
  ];

  const r1 = synthesizeStreetOnlyBuildings(roads, osmBuildings, { halfM: 500, worldSeed: 4242 });
  const r2 = synthesizeStreetOnlyBuildings(roads, osmBuildings, { halfM: 500, worldSeed: 4242 });

  assert.equal(FILL_RULES.keepOsmBuildingsUntouched, true);
  assert.equal(r1.filledCells, 1);
  assert.equal(r1.skippedOsmCells, 1);
  assert.ok(r1.generated.length >= 2, 'Empty street cell must receive generated buildings');
  // Every generated building must be in cell (0,0) and outside cell (2,0) & highway cell (-2,0)
  for (const gb of r1.generated) {
    assert.equal(gb.generated, true);
    assert.ok(gb.x >= 0 && gb.x < 100, `Unexpected building x=${gb.x}`);
  }
  assert.deepEqual(r1.generated, r2.generated);
});

test('Atualização 2 & 3: DayZ PvP config, vehicle passenger aim clamping, spring recoil recovery, death styles, and ballistic drop', () => {
  // DayZ hardcore PvP invariant
  assert.equal(PVP_CONFIG.hitFeedbackOnPlayers, false);
  assert.equal(PVP_CONFIG.hitFeedbackOnZombies, true);
  assert.equal(PVP_CONFIG.showRemoteBloodOnHit, false);

  // Vehicle shooting rules: driver cannot shoot, passenger/pillion can, pitch/yaw clamped
  const motoDriver = clampVehicleAimAngles(true, 0, 0, 0, 0);
  assert.equal(motoDriver.canShoot, false);
  const motoPillion = clampVehicleAimAngles(true, 1, 0, 0, 1.4); // excessive upward pitch
  assert.equal(motoPillion.canShoot, true);
  assert.equal(motoPillion.clamped, true);
  assert.ok(motoPillion.pitch <= (VEHICLE_SHOOTING.motorcycle.passengerArc.pitchUp * Math.PI) / 180 + 1e-6);

  const carDriver = clampVehicleAimAngles(false, 0, 0, 0, 0);
  assert.equal(carDriver.canShoot, false);
  const carPass = clampVehicleAimAngles(false, 1, 0, Math.PI, -1.2);
  assert.equal(carPass.canShoot, true);
  assert.equal(carPass.clamped, true);
  assert.ok(carPass.pitch >= -(VEHICLE_SHOOTING.car.passengerArc.pitchDown * Math.PI) / 180 - 1e-6);

  // Spring recoil cleanly recovers back to 0 without permanent drift
  const recoil = { pitch: 0.14, yaw: -0.05, kick: 0.08, posZ: 0.05, roll: 0.03, recovery: 12, yawRecovery: 13 };
  for (let i = 0; i < 90; i++) stepSpringRecoil(recoil, 1 / 60);
  assert.equal(recoil.pitch, 0);
  assert.equal(recoil.yaw, 0);
  assert.equal(recoil.kick, 0);

  // Contextual death styles span 0..5 cleanly
  assert.equal(selectContextualDeathStyle('torso', { isShotgun: true, seed: 5 }), 4);
  assert.equal(selectContextualDeathStyle('limb', { seed: 7 }), 5);
  assert.equal(selectContextualDeathStyle('torso', { impactSideDot: 0.8, seed: 3 }), 2);
  assert.equal(selectContextualDeathStyle('torso', { impactSideDot: -0.8, seed: 3 }), 3);
  const headStyle = selectContextualDeathStyle('head', { seed: 10 });
  assert.ok(headStyle === 0 || headStyle === 1);

  // Ballistic drop: zero at zeroing distance, negative beyond zeroing, larger drop for slower velocity
  assert.ok(Math.abs(computeBallisticDrop(200, 200, 880)) < 1e-9);
  const drop400 = computeBallisticDrop(400, 100, 880);
  const drop400Slow = computeBallisticDrop(400, 100, 450);
  assert.ok(drop400 < -0.5, `Expected clear bullet drop at 400m zeroed to 100m, got ${drop400}`);
  assert.ok(drop400Slow < drop400, 'Slower bullet must drop more at 400m');
});



test('vehicle sweep catches a zombie crossed between frames and respects vehicle width', () => {
  const moto = getVehiclePhysicsSpec(true);
  const car = getVehiclePhysicsSpec(false);
  const hits = (spec, x, z) => sweptVehicleContact(0, 0, 0, -7, { x, z }, 0, -1, spec, 0.32);
  assert.equal(hits(moto, 0, -3), true);
  assert.equal(hits(moto, 0.90, -3), true);
  assert.equal(hits(moto, 1.2, -3), false);
  assert.equal(hits(car, 1.2, -3), true);
  assert.equal(hits(moto, 0, -12), false);
  assert.equal(sweptVehicleContact(0, 0, 0, 7, { x: 0, z: 3 }, 0, -1, moto, 0.32), true);
});
