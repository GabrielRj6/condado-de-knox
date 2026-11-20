import test from 'node:test';
import assert from 'node:assert/strict';
import {
  shouldShowPlayerOnMap,
  getVehicleSeatsList,
  getVehicleSeatMeta,
  getVehiclePhysicsSpec,
  stepVehicleLongitudinalSpeed,
  computeVehicleGroundAlignment,
  computeVehicleColliderBounds,
  selectNightStreetLamps,
  buildRoadGraph,
  computeRoadRoute,
  computeSpatialAudioParams,
  computeVehicleEngineProfile
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
