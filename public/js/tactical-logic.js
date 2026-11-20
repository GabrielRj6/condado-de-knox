/**
 * Lógica pura compartilhada:
 * - Visibilidade estrita por equipe no mapa/minimapa
 * - Grafo viário e roteamento GPS (A*) para veículos
 * - Seleção otimizada de postes noturnos (zero recompilação WebGL, zero overdraw)
 * - Especificações de física, hitbox e assentos de Carros e Motos (Piloto + Garupa)
 */

export const VEHICLE_CAR_SEAT_OFFSETS = [
  { x: -0.45, y: 0.0, z: -0.22, side: -1, label: 'MOTORISTA' },
  { x:  0.45, y: 0.0, z: -0.22, side:  1, label: 'PASSAGEIRO (FRENTE)' },
  { x: -0.45, y: 0.0, z:  0.60, side: -1, label: 'PASSAGEIRO (TRÁS ESQ)' },
  { x:  0.45, y: 0.0, z:  0.60, side:  1, label: 'PASSAGEIRO (TRÁS DIR)' }
];

export const VEHICLE_MOTO_SEAT_OFFSETS = [
  { x: 0.0, y: 0.28, z: 0.10, side: -1, label: 'PILOTO' },
  { x: 0.0, y: 0.37, z: 0.58, side:  1, label: 'GARUPA' }
];

/**
 * Regra global: um jogador remoto só aparece no mapa/minimapa se estiver no MESMO time.
 */
export function shouldShowPlayerOnMap(localTeamId, remoteTeamId) {
  if (!localTeamId || !remoteTeamId) return false;
  return String(localTeamId).trim().length > 0 && String(localTeamId) === String(remoteTeamId);
}

export function getVehicleSeatsList(isMoto) {
  return isMoto ? VEHICLE_MOTO_SEAT_OFFSETS : VEHICLE_CAR_SEAT_OFFSETS;
}

export function getVehicleSeatMeta(isMoto, seatIdx) {
  const list = getVehicleSeatsList(isMoto);
  const idx = Math.max(0, Math.min(list.length - 1, seatIdx | 0));
  return list[idx];
}

export function getVehiclePhysicsSpec(isMoto) {
  if (isMoto) {
    return {
      isMoto: true,
      maxSeats: 2,
      width: 0.86,
      length: 2.24,
      height: 1.18,
      wheelBase: 0.78,
      trackHalf: 0.24,
      wheelRadius: 0.34,
      capOffsets: [0.68, -0.68],
      capRadius: 0.44,
      stepClearance: 0.28,
      hitLenFront: 1.48,
      hitLenBack: 0.95,
      hitHalfW: 0.64,
      exitOffset: 1.35,
      baseTurnRate: 2.75,
      driftTurnRate: 3.65,
      normalGrip: 9.2,
      driftGrip: 2.35,
      maxReverse: 4.2
    };
  }
  return {
    isMoto: false,
    maxSeats: 4,
    width: 2.02,
    length: 4.65,
    height: 1.52,
    wheelBase: 1.42,
    trackHalf: 0.95,
    wheelRadius: 0.35,
    capOffsets: [1.36, -1.36],
    capRadius: 0.94,
    stepClearance: 0.48,
    hitLenFront: 2.65,
    hitLenBack: 1.30,
    hitHalfW: 1.15,
    exitOffset: 2.15,
    baseTurnRate: 2.25,
    driftTurnRate: 3.55,
    normalGrip: 7.8,
    driftGrip: 1.55,
    maxReverse: 10.5
  };
}

/**
 * Integra velocidade longitudinal de Carro ou Moto garantindo frenagem completa até 0 km/h
 * e marcha ré suave com limite negativo seguro (-Math.abs(maxReverse)).
 */
export function stepVehicleLongitudinalSpeed(fwdVel, thr, handbrake, dt, accel, maxSpeed, maxReverse, isMoto) {
  const revLim = Math.abs(maxReverse || (isMoto ? 4.2 : 10.5));
  let v = fwdVel;

  if (thr > 0) {
    if (v < -0.15) {
      // Saindo da ré: freia primeiro até parar antes de acelerar à frente
      v = Math.min(0, v + accel * 2.1 * dt);
    } else {
      v += accel * (handbrake ? 0.35 : 1.0) * dt;
    }
  } else if (thr < 0) {
    if (v > 0.15) {
      // Frenagem forte e progressiva até 0 km/h real (sem pular direto pra ré no mesmo frame!)
      const brakeRate = accel * (isMoto ? 2.25 : 1.80);
      v = Math.max(0, v - brakeRate * dt);
    } else {
      // Empurra devagar em ré quando já parado
      v -= accel * (isMoto ? 0.42 : 0.72) * dt;
    }
  } else {
    // Desaceleração natural (freio-motor / atrito de rolagem)
    const coastDrag = handbrake ? 4.8 : (isMoto ? 1.15 : 1.05);
    v *= Math.exp(-dt * coastDrag);
    if (Math.abs(v) < 0.12) v = 0;
  }

  if (handbrake) {
    const hbDrag = Math.abs(v) > 5.5 ? (isMoto ? 2.35 : 1.55) : 7.5;
    v *= Math.exp(-dt * hbDrag);
    if (Math.abs(v) < 0.25 && thr <= 0) v = 0;
  }

  return Math.max(-revLim, Math.min(maxSpeed, v));
}

/**
 * Calcula altura e inclinação exatas dos pneus na superfície (contato 2 rodas na moto, 4 no carro)
 * sem folga flutuante nem inclinação falsa de meio-fio lateral na moto.
 */
export function computeVehicleGroundAlignment(isMoto, hCenter, hFL, hFR, hRL, hRR, wheelBase = 0.78, trackHalf = 0.24) {
  const wb2 = Math.max(0.4, wheelBase * 2);
  if (isMoto) {
    const hFront = (hFL + hFR) * 0.5;
    const hRear = (hRL + hRR) * 0.5;
    const lineMid = (hFront + hRear) * 0.5;
    // Só eleva levemente se houver lombada aguda sob o cárter (máx +4cm), mantendo pneus rentes ao piso
    const targetY = hCenter > lineMid + 0.04 ? Math.min(hCenter - 0.02, lineMid + 0.04) : lineMid;
    const pitchSlope = Math.max(-0.44, Math.min(0.44, Math.atan2(hFront - hRear, wb2)));
    return { targetY, pitchSlope, rollSlope: 0 };
  }
  const avgWheels = (hFL + hFR + hRL + hRR) * 0.25;
  const targetY = Math.max(hCenter - 0.02, avgWheels);
  const hFront = (hFL + hFR) * 0.5;
  const hRear = (hRL + hRR) * 0.5;
  const hLeft = (hFL + hRL) * 0.5;
  const hRight = (hFR + hRR) * 0.5;
  const pitchSlope = Math.max(-0.42, Math.min(0.42, Math.atan2(hFront - hRear, wb2)));
  const rollSlope = Math.max(-0.32, Math.min(0.32, Math.atan2(hRight - hLeft, Math.max(0.4, trackHalf * 2))));
  return { targetY, pitchSlope, rollSlope };
}

export function computeVehicleColliderBounds(x, z, yaw, width, length, baseY = 0, height = 1.52) {
  const c = Math.abs(Math.cos(yaw));
  const s = Math.abs(Math.sin(yaw));
  const hw = (width * c + length * s) * 0.5;
  const hd = (width * s + length * c) * 0.5;
  return {
    minX: x - hw,
    maxX: x + hw,
    minY: baseY,
    maxY: baseY + height,
    minZ: z - hd,
    maxZ: z + hd
  };
}

/**
 * Seleciona os postes mais próximos para o pool fixo de PointLights (sem alterar .visible)
 * e os cones volumétricos dentro do campo de visão frontal (elimina overdraw de 1.400 cones).
 */
export function selectNightStreetLamps(lamps, px, pz, fwdX, fwdZ, opts = {}) {
  const maxLights = opts.maxLights ?? 4;
  const maxCones = opts.maxCones ?? 28;
  const lightRange = opts.lightRange ?? 64;
  const coneRange = opts.coneRange ?? 92;
  const coneMinCos = opts.coneMinCos ?? 0.20;
  const nearAlwaysDist = opts.nearAlwaysDist ?? 18;

  const lightRangeSq = lightRange * lightRange;
  const coneRangeSq = coneRange * coneRange;
  const nearAlwaysSq = nearAlwaysDist * nearAlwaysDist;

  const lightLamps = [];
  const coneLamps = [];
  if (!Array.isArray(lamps) || lamps.length === 0) {
    return { lightLamps, coneLamps };
  }

  for (let i = 0; i < lamps.length; i++) {
    const lm = lamps[i];
    const dx = lm.lx - px;
    const dz = lm.lz - pz;
    const d2 = dx * dx + dz * dz;
    if (d2 > coneRangeSq && d2 > lightRangeSq) continue;

    let inView = d2 <= nearAlwaysSq;
    if (!inView && d2 > 1e-4) {
      const invD = 1 / Math.sqrt(d2);
      const dot = (dx * fwdX + dz * fwdZ) * invD;
      inView = dot >= coneMinCos;
    }

    if (d2 <= lightRangeSq) {
      // Prioriza postes na frente do jogador (peso menor), mantendo cobertura imediata atrás
      const score = inView ? d2 : d2 * 1.45;
      insertTopK(lightLamps, { lm, d2, score }, maxLights);
    }

    if (inView && d2 <= coneRangeSq) {
      insertTopK(coneLamps, { lm, d2, score: d2 }, maxCones);
    }
  }

  return { lightLamps, coneLamps };
}

function insertTopK(arr, item, k) {
  if (k <= 0) return;
  if (arr.length < k) {
    arr.push(item);
    for (let j = arr.length - 1; j > 0 && arr[j].score < arr[j - 1].score; j--) {
      const tmp = arr[j];
      arr[j] = arr[j - 1];
      arr[j - 1] = tmp;
    }
  } else if (item.score < arr[k - 1].score) {
    arr[k - 1] = item;
    for (let j = k - 1; j > 0 && arr[j].score < arr[j - 1].score; j--) {
      const tmp = arr[j];
      arr[j] = arr[j - 1];
      arr[j - 1] = tmp;
    }
  }
}

/**
 * Constrói grafo viário conectando vértices e cruzamentos próximos das ruas do mapa.
 */
export function buildRoadGraph(roads, snapCell = 5.5) {
  const nodes = [];
  const adj = [];
  const cellMap = new Map();

  if (!Array.isArray(roads) || roads.length === 0) {
    return { nodes, adj };
  }

  const getOrCreateNode = (x, z) => {
    const gx = Math.round(x / snapCell);
    const gz = Math.round(z / snapCell);
    let bestIdx = -1;
    let bestD2 = snapCell * snapCell;

    for (let ox = -1; ox <= 1; ox++) {
      for (let oz = -1; oz <= 1; oz++) {
        const key = `${gx + ox},${gz + oz}`;
        const bucket = cellMap.get(key);
        if (!bucket) continue;
        for (let i = 0; i < bucket.length; i++) {
          const idx = bucket[i];
          const nd = nodes[idx];
          const d2 = (nd.x - x) * (nd.x - x) + (nd.z - z) * (nd.z - z);
          if (d2 < bestD2) {
            bestD2 = d2;
            bestIdx = idx;
          }
        }
      }
    }
    if (bestIdx >= 0) return bestIdx;

    const idx = nodes.length;
    nodes.push({ x, z });
    adj.push([]);
    const key = `${gx},${gz}`;
    let bucket = cellMap.get(key);
    if (!bucket) {
      bucket = [];
      cellMap.set(key, bucket);
    }
    bucket.push(idx);
    return idx;
  };

  const addEdge = (a, b, dist, weightMult = 1.0) => {
    if (a === b || dist <= 0.1) return;
    const cost = dist * weightMult;
    const listA = adj[a];
    for (let i = 0; i < listA.length; i++) {
      if (listA[i].to === b) {
        if (cost < listA[i].cost) {
          listA[i].cost = cost;
          listA[i].dist = dist;
        }
        return;
      }
    }
    listA.push({ to: b, cost, dist });
  };

  for (let i = 0; i < roads.length; i++) {
    const r = roads[i];
    if (!r || !Array.isArray(r.pts) || r.pts.length < 2) continue;
    const cls = r.roadClass || 'street';
    // Rodovias e avenidas têm leve preferência de custo (velocidade média maior)
    const speedBias = cls === 'highway' ? 0.78 : (cls === 'avenue' ? 0.88 : (cls === 'passage' ? 1.18 : 1.0));

    let prevNode = -1;
    for (let j = 0; j < r.pts.length; j++) {
      const pt = r.pts[j];
      const px = Array.isArray(pt) ? pt[0] : pt.x;
      const pz = Array.isArray(pt) ? pt[1] : pt.z;
      if (!Number.isFinite(px) || !Number.isFinite(pz)) continue;

      // Subdivide segmentos longos (> 28m) para facilitar conexão com ruas transversais e pontos de início/fim
      if (prevNode >= 0) {
        const prev = nodes[prevNode];
        const segLen = Math.hypot(px - prev.x, pz - prev.z);
        if (segLen > 28) {
          const steps = Math.min(12, Math.ceil(segLen / 22));
          for (let s = 1; s < steps; s++) {
            const f = s / steps;
            const mx = prev.x + (px - prev.x) * f;
            const mz = prev.z + (pz - prev.z) * f;
            const midNode = getOrCreateNode(mx, mz);
            const dStep = Math.hypot(nodes[midNode].x - nodes[prevNode].x, nodes[midNode].z - nodes[prevNode].z);
            addEdge(prevNode, midNode, dStep, speedBias);
            addEdge(midNode, prevNode, dStep, speedBias);
            prevNode = midNode;
          }
        }
      }

      const curNode = getOrCreateNode(px, pz);
      if (prevNode >= 0 && prevNode !== curNode) {
        const d = Math.hypot(nodes[curNode].x - nodes[prevNode].x, nodes[curNode].z - nodes[prevNode].z);
        addEdge(prevNode, curNode, d, speedBias);
        addEdge(curNode, prevNode, d, speedBias);
      }
      prevNode = curNode;
    }
  }

  // Conecta nós vizinhos bem próximos (< 12m) que pertençam a ruas que se cruzam sem vértice compartilhado
  const linkRadius = 11.5;
  const linkRadiusSq = linkRadius * linkRadius;
  const linkCell = 12;
  const linkGrid = new Map();
  for (let i = 0; i < nodes.length; i++) {
    const gx = Math.floor(nodes[i].x / linkCell);
    const gz = Math.floor(nodes[i].z / linkCell);
    const k = `${gx},${gz}`;
    let b = linkGrid.get(k);
    if (!b) { b = []; linkGrid.set(k, b); }
    b.push(i);
  }
  for (let i = 0; i < nodes.length; i++) {
    const a = nodes[i];
    const gx = Math.floor(a.x / linkCell);
    const gz = Math.floor(a.z / linkCell);
    for (let ox = -1; ox <= 1; ox++) {
      for (let oz = -1; oz <= 1; oz++) {
        const bucket = linkGrid.get(`${gx + ox},${gz + oz}`);
        if (!bucket) continue;
        for (let bi = 0; bi < bucket.length; bi++) {
          const j = bucket[bi];
          if (j <= i) continue;
          const b = nodes[j];
          const d2 = (a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z);
          if (d2 <= linkRadiusSq && d2 > 0.25) {
            const d = Math.sqrt(d2);
            addEdge(i, j, d, 1.05);
            addEdge(j, i, d, 1.05);
          }
        }
      }
    }
  }

  return { nodes, adj };
}

/**
 * Calcula rota GPS mais curta pelas ruas usando A* com fallback gracioso para vetor direto.
 */
export function computeRoadRoute(graph, startX, startZ, endX, endZ, avgSpeedMps = 22) {
  const directDist = Math.hypot(endX - startX, endZ - startZ);
  if (!graph || !graph.nodes || graph.nodes.length < 2 || directDist < 12) {
    return {
      points: [[startX, startZ], [endX, endZ]],
      totalMeters: Math.round(directDist),
      etaSeconds: Math.max(1, Math.round(directDist / Math.max(5, avgSpeedMps))),
      viaRoads: false
    };
  }

  const { nodes, adj } = graph;
  let startIdx = -1, startD2 = Infinity;
  let endIdx = -1, endD2 = Infinity;

  for (let i = 0; i < nodes.length; i++) {
    if (adj[i].length === 0) continue;
    const nd = nodes[i];
    const ds = (nd.x - startX) * (nd.x - startX) + (nd.z - startZ) * (nd.z - startZ);
    if (ds < startD2) { startD2 = ds; startIdx = i; }
    const de = (nd.x - endX) * (nd.x - endX) + (nd.z - endZ) * (nd.z - endZ);
    if (de < endD2) { endD2 = de; endIdx = i; }
  }

  if (startIdx < 0 || endIdx < 0 || Math.sqrt(startD2) > 160 || Math.sqrt(endD2) > 160) {
    return {
      points: [[startX, startZ], [endX, endZ]],
      totalMeters: Math.round(directDist),
      etaSeconds: Math.max(1, Math.round(directDist / Math.max(5, avgSpeedMps))),
      viaRoads: false
    };
  }

  if (startIdx === endIdx) {
    const pts = [[startX, startZ], [nodes[startIdx].x, nodes[startIdx].z], [endX, endZ]];
    const total = Math.hypot(nodes[startIdx].x - startX, nodes[startIdx].z - startZ) +
      Math.hypot(endX - nodes[startIdx].x, endZ - nodes[startIdx].z);
    return {
      points: pts,
      totalMeters: Math.round(total),
      etaSeconds: Math.max(1, Math.round(total / Math.max(5, avgSpeedMps))),
      viaRoads: true
    };
  }

  const n = nodes.length;
  const gScore = new Float64Array(n);
  const fScore = new Float64Array(n);
  const cameFrom = new Int32Array(n);
  const closed = new Uint8Array(n);
  gScore.fill(Infinity);
  fScore.fill(Infinity);
  cameFrom.fill(-1);

  const goalNode = nodes[endIdx];
  const heuristic = (idx) => Math.hypot(nodes[idx].x - goalNode.x, nodes[idx].z - goalNode.z) * 0.78;

  // Min-heap simples de índices para A* ultrarrápido (< 2ms mesmo em 2.500 nós!)
  const heap = [];
  const heapPush = (nodeIdx, f) => {
    heap.push({ idx: nodeIdx, f });
    let pos = heap.length - 1;
    while (pos > 0) {
      const parent = (pos - 1) >> 1;
      if (heap[parent].f <= heap[pos].f) break;
      const tmp = heap[parent]; heap[parent] = heap[pos]; heap[pos] = tmp;
      pos = parent;
    }
  };
  const heapPop = () => {
    const top = heap[0];
    const last = heap.pop();
    if (heap.length > 0 && last) {
      heap[0] = last;
      let pos = 0;
      const len = heap.length;
      while (true) {
        let best = pos;
        const l = (pos << 1) + 1;
        const r = l + 1;
        if (l < len && heap[l].f < heap[best].f) best = l;
        if (r < len && heap[r].f < heap[best].f) best = r;
        if (best === pos) break;
        const tmp = heap[pos]; heap[pos] = heap[best]; heap[best] = tmp;
        pos = best;
      }
    }
    return top;
  };

  gScore[startIdx] = 0;
  fScore[startIdx] = heuristic(startIdx);
  heapPush(startIdx, fScore[startIdx]);

  let found = false;
  let expanded = 0;
  const maxExpansions = Math.min(8000, n * 3 + 200);

  while (heap.length > 0 && expanded < maxExpansions) {
    const cur = heapPop();
    const u = cur.idx;
    if (closed[u]) continue;
    if (u === endIdx) { found = true; break; }
    closed[u] = 1;
    expanded++;

    const edges = adj[u];
    const gu = gScore[u];
    for (let i = 0; i < edges.length; i++) {
      const e = edges[i];
      if (closed[e.to]) continue;
      const tentative = gu + e.cost;
      if (tentative < gScore[e.to]) {
        cameFrom[e.to] = u;
        gScore[e.to] = tentative;
        const f = tentative + heuristic(e.to);
        fScore[e.to] = f;
        heapPush(e.to, f);
      }
    }
  }

  if (!found) {
    return {
      points: [[startX, startZ], [endX, endZ]],
      totalMeters: Math.round(directDist),
      etaSeconds: Math.max(1, Math.round(directDist / Math.max(5, avgSpeedMps))),
      viaRoads: false
    };
  }

  const rev = [];
  let cur = endIdx;
  while (cur !== -1) {
    rev.push(cur);
    cur = cameFrom[cur];
  }
  rev.reverse();

  const points = [[startX, startZ]];
  for (let i = 0; i < rev.length; i++) {
    const nd = nodes[rev[i]];
    const last = points[points.length - 1];
    if (Math.hypot(nd.x - last[0], nd.z - last[1]) > 1.5) {
      points.push([nd.x, nd.z]);
    }
  }
  const lastPt = points[points.length - 1];
  if (Math.hypot(endX - lastPt[0], endZ - lastPt[1]) > 1.5) {
    points.push([endX, endZ]);
  }

  let totalMeters = 0;
  for (let i = 1; i < points.length; i++) {
    totalMeters += Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]);
  }

  return {
    points,
    totalMeters: Math.round(totalMeters),
    etaSeconds: Math.max(1, Math.round(totalMeters / Math.max(5, avgSpeedMps))),
    viaRoads: true
  };
}

/**
 * Calcula parâmetros acústicos 3D reais para qualquer som no mundo (tiros, veículos, zumbis, explosões):
 * - pan (-1 esquerda .. +1 direita)
 * - frontDot (+1 frente .. -1 atrás)
 * - gain (atenuação suave por distância: forte de perto, mais suave mas direcional de longe!)
 * - lowpassHz (absorção atmosférica por distância + escurecimento pinna quando vem por trás!)
 * - delaySec (atraso real da velocidade do som para tiros/explosões distantes)
 */
export function computeSpatialAudioParams(listenerPos, listenerFwd, listenerRight, sourcePos, opts = {}) {
  const refDist = opts.refDist ?? 14;
  const maxDist = opts.maxDist ?? 420;
  const rolloff = opts.rolloff ?? 1.25;
  const maxLowpass = opts.maxLowpass ?? 16000;
  const minLowpass = opts.minLowpass ?? 900;
  const speedOfSound = opts.speedOfSound ?? 343;

  const dx = (sourcePos.x || 0) - (listenerPos.x || 0);
  const dy = (sourcePos.y || 0) - (listenerPos.y || 0);
  const dz = (sourcePos.z || 0) - (listenerPos.z || 0);
  const dist = Math.hypot(dx, dy, dz);

  if (dist >= maxDist) {
    return {
      audible: false,
      dist,
      pan: 0,
      frontDot: 0,
      gain: 0,
      lowpassHz: minLowpass,
      delaySec: 0,
      direction: 'out-of-range'
    };
  }

  let dirX = 0, dirY = 0, dirZ = 0;
  if (dist > 1e-4) {
    const inv = 1 / dist;
    dirX = dx * inv;
    dirY = dy * inv;
    dirZ = dz * inv;
  }

  // Normaliza vetores horizontais/3D do ouvinte para projeção exata esquerda/direita e frente/trás
  const rLen = Math.hypot(listenerRight.x || 0, listenerRight.y || 0, listenerRight.z || 0) || 1;
  const rx = (listenerRight.x || 0) / rLen, ry = (listenerRight.y || 0) / rLen, rz = (listenerRight.z || 0) / rLen;

  const fLen = Math.hypot(listenerFwd.x || 0, listenerFwd.y || 0, listenerFwd.z || 0) || 1;
  const fx = (listenerFwd.x || 0) / fLen, fy = (listenerFwd.y || 0) / fLen, fz = (listenerFwd.z || 0) / fLen;

  const pan = dist < 0.35 ? 0 : Math.max(-1, Math.min(1, dirX * rx + dirY * ry + dirZ * rz));
  const frontDot = dist < 0.35 ? 1 : Math.max(-1, Math.min(1, dirX * fx + dirY * fy + dirZ * fz));

  // Atenuação inversa suave com cauda macia até maxDist (tiros distantes continuam audíveis e direcionais!)
  let distGain = 1.0;
  if (dist > refDist) {
    const invCurve = refDist / (refDist + rolloff * (dist - refDist));
    const edgeT = Math.max(0, Math.min(1, (dist - refDist) / Math.max(1, maxDist - refDist)));
    const smoothTail = 1 - edgeT * edgeT;
    distGain = invCurve * smoothTail;
  }

  // Escurecimento acústico anatômico (pinna) quando o som vem de TRÁS: permite diferenciar frente vs trás claramente!
  const rearAlpha = Math.max(0, -frontDot); // 0 na frente/lados, 1 exatamente atrás
  const rearGainMult = 1 - rearAlpha * 0.16; // leve sombra traseira (~-1.5dB)
  const gain = Math.max(0, Math.min(1, distGain * rearGainMult));

  // Absorção atmosférica de agudos pela distância + filtro de orelha (pinna) para som vindo de trás
  const distNorm = Math.max(0, Math.min(1, (dist - refDist * 0.5) / Math.max(1, maxDist - refDist * 0.5)));
  const distLp = maxLowpass * Math.pow(minLowpass / maxLowpass, Math.pow(distNorm, 0.72));
  const rearLpMult = 1 - rearAlpha * 0.56; // atrás reduz agudos em até 56% -> timbre inconfundível de costas!
  const lowpassHz = Math.max(520, Math.min(maxLowpass, Math.round(distLp * rearLpMult)));

  const delaySec = opts.useSpeedOfSound ? Math.min(0.85, dist / speedOfSound) : 0;

  // Classificação legível da direção percebida
  let direction = 'center';
  if (dist >= 0.35) {
    const absPan = Math.abs(pan);
    const absFront = Math.abs(frontDot);
    if (absFront >= 0.72 && absPan < 0.45) {
      direction = frontDot >= 0 ? 'front' : 'back';
    } else if (absPan >= 0.72 && absFront < 0.45) {
      direction = pan >= 0 ? 'right' : 'left';
    } else {
      direction = `${frontDot >= 0 ? 'front' : 'back'}-${pan >= 0 ? 'right' : 'left'}`;
    }
  }

  return {
    audible: gain > 0.008,
    dist,
    pan,
    frontDot,
    gain,
    lowpassHz,
    delaySec,
    direction
  };
}

/**
 * Calcula perfil acústico contínuo de motor para Carros (V6/I4) e Motos (Trail 450 monocilíndrica / Street 600 esportiva).
 */
export function computeVehicleEngineProfile(isMoto, motoStyle, speedMps, throttle = 0, isOccupied = false, maxSpeed = 30) {
  const spd = Math.abs(speedMps || 0);
  const active = isOccupied || spd > 0.35;
  if (!active) {
    return { active: false, rpmNorm: 0, gear: 1, baseFreq: 45, overtoneFreq: 90, filterHz: 220, gain: 0, pulseHz: 0 };
  }

  const speedNorm = Math.max(0, Math.min(1.12, spd / Math.max(8, maxSpeed)));
  const gearCount = isMoto ? (motoStyle === 'street' ? 5 : 4) : 4;
  const scaled = speedNorm * gearCount;
  const gear = Math.max(1, Math.min(gearCount, Math.floor(scaled) + 1));
  const gearFrac = gear >= gearCount ? Math.min(1, scaled - (gearCount - 1)) : (scaled - Math.floor(scaled));

  const thrBoost = Math.max(0, throttle) * 0.22;
  const idleRpm = isMoto ? 0.19 : 0.16;
  const rpmNorm = Math.max(idleRpm, Math.min(1.0, idleRpm + gearFrac * 0.68 + speedNorm * 0.18 + thrBoost));

  if (isMoto) {
    if (motoStyle === 'street') {
      // Moto Street 600: motor 4 cilindros esportivo agudo e contínuo
      const baseFreq = 98 + rpmNorm * 265;
      return {
        active: true,
        rpmNorm,
        gear,
        baseFreq,
        overtoneFreq: baseFreq * 2.0,
        filterHz: 680 + rpmNorm * 3100,
        gain: 0.075 + rpmNorm * 0.115 + Math.max(0, throttle) * 0.035,
        pulseHz: 18 + rpmNorm * 42
      };
    }
    // Moto Trail 450: monocilíndrica grave com batida ("brap-brap") marcante
    const baseFreq = 58 + rpmNorm * 142;
    return {
      active: true,
      rpmNorm,
      gear,
      baseFreq,
      overtoneFreq: baseFreq * 1.5,
      filterHz: 420 + rpmNorm * 2100,
      gain: 0.085 + rpmNorm * 0.125 + Math.max(0, throttle) * 0.04,
      pulseHz: 13 + rpmNorm * 34
    };
  }

  // Carro (Sedan / Sheriff / Ranger 4x4): ronco grave encorpado V6/I4
  const baseFreq = 44 + rpmNorm * 108;
  return {
    active: true,
    rpmNorm,
    gear,
    baseFreq,
    overtoneFreq: baseFreq * 2.0,
    filterHz: 230 + rpmNorm * 1180,
    gain: 0.08 + rpmNorm * 0.11 + Math.max(0, throttle) * 0.035,
    pulseHz: 8 + rpmNorm * 22
  };
}

