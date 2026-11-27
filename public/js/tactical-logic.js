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

/* ============================================================================
   SINTETIZADOR DE RUAS INTERNAS PARA CONDOMÍNIOS / VILAS SEM VIA NO OSM
   ============================================================================ */
function _ptSegDistSq(px, pz, ax, az, bx, bz) {
  const vx = bx - ax, vz = bz - az;
  const lenSq = vx * vx + vz * vz;
  if (lenSq < 1e-6) return (px - ax) * (px - ax) + (pz - az) * (pz - az);
  let t = ((px - ax) * vx + (pz - az) * vz) / lenSq;
  if (t < 0) t = 0;
  else if (t > 1) t = 1;
  const dx = px - (ax + vx * t);
  const dz = pz - (az + vz * t);
  return dx * dx + dz * dz;
}

function _nearestSegOnList(x, z, segs) {
  let bestD2 = Infinity;
  let best = null;
  for (let i = 0; i < segs.length; i++) {
    const s = segs[i];
    const vx = s.bx - s.ax, vz = s.bz - s.az;
    const lenSq = vx * vx + vz * vz;
    if (lenSq < 1e-4) continue;
    let t = ((x - s.ax) * vx + (z - s.az) * vz) / lenSq;
    if (t < 0) t = 0;
    else if (t > 1) t = 1;
    const projX = s.ax + vx * t;
    const projZ = s.az + vz * t;
    const d2 = (x - projX) * (x - projX) + (z - projZ) * (z - projZ);
    if (d2 < bestD2) {
      bestD2 = d2;
      best = { seg: s, projX, projZ, dist: Math.sqrt(d2) };
    }
  }
  return best;
}

/**
 * Prioriza vias mantendo ruas residenciais e travessas (limite ampliado para 950 vias)
 * para evitar cortes de bairros inteiros no OpenStreetMap.
 */
export function mergeAndPrioritizeRoads(rawRoads, maxRoads = 950) {
  const classPriority = { highway: 0, avenue: 1, street: 2, residential: 3, passage: 4, service: 5 };
  return (rawRoads || [])
    .filter(r => r && Array.isArray(r.pts) && r.pts.length >= 2)
    .sort((a, b) => (classPriority[a.roadClass] ?? 3) - (classPriority[b.roadClass] ?? 3))
    .slice(0, maxRoads)
    .map(r => {
      const roadClass = r.roadClass || 'street';
      const defaultW = roadClass === 'highway' ? 16.0 : (roadClass === 'avenue' ? 12.4 : (roadClass === 'passage' || roadClass === 'service' ? 5.8 : 8.2));
      return {
        name: String(r.name || '').slice(0, 36),
        roadClass,
        width: +(r.width || defaultW).toFixed(1),
        oneway: r.oneway === 1 ? 1 : 0,
        lanes: Number.isFinite(r.lanes) ? r.lanes : 0,
        pts: r.pts.map(p => Array.isArray(p) ? [+(p[0]).toFixed(1), +(p[1]).toFixed(1)] : [+(p.x).toFixed(1), +(p.z).toFixed(1)])
      };
    });
}

/**
 * Detecta aglomerados de casas/prédios sem rua próxima (condomínios fechados, vilas ou quadras sem
 * vias mapeadas no OpenStreetMap) e gera automaticamente alamedas/ruas internas alinhadas entre as
 * construções, conectando-as diretamente à malha viária real mais próxima.
 */
export function synthesizeCondoAccessRoads(roads, rawBuildings, opts = {}) {
  const orphanThreshold = opts.orphanThreshold ?? 22;
  const clusterRadius = opts.clusterRadius ?? 46;
  const laneSpacing = opts.laneSpacing ?? 28;
  const halfM = opts.halfM ?? 1500;
  const maxNewRoads = opts.maxNewRoads ?? 140;

  if (!Array.isArray(rawBuildings) || rawBuildings.length === 0) {
    return { roads: Array.isArray(roads) ? roads.slice() : [], addedRoads: [], clusterCount: 0, orphanCount: 0 };
  }

  const outRoads = Array.isArray(roads) ? roads.slice() : [];
  const segs = [];
  const pushRoadSegs = (rd) => {
    const pts = rd.pts || [];
    for (let i = 1; i < pts.length; i++) {
      const ax = Array.isArray(pts[i - 1]) ? pts[i - 1][0] : pts[i - 1].x;
      const az = Array.isArray(pts[i - 1]) ? pts[i - 1][1] : pts[i - 1].z;
      const bx = Array.isArray(pts[i]) ? pts[i][0] : pts[i].x;
      const bz = Array.isArray(pts[i]) ? pts[i][1] : pts[i].z;
      const len = Math.hypot(bx - ax, bz - az);
      if (len < 1.2) continue;
      segs.push({ ax, az, bx, bz, tx: (bx - ax) / len, tz: (bz - az) / len, len });
    }
  };
  for (let i = 0; i < outRoads.length; i++) pushRoadSegs(outRoads[i]);

  // 1. Filtra construções "órfãs" (distantes de qualquer rua existente)
  const orphans = [];
  const threshSq = orphanThreshold * orphanThreshold;
  for (let i = 0; i < rawBuildings.length; i++) {
    const b = rawBuildings[i];
    if (!b || !Number.isFinite(b.x) || !Number.isFinite(b.z)) continue;
    if (b.prefab === 'park' || b.prefab === 'cemetery') continue;
    if (Math.abs(b.x) > halfM - 16 || Math.abs(b.z) > halfM - 16) continue;
    let minD2 = Infinity;
    for (let s = 0; s < segs.length; s++) {
      const d2 = _ptSegDistSq(b.x, b.z, segs[s].ax, segs[s].az, segs[s].bx, segs[s].bz);
      if (d2 < minD2) {
        minD2 = d2;
        if (minD2 < threshSq) break;
      }
    }
    if (minD2 >= threshSq) {
      orphans.push({ x: b.x, z: b.z, idx: i });
    }
  }

  if (orphans.length === 0) {
    return { roads: outRoads, addedRoads: [], clusterCount: 0, orphanCount: 0 };
  }

  // 2. Agrupa casas órfãs em clusters espaciais (condomínios / vilas) via BFS
  const cell = clusterRadius;
  const grid = new Map();
  for (let i = 0; i < orphans.length; i++) {
    const k = `${Math.floor(orphans[i].x / cell)},${Math.floor(orphans[i].z / cell)}`;
    let arr = grid.get(k);
    if (!arr) { arr = []; grid.set(k, arr); }
    arr.push(i);
  }

  const visited = new Uint8Array(orphans.length);
  const clusters = [];
  const radSq = clusterRadius * clusterRadius;
  for (let i = 0; i < orphans.length; i++) {
    if (visited[i]) continue;
    visited[i] = 1;
    const q = [i];
    const members = [];
    while (q.length > 0) {
      const cur = q.pop();
      const o = orphans[cur];
      members.push(o);
      const gx = Math.floor(o.x / cell);
      const gz = Math.floor(o.z / cell);
      for (let ox = -1; ox <= 1; ox++) {
        for (let oz = -1; oz <= 1; oz++) {
          const arr = grid.get(`${gx + ox},${gz + oz}`);
          if (!arr) continue;
          for (let k = 0; k < arr.length; k++) {
            const ni = arr[k];
            if (visited[ni]) continue;
            const nb = orphans[ni];
            const d2 = (nb.x - o.x) * (nb.x - o.x) + (nb.z - o.z) * (nb.z - o.z);
            if (d2 <= radSq) {
              visited[ni] = 1;
              q.push(ni);
            }
          }
        }
      }
    }
    clusters.push(members);
  }

  // Ordena clusters por tamanho decrescente (maiores condomínios primeiro)
  clusters.sort((a, b) => b.length - a.length);

  const addedRoads = [];
  const clampB = (v) => Math.max(-(halfM - 10), Math.min(halfM - 10, v));
  const addSynthesizedRoad = (name, pts, width = 6.4, roadClass = 'residential') => {
    if (addedRoads.length >= maxNewRoads || pts.length < 2) return;
    const cleanPts = [];
    for (let i = 0; i < pts.length; i++) {
      const px = +clampB(pts[i][0]).toFixed(1);
      const pz = +clampB(pts[i][1]).toFixed(1);
      if (cleanPts.length === 0 || Math.hypot(px - cleanPts[cleanPts.length - 1][0], pz - cleanPts[cleanPts.length - 1][1]) >= 2.5) {
        cleanPts.push([px, pz]);
      }
    }
    if (cleanPts.length < 2) return;
    const rd = { name, roadClass, width, oneway: 0, lanes: 2, pts: cleanPts, synthesized: true };
    outRoads.push(rd);
    addedRoads.push(rd);
    pushRoadSegs(rd);
  };

  let condoIdx = 1;
  for (let ci = 0; ci < clusters.length && addedRoads.length < maxNewRoads; ci++) {
    const members = clusters[ci];
    let cx = 0, cz = 0;
    for (let i = 0; i < members.length; i++) { cx += members[i].x; cz += members[i].z; }
    cx /= members.length;
    cz /= members.length;

    const nearExt = _nearestSegOnList(cx, cz, segs);

    // Casa isolada muito distante (> 30m): puxa uma travessa de acesso curta até a rua mais próxima
    if (members.length === 1) {
      if (nearExt && nearExt.dist > 28 && nearExt.dist < 140) {
        const dx = cx - nearExt.projX;
        const dz = cz - nearExt.projZ;
        const d = Math.hypot(dx, dz) || 1;
        const stopX = cx - (dx / d) * 9.5;
        const stopZ = cz - (dz / d) * 9.5;
        if (Math.hypot(stopX - nearExt.projX, stopZ - nearExt.projZ) >= 8) {
          addSynthesizedRoad('Acesso Residencial', [[nearExt.projX, nearExt.projZ], [stopX, stopZ]], 5.8, 'passage');
        }
      }
      continue;
    }

    // Eixo local do condomínio: alinha à rua real mais próxima (se estiver perto) ou ao eixo principal do cluster
    let ux = 1, uz = 0;
    if (nearExt && nearExt.dist < 220) {
      ux = nearExt.seg.tx;
      uz = nearExt.seg.tz;
    } else {
      let sxx = 0, szz = 0, sxz = 0;
      for (let i = 0; i < members.length; i++) {
        const dx = members[i].x - cx, dz = members[i].z - cz;
        sxx += dx * dx; szz += dz * dz; sxz += dx * dz;
      }
      const ang = 0.5 * Math.atan2(2 * sxz, sxx - szz);
      ux = Math.cos(ang);
      uz = Math.sin(ang);
    }
    const vx = -uz, vz = ux; // perpendicular

    // Projeta todas as casas do condomínio no referencial local (u, v)
    let minU = Infinity, maxU = -Infinity, minV = Infinity, maxV = -Infinity;
    const proj = members.map(m => {
      const dx = m.x - cx, dz = m.z - cz;
      const u = dx * ux + dz * uz;
      const v = dx * vx + dz * vz;
      if (u < minU) minU = u; if (u > maxU) maxU = u;
      if (v < minV) minV = v; if (v > maxV) maxV = v;
      return { u, v };
    });

    const spanU = maxU - minU;
    const spanV = maxV - minV;
    const toWorld = (u, v) => [cx + ux * u + vx * v, cz + uz * u + vz * v];

    // Escolhe deslocamento de faixa que minimize sobreposição direta sobre centros de casas (corredor limpo entre fileiras)
    const findCleanLaneCoord = (targetCoord, axisKey, searchSpan = 6.5) => {
      let bestCoord = targetCoord;
      let bestPenalty = Infinity;
      for (let off = -searchSpan; off <= searchSpan + 0.01; off += 2.15) {
        const c = targetCoord + off;
        let pen = Math.abs(off) * 0.08;
        for (let i = 0; i < proj.length; i++) {
          const d = Math.abs(proj[i][axisKey] - c);
          if (d < 8.5) pen += (8.5 - d) * (8.5 - d);
        }
        if (pen < bestPenalty) {
          bestPenalty = pen;
          bestCoord = c;
        }
      }
      return bestCoord;
    };

    const padU = Math.min(12, Math.max(6, spanU * 0.08));
    const padV = Math.min(12, Math.max(6, spanV * 0.08));
    const uStart = minU - padU;
    const uEnd = maxU + padU;
    const vStart = minV - padV;
    const vEnd = maxV + padV;

    // Gera alamedas paralelas ao eixo U (espaçadas a cada ~laneSpacing m)
    const uLanesV = [];
    const numULanes = Math.max(1, Math.min(6, Math.round(spanV / laneSpacing) + 1));
    if (numULanes === 1) {
      uLanesV.push(findCleanLaneCoord((minV + maxV) * 0.5, 'v'));
    } else {
      const stepV = spanV / numULanes;
      for (let li = 0; li < numULanes; li++) {
        const baseV = minV + (li + 0.5) * stepV;
        uLanesV.push(findCleanLaneCoord(baseV, 'v'));
      }
    }

    const labelBase = members.length >= 8 ? `Alameda Cond. ${condoIdx}` : `Vila Interna ${condoIdx}`;
    condoIdx++;

    for (let li = 0; li < uLanesV.length; li++) {
      const lv = uLanesV[li];
      const pA = toWorld(uStart, lv);
      const pB = toWorld(uEnd, lv);
      if (Math.hypot(pB[0] - pA[0], pB[1] - pA[1]) >= 10) {
        addSynthesizedRoad(
          li === 0 ? labelBase : `${labelBase} · Trav. ${li}`,
          [pA, toWorld((uStart + uEnd) * 0.5, lv), pB],
          6.4,
          'residential'
        );
      }
    }

    // Gera ruas transversais ao eixo V quando o condomínio tem largura suficiente ou múltiplas alamedas
    const crossUs = [];
    if (uLanesV.length >= 2 || spanU > 38) {
      const numCross = Math.max(1, Math.min(5, Math.floor(spanU / (laneSpacing * 1.15)) + 1));
      if (numCross === 1) {
        crossUs.push(findCleanLaneCoord((minU + maxU) * 0.5, 'u'));
      } else {
        const stepU = spanU / numCross;
        for (let ci2 = 0; ci2 < numCross; ci2++) {
          const baseU = minU + (ci2 + 0.5) * stepU;
          crossUs.push(findCleanLaneCoord(baseU, 'u'));
        }
      }
      const vLo = Math.min(vStart, ...uLanesV);
      const vHi = Math.max(vEnd, ...uLanesV);
      for (let k = 0; k < crossUs.length; k++) {
        const cu = crossUs[k];
        const pA = toWorld(cu, vLo);
        const pB = toWorld(cu, vHi);
        if (Math.hypot(pB[0] - pA[0], pB[1] - pA[1]) >= 12) {
          addSynthesizedRoad(`${labelBase} · Acesso`, [pA, toWorld(cu, (vLo + vHi) * 0.5), pB], 6.2, 'residential');
        }
      }
    }

    // Conecta a malha interna do condomínio diretamente à rua externa real mais próxima (portaria / entrada)
    if (nearExt && nearExt.dist < 240) {
      // Escolhe a extremidade mais próxima da malha interna para ligar à rua externa
      const anchors = [];
      for (let li = 0; li < uLanesV.length; li++) {
        anchors.push(toWorld(uStart, uLanesV[li]), toWorld(uEnd, uLanesV[li]));
      }
      for (let k = 0; k < crossUs.length; k++) {
        anchors.push(toWorld(crossUs[k], vStart), toWorld(crossUs[k], vEnd));
      }
      let bestAnchor = anchors[0] || [cx, cz];
      let bestConn = nearExt;
      let bestConnDist = Infinity;
      // Usa apenas segmentos originais (externos) para garantir ligação com a cidade fora do condomínio
      const extSegCount = segs.length - addedRoads.reduce((acc, r) => acc + Math.max(0, r.pts.length - 1), 0);
      const extSegs = extSegCount > 0 ? segs.slice(0, extSegCount) : segs;
      for (let ai = 0; ai < anchors.length; ai++) {
        const a = anchors[ai];
        const n = _nearestSegOnList(a[0], a[1], extSegs);
        if (n && n.dist < bestConnDist) {
          bestConnDist = n.dist;
          bestAnchor = a;
          bestConn = n;
        }
      }
      if (bestConn && bestConnDist >= 3.5 && bestConnDist < 220) {
        addSynthesizedRoad(`Entrada ${labelBase}`, [bestAnchor, [bestConn.projX, bestConn.projZ]], 6.8, 'residential');
      }
    }
  }

  return {
    roads: outRoads,
    addedRoads,
    clusterCount: clusters.length,
    orphanCount: orphans.length
  };
}

/* ============================================================================
   FASE 2 — MUNDO POR CHUNKS DETERMINÍSTICOS + MACRO-MAPA + VALIDAÇÃO DE SPAWN
   (Zero Math.random(), zero Math.sin() — 100% determinístico entre navegadores)
   ============================================================================ */
export const WORLD_SIZE_PRESETS = {
  small:  { key: 'small',  label: 'Pequeno (4×4 km)',  sizeMeters: 4096,  halfMeters: 2048, chunksPerAxis: 64,  cityCount: 6 },
  medium: { key: 'medium', label: 'Médio (8×8 km)',    sizeMeters: 8192,  halfMeters: 4096, chunksPerAxis: 128, cityCount: 9 },
  large:  { key: 'large',  label: 'Grande (16×16 km)', sizeMeters: 16384, halfMeters: 8192, chunksPerAxis: 256, cityCount: 12 }
};

export const KNOX_REGION_CATALOG = [
  { name: 'Cuiabá Central',     tier: 'metropolis', loot: 'Alto',   danger: 'Extremo', radius: 290 },
  { name: 'Fortaleza Sul',      tier: 'metropolis', loot: 'Alto',   danger: 'Alto',    radius: 260 },
  { name: 'Porto Claro',        tier: 'town',       loot: 'Médio',  danger: 'Médio',   radius: 210 },
  { name: 'Vila Aurora',        tier: 'town',       loot: 'Médio',  danger: 'Médio',   radius: 195 },
  { name: 'Serra Dourada',      tier: 'town',       loot: 'Médio',  danger: 'Médio',   radius: 190 },
  { name: 'Ribeirão Alto',      tier: 'town',       loot: 'Médio',  danger: 'Baixo',   radius: 175 },
  { name: 'Campo Verde',        tier: 'rural',      loot: 'Baixo',  danger: 'Baixo',   radius: 145 },
  { name: 'Nova Esperança',     tier: 'town',       loot: 'Médio',  danger: 'Médio',   radius: 185 },
  { name: 'Vale do Sol',        tier: 'rural',      loot: 'Baixo',  danger: 'Baixo',   radius: 140 },
  { name: 'Fazenda Boa Vista',  tier: 'rural',      loot: 'Baixo',  danger: 'Baixo',   radius: 135 },
  { name: 'Ponte Branca',       tier: 'town',       loot: 'Médio',  danger: 'Médio',   radius: 175 },
  { name: 'Estância Norte',     tier: 'rural',      loot: 'Baixo',  danger: 'Baixo',   radius: 145 }
];

export function hashInt32(seed, x, z) {
  let h = (seed | 0) ^ 0x9e3779b9;
  h = Math.imul(h ^ (x | 0), 0x85ebca6b);
  h = Math.imul(h ^ (z | 0), 0xc2b2ae35);
  h ^= h >>> 16;
  h = Math.imul(h, 0x27d4eb2d);
  h ^= h >>> 15;
  return h >>> 0;
}

export function createDeterministicRng(seed) {
  let a = (seed >>> 0) || 1;
  return function () {
    a |= 0;
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function worldToChunk(x, z, chunkSize = 64) {
  return {
    cx: Math.floor(x / chunkSize),
    cz: Math.floor(z / chunkSize)
  };
}

export function chunkKey(cx, cz) {
  return `${cx},${cz}`;
}

export function isWithinAOI(cxA, czA, cxB, czB, radiusChunks = 4) {
  return Math.max(Math.abs(cxA - cxB), Math.abs(czA - czB)) <= radiusChunks;
}

// Ruído de valor 2D baseado estritamente em hash inteiro (idêntico em qualquer navegador/CPU)
function _valueNoise2D(seed, x, z) {
  const xi = Math.floor(x);
  const zi = Math.floor(z);
  const xf = x - xi;
  const zf = z - zi;
  const u = xf * xf * (3 - 2 * xf);
  const v = zf * zf * (3 - 2 * zf);

  const n00 = hashInt32(seed, xi, zi) / 4294967295;
  const n10 = hashInt32(seed, xi + 1, zi) / 4294967295;
  const n01 = hashInt32(seed, xi, zi + 1) / 4294967295;
  const n11 = hashInt32(seed, xi + 1, zi + 1) / 4294967295;

  const nx0 = n00 + (n10 - n00) * u;
  const nx1 = n01 + (n11 - n01) * u;
  return nx0 + (nx1 - nx0) * v;
}

function _fbm2D(seed, x, z) {
  const a = _valueNoise2D(seed, x, z) * 0.62;
  const b = _valueNoise2D(seed + 1013, x * 2.03 + 11.7, z * 2.03 - 7.3) * 0.26;
  const c = _valueNoise2D(seed + 2909, x * 4.11 - 5.1, z * 4.11 + 19.4) * 0.12;
  return a + b + c;
}

/**
 * Gera o Macro-Mapa determinístico completo a partir da seed e do tamanho do mundo.
 * Alimenta os chunks 3D, a tela de escolha de spawn e o mapa tático [M].
 */
export function generateWorldMacroMap(worldSeed, sizeKey = 'medium', chunkSize = 64) {
  const preset = WORLD_SIZE_PRESETS[sizeKey] || WORLD_SIZE_PRESETS.medium;
  const seedInt = ((Number(worldSeed) || 1337) >>> 0);
  const rng = createDeterministicRng(hashInt32(seedInt, 77, 313));
  const half = preset.halfMeters;
  const usable = half * 0.78;

  // 1. Lagos naturais determinísticos (evitados pelas cidades e pelo validador de spawn)
  const lakes = [];
  const lakeCount = Math.max(3, Math.round(preset.cityCount * 0.65));
  for (let i = 0; i < lakeCount; i++) {
    const lx = (rng() * 2 - 1) * usable * 0.92;
    const lz = (rng() * 2 - 1) * usable * 0.92;
    const rx = 110 + rng() * 170;
    const rz = 95 + rng() * 155;
    // Deixa uma clareira seca próxima à origem (0,0)
    if (Math.hypot(lx, lz) < rx + 260) continue;
    lakes.push({ x: Math.round(lx), z: Math.round(lz), rx: Math.round(rx), rz: Math.round(rz) });
  }

  // 2. Cidades e Regiões Nomeadas (com espaçamento mínimo garantido)
  const cities = [];
  const minCitySep = Math.max(680, Math.round(preset.sizeMeters / (Math.sqrt(preset.cityCount) * 1.38)));
  for (let i = 0; i < preset.cityCount; i++) {
    const tpl = KNOX_REGION_CATALOG[i % KNOX_REGION_CATALOG.length];
    let cx = 0, cz = 0;
    let placed = false;
    if (i === 0) {
      // Cidade central próxima à origem para referência e ação imediata
      cx = Math.round((rng() - 0.5) * 320);
      cz = Math.round((rng() - 0.5) * 320);
      placed = true;
    } else {
      for (let tries = 0; tries < 60; tries++) {
        const tx = (rng() * 2 - 1) * usable;
        const tz = (rng() * 2 - 1) * usable;
        let ok = true;
        for (let j = 0; j < cities.length; j++) {
          if (Math.hypot(tx - cities[j].x, tz - cities[j].z) < minCitySep) { ok = false; break; }
        }
        if (!ok) continue;
        for (let j = 0; j < lakes.length; j++) {
          if (Math.hypot(tx - lakes[j].x, tz - lakes[j].z) < Math.max(lakes[j].rx, lakes[j].rz) + tpl.radius + 70) { ok = false; break; }
        }
        if (ok) { cx = Math.round(tx); cz = Math.round(tz); placed = true; break; }
      }
    }
    if (!placed) {
      const idxAngle = (i / preset.cityCount) * 6.283185307179586;
      const dist = usable * 0.68;
      // Aproximação polinomial / trig evitada: usa pontos em anel octogonal determinístico
      const oct = [[1, 0], [0.707, 0.707], [0, 1], [-0.707, 0.707], [-1, 0], [-0.707, -0.707], [0, -1], [0.707, -0.707]];
      const dir = oct[i % oct.length];
      cx = Math.round(dir[0] * dist + (rng() - 0.5) * 240);
      cz = Math.round(dir[1] * dist + (rng() - 0.5) * 240);
      void idxAngle;
    }
    // Alinha o centro da cidade à grade de chunks (64m) para encaixe perfeito das avenidas!
    cx = Math.round(cx / chunkSize) * chunkSize;
    cz = Math.round(cz / chunkSize) * chunkSize;
    cities.push({
      id: `city-${i}`,
      name: tpl.name,
      tier: tpl.tier,
      loot: tpl.loot,
      danger: tpl.danger,
      x: cx,
      z: cz,
      radius: tpl.radius
    });
  }

  // 3. Rodovias principais ligando todas as cidades (Árvore Geradora Mínima + 2 anéis extras)
  const highways = [];
  const edgeSet = new Set();
  const addHighway = (aIdx, bIdx, kind = 'highway') => {
    const lo = Math.min(aIdx, bIdx), hi = Math.max(aIdx, bIdx);
    const key = `${lo}-${hi}`;
    if (lo === hi || edgeSet.has(key)) return;
    edgeSet.add(key);
    const a = cities[lo], b = cities[hi];
    // Ponto intermediário alinhado (curva suave em L/quebra natural) para estradas parecerem reais
    const midX = Math.round(((a.x + b.x) * 0.5 + (rng() - 0.5) * 140) / chunkSize) * chunkSize;
    const midZ = Math.round(((a.z + b.z) * 0.5 + (rng() - 0.5) * 140) / chunkSize) * chunkSize;
    highways.push({
      name: `Rod. ${a.name.split(' ')[0]}-${b.name.split(' ')[0]}`,
      roadClass: kind,
      width: kind === 'highway' ? 12.0 : 9.0,
      fromCity: a.id,
      toCity: b.id,
      pts: [[a.x, a.z], [midX, midZ], [b.x, b.z]]
    });
  };

  if (cities.length >= 2) {
    // Prim's MST garante que todas as regiões estejam conectadas por rodovia
    const inTree = new Uint8Array(cities.length);
    inTree[0] = 1;
    for (let step = 1; step < cities.length; step++) {
      let bestA = 0, bestB = 1, bestD = Infinity;
      for (let i = 0; i < cities.length; i++) {
        if (!inTree[i]) continue;
        for (let j = 0; j < cities.length; j++) {
          if (inTree[j]) continue;
          const d = Math.hypot(cities[i].x - cities[j].x, cities[i].z - cities[j].z);
          if (d < bestD) { bestD = d; bestA = i; bestB = j; }
        }
      }
      inTree[bestB] = 1;
      addHighway(bestA, bestB, 'highway');
    }
    // Anéis extras ligando cada cidade ao seu 2º vizinho mais próximo
    for (let i = 0; i < cities.length; i++) {
      let bestJ = -1, bestD = Infinity;
      for (let j = 0; j < cities.length; j++) {
        if (i === j) continue;
        const lo = Math.min(i, j), hi = Math.max(i, j);
        if (edgeSet.has(`${lo}-${hi}`)) continue;
        const d = Math.hypot(cities[i].x - cities[j].x, cities[i].z - cities[j].z);
        if (d < bestD) { bestD = d; bestJ = j; }
      }
      if (bestJ >= 0 && bestD < preset.sizeMeters * 0.45) {
        addHighway(i, bestJ, 'avenue');
      }
    }
  }

  return {
    seed: seedInt,
    sizeKey: preset.key,
    sizeLabel: preset.label,
    sizeMeters: preset.sizeMeters,
    halfMeters: preset.halfMeters,
    chunkSize,
    chunksPerAxis: preset.chunksPerAxis,
    cities,
    lakes,
    highways
  };
}

/**
 * Consulta determinística de bioma, água, cidade mais próxima e proximidade de rodovia em (x, z).
 */
export function sampleMacroTerrain(macroMap, x, z) {
  if (!macroMap) {
    return { biome: 'plains', isWater: false, height: 0, nearestCity: null, cityDist: Infinity, highwayDist: Infinity };
  }
  const seed = macroMap.seed;

  // 1. Checa lagos (água)
  let isWater = false;
  for (let i = 0; i < macroMap.lakes.length; i++) {
    const lk = macroMap.lakes[i];
    const nx = (x - lk.x) / lk.rx;
    const nz = (z - lk.z) / lk.rz;
    const n2 = nx * nx + nz * nz;
    if (n2 < 0.88) {
      isWater = true;
      break;
    }
  }

  // 2. Cidade mais próxima
  let nearestCity = null;
  let cityDist = Infinity;
  for (let i = 0; i < macroMap.cities.length; i++) {
    const c = macroMap.cities[i];
    const d = Math.hypot(x - c.x, z - c.z);
    if (d < cityDist) { cityDist = d; nearestCity = c; }
  }

  // 3. Rodovia principal mais próxima
  let highwayDistSq = Infinity;
  for (let i = 0; i < macroMap.highways.length; i++) {
    const pts = macroMap.highways[i].pts;
    for (let k = 1; k < pts.length; k++) {
      const d2 = _ptSegDistSq(x, z, pts[k - 1][0], pts[k - 1][1], pts[k][0], pts[k][1]);
      if (d2 < highwayDistSq) highwayDistSq = d2;
    }
  }
  const highwayDist = Math.sqrt(highwayDistSq);

  // 4. Bioma & elevação suave (mantemos y = 0 plano para compatibilidade imediata de física/carros nos chunks)
  const moisture = _fbm2D(seed + 4099, x * 0.0014, z * 0.0014);
  const elevNoise = _fbm2D(seed + 8191, x * 0.0011, z * 0.0011);

  let biome = 'plains';
  if (isWater) {
    biome = 'water';
  } else if (nearestCity && cityDist < nearestCity.radius * 0.72) {
    biome = 'urban';
  } else if (nearestCity && cityDist < nearestCity.radius * 1.18) {
    biome = 'suburb';
  } else if (moisture > 0.54) {
    biome = 'forest';
  } else if (elevNoise > 0.66) {
    biome = 'hills';
  }

  return {
    biome,
    isWater,
    height: isWater ? -0.45 : 0,
    nearestCity,
    cityDist,
    highwayDist
  };
}

/**
 * Gera o blueprint 100% determinístico de um chunk (cx, cz) a partir do Macro-Mapa + hash inteiro.
 * Mesmos prédios, ruas, postes, árvores e pontos de loot para todos os jogadores na mesma seed!
 */
export function generateChunkBlueprint(macroMap, cx, cz) {
  const cs = macroMap.chunkSize || 64;
  const originX = cx * cs;
  const originZ = cz * cs;
  const centerX = originX + cs * 0.5;
  const centerZ = originZ + cs * 0.5;
  const key = chunkKey(cx, cz);
  const chunkSeed = hashInt32(macroMap.seed, cx, cz);
  const rng = createDeterministicRng(chunkSeed);

  const sample = sampleMacroTerrain(macroMap, centerX, centerZ);
  const isUrban = sample.biome === 'urban';
  const isSuburb = sample.biome === 'suburb';
  const isForest = sample.biome === 'forest';
  const isWater = sample.isWater;

  const roads = [];
  const buildings = [];
  const trees = [];
  const lamps = [];
  const lootSpots = [];
  const vehicleSpots = [];
  const zombieSpots = [];

  if (isWater) {
    return { cx, cz, key, chunkSeed, originX, originZ, centerX, centerZ, biome: 'water', isWater: true, roads, buildings, trees, lamps, lootSpots, vehicleSpots, zombieSpots };
  }

  // 1. Malha viária local do chunk:
  // Em áreas urbanas/suburbanas, todo chunk tem ruas limpas nas bordas (ou cruzamento central) conectando perfeitamente com os chunks vizinhos!
  const hasNsRoad = isUrban || isSuburb || (cx % 3 === 0);
  const hasEwRoad = isUrban || isSuburb || (cz % 3 === 0);
  const roadW = isUrban ? 10.0 : (isSuburb ? 8.2 : 7.6);
  const sideW = isUrban ? 1.8 : (isSuburb ? 1.4 : 0);

  if (hasNsRoad) {
    roads.push({ axis: 'ns', x: centerX, z: centerZ, len: cs, width: roadW, sideW });
  }
  if (hasEwRoad) {
    roads.push({ axis: 'ew', x: centerX, z: centerZ, len: cs, width: roadW, sideW });
  }

  // Checa se alguma rodovia do macro-mapa cruza este chunk
  const halfDiag = cs * 0.75;
  for (let i = 0; i < macroMap.highways.length; i++) {
    const hw = macroMap.highways[i];
    for (let k = 1; k < hw.pts.length; k++) {
      const a = hw.pts[k - 1], b = hw.pts[k];
      const d2 = _ptSegDistSq(centerX, centerZ, a[0], a[1], b[0], b[1]);
      if (d2 <= halfDiag * halfDiag) {
        roads.push({ axis: 'macro', ax: a[0], az: a[1], bx: b[0], bz: b[1], width: hw.width || 11.0, name: hw.name });
        break;
      }
    }
  }

  // 2. Postes de iluminação nas calçadas das ruas urbanas/suburbanas
  if (isUrban || isSuburb) {
    const off = roadW * 0.5 + 0.65;
    if (hasNsRoad) {
      lamps.push({ x: centerX - off, y: 0.14, z: originZ + 14, yaw: Math.PI * 0.5 });
      lamps.push({ x: centerX + off, y: 0.14, z: originZ + cs - 14, yaw: -Math.PI * 0.5 });
    }
    if (hasEwRoad) {
      lamps.push({ x: originX + 14, y: 0.14, z: centerZ - off, yaw: 0 });
      lamps.push({ x: originX + cs - 14, y: 0.14, z: centerZ + off, yaw: Math.PI });
    }
  }

  // 3. Construções nos 4 quadrantes do chunk (alinhadas às ruas, sem nunca invadir o asfalto!)
  const quadOffsets = [
    { qx: -1, qz: -1, dirToNs: 1, dirToEw: 0 },
    { qx:  1, qz: -1, dirToNs: 3, dirToEw: 0 },
    { qx: -1, qz:  1, dirToNs: 1, dirToEw: 2 },
    { qx:  1, qz:  1, dirToNs: 3, dirToEw: 2 }
  ];
  const CARDINAL_YAWS_LOCAL = [0, Math.PI * 0.5, Math.PI, -Math.PI * 0.5];
  const cityLabel = sample.nearestCity ? sample.nearestCity.name.toUpperCase() : 'KNOX';

  for (let qi = 0; qi < quadOffsets.length; qi++) {
    const q = quadOffsets[qi];
    const bx = centerX + q.qx * 18.5;
    const bz = centerZ + q.qz * 18.5;
    const densityChance = isUrban ? 0.88 : (isSuburb ? 0.62 : (isForest ? 0.08 : 0.16));
    if (rng() > densityChance) continue;

    const dir = (hasNsRoad && (!hasEwRoad || rng() < 0.5)) ? q.dirToNs : q.dirToEw;
    const rotY = CARDINAL_YAWS_LOCAL[dir];
    const roll = rng();
    let prefab = 'house';
    let label = '';

    if (isUrban) {
      if (roll < 0.04) { prefab = 'hospital'; label = `HOSPITAL ${cityLabel}`; }
      else if (roll < 0.08) { prefab = 'police'; label = `DELEGACIA ${cityLabel}`; }
      else if (roll < 0.13) { prefab = 'supermarket'; label = `MERCADO ${cityLabel}`; }
      else if (roll < 0.18) { prefab = 'pharmacy'; label = 'FARMÁCIA 24H'; }
      else if (roll < 0.22) { prefab = 'bank'; label = 'BANCO KNOX'; }
      else if (roll < 0.26) { prefab = 'gas'; label = 'POSTO KNOX'; }
      else if (roll < 0.30) { prefab = 'church'; label = 'IGREJA LOCAL'; }
      else if (roll < 0.34) { prefab = 'public'; label = `PREFEITURA ${cityLabel}`; }
      else if (roll < 0.54) { prefab = 'building'; label = `EDIFÍCIO ${cityLabel}`; }
      else if (roll < 0.72) { prefab = 'shop'; label = 'COMÉRCIO'; }
      else { prefab = 'house'; }
    } else if (isSuburb) {
      if (roll < 0.08) { prefab = 'shop'; label = 'MERCEARIA'; }
      else if (roll < 0.13) { prefab = 'gas'; label = 'POSTO LOCAL'; }
      else if (roll < 0.18) { prefab = 'pharmacy'; label = 'DROGARIA'; }
      else if (roll < 0.24) { prefab = 'building'; label = 'RESIDENCIAL'; }
      else { prefab = 'house'; }
    } else {
      prefab = roll < 0.18 ? 'gas' : 'house';
      if (prefab === 'gas') label = 'POSTO DE ESTRADA';
    }

    buildings.push({
      id: `b_${cx}_${cz}_${qi}`,
      x: +bx.toFixed(1),
      z: +bz.toFixed(1),
      dir,
      rotY,
      prefab,
      floors: prefab === 'building' ? (2 + ((rng() * 2) | 0)) : (rng() < 0.3 ? 2 : 1),
      highTier: isUrban || prefab === 'police' || prefab === 'hospital' || rng() < 0.25,
      seed: ((rng() * 999999) | 0) + 1,
      name: label
    });
  }

  // 4. Árvores (densas em floresta, moderadas em planícies/subúrbios, nunca sobre estradas/casas)
  const treeTarget = isForest ? 14 : (sample.biome === 'plains' || sample.biome === 'hills' ? 7 : (isSuburb ? 4 : 2));
  for (let ti = 0; ti < treeTarget; ti++) {
    const tx = originX + 5 + rng() * (cs - 10);
    const tz = originZ + 5 + rng() * (cs - 10);
    if (hasNsRoad && Math.abs(tx - centerX) < roadW * 0.5 + sideW + 3.2) continue;
    if (hasEwRoad && Math.abs(tz - centerZ) < roadW * 0.5 + sideW + 3.2) continue;
    let blocked = false;
    for (let bi = 0; bi < buildings.length; bi++) {
      if (Math.hypot(tx - buildings[bi].x, tz - buildings[bi].z) < 12.5) { blocked = true; break; }
    }
    if (blocked) continue;
    trees.push({ x: +tx.toFixed(1), z: +tz.toFixed(1), scale: +(0.85 + rng() * 0.6).toFixed(2), kind: rng() < 0.55 ? 1 : 0 });
  }

  // 5. Pontos de loot de rua/calçada (determinísticos, com UID estável por chunk para diffs persistentes!)
  const lootCount = isUrban ? 3 : (isSuburb ? 2 : (buildings.length > 0 ? 1 : 0));
  for (let li = 0; li < lootCount; li++) {
    const side = li % 2 === 0 ? -1 : 1;
    const lx = hasNsRoad ? (centerX + side * (roadW * 0.5 + 0.9)) : (originX + 16 + rng() * 32);
    const lz = originZ + 12 + rng() * (cs - 24);
    lootSpots.push({
      uid: `ch_${cx}_${cz}_l${li}`,
      x: +lx.toFixed(1),
      y: 0.06,
      z: +lz.toFixed(1),
      highTier: isUrban && li === 0
    });
  }

  // 6. Veículo estacionado ocasional na via (1 em cada ~5 chunks urbanos/rodoviários)
  if ((hasNsRoad || hasEwRoad) && rng() < (isUrban ? 0.24 : 0.14)) {
    const styleIdx = (rng() * 6) | 0; // inclui carros e motos!
    const vx = hasNsRoad ? (centerX + (rng() < 0.5 ? -2.6 : 2.6)) : (originX + 18 + rng() * 28);
    const vz = hasNsRoad ? (originZ + 16 + rng() * 32) : (centerZ + (rng() < 0.5 ? -2.6 : 2.6));
    const vyaw = hasNsRoad ? (rng() < 0.5 ? 0 : Math.PI) : (rng() < 0.5 ? Math.PI * 0.5 : -Math.PI * 0.5);
    vehicleSpots.push({ id: `veh_${cx}_${cz}`, x: +vx.toFixed(1), z: +vz.toFixed(1), yaw: vyaw, styleIdx });
  }

  // 7. Spawns de zumbis proporcionais ao risco da região (cidade grande = mais zumbis; interior = calmo)
  const zTarget = isUrban ? (2 + ((rng() * 3) | 0)) : (isSuburb ? (1 + ((rng() * 2) | 0)) : (rng() < 0.35 ? 1 : 0));
  for (let zi = 0; zi < zTarget; zi++) {
    const zx = centerX + (rng() - 0.5) * 28;
    const zz = centerZ + (rng() - 0.5) * 28;
    zombieSpots.push({ id: `zc_${cx}_${cz}_${zi}`, x: +zx.toFixed(1), z: +zz.toFixed(1) });
  }

  return {
    cx, cz, key, chunkSeed, originX, originZ, centerX, centerZ,
    biome: sample.biome,
    isWater: false,
    roads, buildings, trees, lamps, lootSpots, vehicleSpots, zombieSpots
  };
}

/**
 * Valida e ajusta um ponto de nascimento no mapa (garante terra firme, fora de água/prédios,
 * dentro dos limites e opcionalmente respeitando distância mínima de jogadores não aliados).
 */
export function validateSpawnPoint(macroMap, rawX, rawZ, opts = {}) {
  const halfLim = macroMap ? (macroMap.halfMeters - 48) : (opts.halfMeters || 450);
  const clamp = (v) => Math.max(-halfLim, Math.min(halfLim, v));
  const buildings = opts.buildings || [];
  const enemySpawns = opts.enemySpawns || [];
  const minEnemyDist = opts.minEnemyDist || 0;
  const minEnemySq = minEnemyDist * minEnemyDist;

  const isSpotSafe = (x, z) => {
    if (Math.abs(x) > halfLim || Math.abs(z) > halfLim) return false;
    if (macroMap) {
      const s = sampleMacroTerrain(macroMap, x, z);
      if (s.isWater) return false;
      // Verifica prédios determinísticos do chunk onde o ponto cai
      const { cx, cz } = worldToChunk(x, z, macroMap.chunkSize || 64);
      const bp = generateChunkBlueprint(macroMap, cx, cz);
      for (let i = 0; i < bp.buildings.length; i++) {
        const b = bp.buildings[i];
        if ((x - b.x) * (x - b.x) + (z - b.z) * (z - b.z) < 12.5 * 12.5) return false;
      }
    }
    for (let i = 0; i < buildings.length; i++) {
      const b = buildings[i];
      const rad = (b.r || 9) + 3.0;
      if ((x - b.x) * (x - b.x) + (z - b.z) * (z - b.z) < rad * rad) return false;
    }
    if (minEnemyDist > 0) {
      for (let i = 0; i < enemySpawns.length; i++) {
        const e = enemySpawns[i];
        if ((x - e.x) * (x - e.x) + (z - e.z) * (z - e.z) < minEnemySq) return false;
      }
    }
    return true;
  };

  const sx = clamp(Number(rawX) || 0);
  const sz = clamp(Number(rawZ) || 0);
  if (isSpotSafe(sx, sz)) {
    const info = macroMap ? sampleMacroTerrain(macroMap, sx, sz) : null;
    return { x: +sx.toFixed(1), z: +sz.toFixed(1), adjusted: false, region: info?.nearestCity?.name || 'Área Aberta', biome: info?.biome || 'urban' };
  }

  // Busca em espiral determinística o ponto válido mais próximo
  const dirs = [[1, 0], [0, 1], [-1, 0], [0, -1], [0.707, 0.707], [-0.707, 0.707], [-0.707, -0.707], [0.707, -0.707]];
  for (let rad = 14; rad <= 420; rad += 16) {
    for (let di = 0; di < dirs.length; di++) {
      const tx = clamp(sx + dirs[di][0] * rad);
      const tz = clamp(sz + dirs[di][1] * rad);
      if (isSpotSafe(tx, tz)) {
        const info = macroMap ? sampleMacroTerrain(macroMap, tx, tz) : null;
        return { x: +tx.toFixed(1), z: +tz.toFixed(1), adjusted: true, region: info?.nearestCity?.name || 'Área Aberta', biome: info?.biome || 'urban' };
      }
    }
  }

  // Último fallback seguro: centro da primeira cidade (eixo de rua)
  const fx = macroMap && macroMap.cities[0] ? macroMap.cities[0].x : 0;
  const fz = macroMap && macroMap.cities[0] ? macroMap.cities[0].z : 0;
  return { x: fx, z: fz, adjusted: true, region: macroMap?.cities[0]?.name || 'Centro', biome: 'urban' };
}

/* ============================================================================
   ATUALIZAÇÃO 2 & 3 — REGRAS CONFIGURÁVEIS, SÍNTESE OSM, MERGE DE POIs MÉDICOS,
   PVP DAYZ, MIRA EM VEÍCULOS, RECUO POR MOLA, MORTES CONTEXTUAIS & BALÍSTICA
   ============================================================================ */

export const FILL_RULES = {
  fillBuildingsOnStreetsOnly: true,
  fillCellSize: 100,
  minStreetLengthPerCell: 60,
  keepOsmBuildingsUntouched: true,
  buildingMix: { house: 0.60, building: 0.25, shop: 0.10, warehouse: 0.05 }
};

export const POI_MERGE = {
  hospital: {
    tags: ['hospital', 'upa', 'clinic_emergency', 'pronto_socorro'],
    radius: 150,
    minCount: 3,
    maxScale: 2.5
  },
  pharmacy: {
    tags: ['pharmacy', 'drugstore', 'farmacia'],
    radius: 120,
    minCount: 3,
    maxScale: 2.0
  }
};

export const PVP_CONFIG = {
  hitFeedbackOnPlayers: false,
  hitFeedbackOnZombies: true,
  showRemoteBloodOnHit: false
};

export const VEHICLE_SHOOTING = {
  motorcycle: {
    driver: false,
    passenger: true,
    passengerArc: { yaw: 160, pitchUp: 35, pitchDown: 40 }
  },
  car: {
    driver: false,
    passenger: true,
    passengerArc: { yaw: 120, pitchUp: 30, pitchDown: 30 }
  }
};

function _normalizeAngleRad(a) {
  let r = (a + Math.PI) % (Math.PI * 2);
  if (r < 0) r += Math.PI * 2;
  return r - Math.PI;
}

/**
 * Classifica um prédio/POI bruto em categoria médica de POI_MERGE ('hospital' | 'pharmacy' | null).
 */
function _resolveMedicalPoiCategory(rb, mergeCfg) {
  if (!rb) return null;
  const pref = String(rb.prefab || '').toLowerCase();
  const nm = String(rb.name || '').toLowerCase();
  const tag = String(rb.amenity || rb.healthcare || rb.osmTag || '').toLowerCase();

  if (mergeCfg.hospital) {
    if (pref === 'hospital') return 'hospital';
    for (let i = 0; i < mergeCfg.hospital.tags.length; i++) {
      const t = mergeCfg.hospital.tags[i];
      if (tag === t || nm.includes(t) || nm.includes('upa ') || nm.startsWith('upa') || nm.includes('pronto socorro') || nm.includes('pronto-socorro')) {
        return 'hospital';
      }
    }
  }
  if (mergeCfg.pharmacy) {
    if (pref === 'pharmacy') return 'pharmacy';
    for (let i = 0; i < mergeCfg.pharmacy.tags.length; i++) {
      const t = mergeCfg.pharmacy.tags[i];
      if (tag === t || nm.includes(t) || nm.includes('drogaria') || nm.includes('farmácia') || nm.includes('farmacia')) {
        return 'pharmacy';
      }
    }
  }
  return null;
}

/**
 * Agrupa hospitais/UPAs e farmácias muito próximos (Union-Find determinístico)
 * em um único POI maior e central quando o grupo atinge minCount (padrão >= 3).
 * Unidades isoladas (1 ou 2) permanecem intactas.
 */
export function mergeNearbyMedicalPois(rawBuildings, opts = {}) {
  const list = Array.isArray(rawBuildings) ? rawBuildings : [];
  if (list.length < 2) {
    return { buildings: list.slice(), mergedGroups: 0, absorbedCount: 0 };
  }
  const cfg = {
    hospital: { ...POI_MERGE.hospital, ...(opts.hospital || {}) },
    pharmacy: { ...POI_MERGE.pharmacy, ...(opts.pharmacy || {}) }
  };

  // Ordenação determinística por coordenadas antes do Union-Find (mesmo resultado em qualquer cliente)
  const indexed = list.map((b, idx) => ({
    b,
    idx,
    cat: _resolveMedicalPoiCategory(b, cfg),
    x: Number(b.x) || 0,
    z: Number(b.z) || 0
  }));

  const removedIndices = new Set();
  const mergedResults = [];
  let mergedGroups = 0;
  let absorbedCount = 0;

  for (const catKey of ['hospital', 'pharmacy']) {
    const rule = cfg[catKey];
    if (!rule || rule.minCount < 2) continue;
    const members = indexed
      .filter((it) => it.cat === catKey)
      .sort((a, b) => (a.x - b.x) || (a.z - b.z) || (a.idx - b.idx));
    if (members.length < rule.minCount) continue;

    const n = members.length;
    const parent = new Int32Array(n);
    for (let i = 0; i < n; i++) parent[i] = i;
    const find = (i) => {
      while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; }
      return i;
    };
    const unite = (a, b) => {
      const ra = find(a), rb = find(b);
      if (ra !== rb) {
        if (ra < rb) parent[rb] = ra;
        else parent[ra] = rb;
      }
    };

    const rSq = rule.radius * rule.radius;
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const dx = members[i].x - members[j].x;
        const dz = members[i].z - members[j].z;
        if (dx * dx + dz * dz <= rSq) unite(i, j);
      }
    }

    const clusters = new Map();
    for (let i = 0; i < n; i++) {
      const root = find(i);
      let arr = clusters.get(root);
      if (!arr) { arr = []; clusters.set(root, arr); }
      arr.push(members[i]);
    }

    for (const cluster of clusters.values()) {
      if (cluster.length < rule.minCount) continue;
      mergedGroups++;
      absorbedCount += (cluster.length - 1);

      let sumX = 0, sumZ = 0;
      for (const m of cluster) { sumX += m.x; sumZ += m.z; }
      const cx = sumX / cluster.length;
      const cz = sumZ / cluster.length;

      // Escolhe o membro mais central (desempate por nome preenchido e tamanho/andares)
      let primary = cluster[0];
      let bestScore = Infinity;
      for (const m of cluster) {
        const d = Math.hypot(m.x - cx, m.z - cz);
        const nameBonus = (m.b.name && String(m.b.name).trim().length > 2) ? -12 : 0;
        const floorBonus = (Number(m.b.floors) || 1) * -4;
        const sc = d + nameBonus + floorBonus;
        if (sc < bestScore) { bestScore = sc; primary = m; }
      }

      for (const m of cluster) removedIndices.add(m.idx);

      const scaleFactor = Math.min(
        rule.maxScale,
        +(1 + (cluster.length - 1) * (catKey === 'hospital' ? 0.32 : 0.25)).toFixed(2)
      );
      const baseFloors = Number(primary.b.floors) || (catKey === 'hospital' ? 2 : 1);
      const mergedFloors = Math.min(catKey === 'hospital' ? 4 : 2, baseFloors + Math.min(2, Math.floor((cluster.length - 1) / 2)));
      const defaultName = catKey === 'hospital'
        ? `Complexo Hospitalar (${cluster.length} unid.)`
        : `Mega Farmácia Central (${cluster.length} unid.)`;
      const primaryName = (primary.b.name && String(primary.b.name).trim())
        ? `${String(primary.b.name).trim()}`
        : defaultName;

      mergedResults.push({
        ...primary.b,
        x: +primary.x.toFixed(1),
        z: +primary.z.toFixed(1),
        prefab: catKey,
        floors: mergedFloors,
        highTier: true,
        mergedCount: cluster.length,
        poiScale: scaleFactor,
        name: primaryName
      });
    }
  }

  const out = [];
  for (let i = 0; i < list.length; i++) {
    if (!removedIndices.has(i)) out.push(list[i]);
  }
  for (let i = 0; i < mergedResults.length; i++) out.push(mergedResults[i]);
  return { buildings: out, mergedGroups, absorbedCount };
}

/**
 * Detecta células urbanas (ex: 100x100m) com ruas mapeadas no OSM mas ZERO construções OSM,
 * e gera lotes determinísticos alinhados às ruas sem NUNCA alterar células que já possuem
 * construções OSM. Ignora rodovias/pontes/túneis/trilhas isoladas.
 */
export function synthesizeStreetOnlyBuildings(roads, osmBuildings, opts = {}) {
  const rules = { ...FILL_RULES, ...(opts.rules || opts) };
  const halfM = Number(opts.halfM) || 500;
  const worldSeed = Number(opts.worldSeed) || 1337;
  const maxGenerated = Number(opts.maxGenerated) || 260;

  if (!rules.fillBuildingsOnStreetsOnly || !Array.isArray(roads) || roads.length === 0) {
    return { generated: [], filledCells: 0, skippedOsmCells: 0 };
  }

  const cellSize = Math.max(40, Number(rules.fillCellSize) || 100);
  const minStreetLen = Math.max(15, Number(rules.minStreetLengthPerCell) || 60);
  const existing = Array.isArray(osmBuildings) ? osmBuildings : [];

  // 1. Marca TODAS as células que já possuem qualquer construção OSM (intocáveis!)
  const osmCells = new Set();
  for (let i = 0; i < existing.length; i++) {
    const b = existing[i];
    if (!b || !Number.isFinite(b.x) || !Number.isFinite(b.z)) continue;
    const cx = Math.floor(b.x / cellSize);
    const cz = Math.floor(b.z / cellSize);
    osmCells.add(`${cx},${cz}`);
  }

  // 2. Acumula segmentos de ruas elegíveis por célula (ignora rodovias/pontes/túneis/trilhas/estacionamentos)
  const ignoredClasses = new Set(['highway', 'motorway', 'trunk', 'footway', 'cycleway', 'path', 'track', 'bridleway', 'parking']);
  const cellRoadLen = new Map();
  const cellSegs = new Map();
  const allSegs = [];

  for (let ri = 0; ri < roads.length; ri++) {
    const rd = roads[ri];
    if (!rd || !Array.isArray(rd.pts) || rd.pts.length < 2) continue;
    const cls = String(rd.roadClass || 'street').toLowerCase();
    if (ignoredClasses.has(cls) || rd.bridge || rd.tunnel) continue;
    const hw = (Number(rd.width) || 8.2) * 0.5;
    const swW = cls === 'avenue' ? 2.4 : (cls === 'service' || cls === 'passage' ? 1.15 : 1.85);
    const landuse = String(rd.landuse || '').toLowerCase();

    for (let i = 1; i < rd.pts.length; i++) {
      const pA = rd.pts[i - 1], pB = rd.pts[i];
      const ax = Array.isArray(pA) ? pA[0] : pA.x;
      const az = Array.isArray(pA) ? pA[1] : pA.z;
      const bx = Array.isArray(pB) ? pB[0] : pB.x;
      const bz = Array.isArray(pB) ? pB[1] : pB.z;
      const len = Math.hypot(bx - ax, bz - az);
      if (!Number.isFinite(len) || len < 4) continue;

      const seg = {
        ax, az, bx, bz, len,
        tx: (bx - ax) / len, tz: (bz - az) / len,
        hw, swW, roadClass: cls, landuse
      };
      allSegs.push(seg);

      const midX = (ax + bx) * 0.5;
      const midZ = (az + bz) * 0.5;
      const cx = Math.floor(midX / cellSize);
      const cz = Math.floor(midZ / cellSize);
      const k = `${cx},${cz}`;
      cellRoadLen.set(k, (cellRoadLen.get(k) || 0) + len);
      let arr = cellSegs.get(k);
      if (!arr) { arr = []; cellSegs.set(k, arr); }
      arr.push(seg);
    }
  }

  // 3. Para cada célula SEM construções OSM e com >= minStreetLengthPerCell de rua, gera lotes ao longo da via
  const generated = [];
  let filledCells = 0;
  let skippedOsmCells = 0;

  const isBlocked = (x, z, rNeed) => {
    if (Math.abs(x) > halfM - 16 || Math.abs(z) > halfM - 16) return true;
    // Não pode invadir nenhuma via
    for (let i = 0; i < allSegs.length; i++) {
      const s = allSegs[i];
      const clear = s.hw + s.swW + rNeed * 0.62;
      const vx = s.bx - s.ax, vz = s.bz - s.az;
      const l2 = vx * vx + vz * vz;
      const t = l2 > 1e-4 ? Math.max(0, Math.min(1, ((x - s.ax) * vx + (z - s.az) * vz) / l2)) : 0;
      const dx = x - (s.ax + t * vx), dz = z - (s.az + t * vz);
      if (dx * dx + dz * dz < clear * clear) return true;
    }
    // Não pode sobrepor construção OSM existente
    for (let i = 0; i < existing.length; i++) {
      const eb = existing[i];
      const minD = rNeed + (eb.r || 7.2);
      if ((x - eb.x) * (x - eb.x) + (z - eb.z) * (z - eb.z) < minD * minD) return true;
    }
    // Não pode sobrepor construção gerada anteriormente
    for (let i = 0; i < generated.length; i++) {
      const gb = generated[i];
      const minD = (rNeed + gb.r) * 0.90;
      if ((x - gb.x) * (x - gb.x) + (z - gb.z) * (z - gb.z) < minD * minD) return true;
    }
    return false;
  };

  // Ordena chaves de células para determinismo absoluto
  const sortedCellKeys = Array.from(cellRoadLen.keys()).sort();
  for (let ci = 0; ci < sortedCellKeys.length && generated.length < maxGenerated; ci++) {
    const k = sortedCellKeys[ci];
    if (rules.keepOsmBuildingsUntouched && osmCells.has(k)) {
      skippedOsmCells++;
      continue;
    }
    const totalLen = cellRoadLen.get(k) || 0;
    if (totalLen < minStreetLen) continue;

    const segs = cellSegs.get(k);
    if (!segs || segs.length === 0) continue;
    const [cxStr, czStr] = k.split(',');
    const cx = Number(cxStr) || 0;
    const cz = Number(czStr) || 0;
    const cellRng = createDeterministicRng(hashInt32(worldSeed ^ 0x4b1d, cx, cz));

    const isDenseUrban = totalLen > minStreetLen * 2.8 || Math.hypot(cx * cellSize, cz * cellSize) < halfM * 0.35;
    let addedInCell = 0;

    for (let si = 0; si < segs.length && generated.length < maxGenerated; si++) {
      const seg = segs[si];
      const lotStep = seg.roadClass === 'avenue' ? 21 : 18.5;
      const samples = Math.max(1, Math.min(6, Math.floor(seg.len / lotStep)));
      const nx = -seg.tz, nz = seg.tx;

      for (let sIdx = 0; sIdx < samples && generated.length < maxGenerated; sIdx++) {
        const frac = (sIdx + 0.5) / samples;
        const mx = seg.ax + (seg.bx - seg.ax) * frac;
        const mz = seg.az + (seg.bz - seg.az) * frac;

        for (const side of [-1, 1]) {
          if (generated.length >= maxGenerated) break;
          // Variedade orgânica: deixa alguns lotes abertos (quintais/terrenos)
          if (cellRng() < 0.18) continue;

          const roll = cellRng();
          let prefab = 'house';
          if (seg.landuse === 'industrial') {
            prefab = roll < 0.55 ? 'shop' : (roll < 0.85 ? 'building' : 'house');
          } else if (seg.roadClass === 'avenue' || isDenseUrban) {
            prefab = roll < 0.42 ? 'building' : (roll < 0.72 ? 'shop' : 'house');
          } else {
            const mix = rules.buildingMix || FILL_RULES.buildingMix;
            const cHouse = mix.house ?? 0.6;
            const cApt = cHouse + (mix.building ?? mix.apartment ?? 0.25);
            const cShop = cApt + (mix.shop ?? 0.1);
            prefab = roll < cHouse ? 'house' : (roll < cApt ? 'building' : (roll < cShop ? 'shop' : 'shop'));
          }

          const rNeed = prefab === 'building' ? 8.6 : (prefab === 'shop' ? 7.4 : 6.4);
          const frontD = prefab === 'building' ? 5.8 : (prefab === 'shop' ? 4.9 : 4.8);
          const distOff = seg.hw + seg.swW + frontD + 0.65 + cellRng() * 1.15;
          const bx = +(mx + nx * side * distOff).toFixed(1);
          const bz = +(mz + nz * side * distOff).toFixed(1);

          // Garante que o lote gerado não vaze para dentro de uma célula que tem casas OSM
          const lotCellKey = `${Math.floor(bx / cellSize)},${Math.floor(bz / cellSize)}`;
          if (rules.keepOsmBuildingsUntouched && osmCells.has(lotCellKey)) continue;
          if (isBlocked(bx, bz, rNeed)) continue;

          const faceDx = -nx * side, faceDz = -nz * side;
          const rotY = +Math.atan2(faceDx, faceDz).toFixed(4);
          const dir = Math.abs(faceDx) > Math.abs(faceDz) ? (faceDx > 0 ? 1 : 3) : (faceDz > 0 ? 0 : 2);
          const floors = prefab === 'building'
            ? (2 + ((cellRng() * 3) | 0))
            : (prefab === 'shop' ? (cellRng() < 0.45 ? 2 : 1) : (cellRng() < 0.28 ? 2 : 1));

          generated.push({
            x: bx,
            z: bz,
            r: rNeed,
            dir,
            rotY,
            prefab,
            floors,
            highTier: prefab === 'building' || cellRng() < 0.22,
            seed: hashInt32(worldSeed, Math.round(bx * 10), Math.round(bz * 10)),
            name: prefab === 'building' ? 'Edifício Residencial' : (prefab === 'shop' ? 'Comércio Local' : ''),
            generated: true
          });
          addedInCell++;
        }
      }
    }
    if (addedInCell > 0) filledCells++;
  }

  return { generated, filledCells, skippedOsmCells };
}

/**
 * Restringe ângulos de mira de ocupantes de veículos (garupa de moto / passageiro de carro)
 * em espaço do mundo, respeitando VEHICLE_SHOOTING sem nunca entortar o tronco ou acumular pitch.
 */
export function clampVehicleAimAngles(isMoto, seatIdx, vehYaw, rawYaw, rawPitch, cfg = VEHICLE_SHOOTING) {
  const rules = isMoto ? (cfg.motorcycle || VEHICLE_SHOOTING.motorcycle) : (cfg.car || VEHICLE_SHOOTING.car);
  const canShoot = seatIdx === 0 ? !!rules.driver : !!rules.passenger;
  const arc = rules.passengerArc || { yaw: 140, pitchUp: 35, pitchDown: 35 };

  const deg2rad = Math.PI / 180;
  const maxUp = (arc.pitchUp || 35) * deg2rad;
  const maxDown = (arc.pitchDown || 35) * deg2rad;
  const clampedPitch = Math.max(-maxDown, Math.min(maxUp, rawPitch));

  // Em moto (garupa), arco centrado para trás/laterais ou 160° em cada lado; em carro, focado para o lado da janela
  let centerYaw = vehYaw;
  if (!isMoto && seatIdx > 0) {
    // Assentos ímpares = lado direito (-PI/2), pares > 0 = lado esquerdo (+PI/2)
    const sideSign = (seatIdx % 2 === 1) ? -1 : 1;
    centerYaw = vehYaw + sideSign * (Math.PI * 0.5);
  }
  const halfYawRad = Math.min(Math.PI, ((arc.yaw || 140) * deg2rad));
  const relYaw = _normalizeAngleRad(rawYaw - centerYaw);
  const clampedRelYaw = Math.max(-halfYawRad, Math.min(halfYawRad, relYaw));
  const clampedYaw = _normalizeAngleRad(centerYaw + clampedRelYaw);

  return {
    canShoot,
    yaw: clampedYaw,
    pitch: clampedPitch,
    clamped: Math.abs(relYaw - clampedRelYaw) > 0.001 || Math.abs(rawPitch - clampedPitch) > 0.001
  };
}

/**
 * Recuperação por mola criticamente amortecida para o offset de recuo.
 * Separa aimBase (onde o jogador mira) de recoilOffset (que sempre retorna a 0).
 */
export function stepSpringRecoil(recoilState, dt) {
  const safeDt = Math.min(0.05, Math.max(0, dt || 0));
  if (!recoilState || safeDt <= 0) return recoilState;
  const decayPitch = Math.exp(-(recoilState.recovery || 11.5) * safeDt);
  const decayYaw = Math.exp(-(recoilState.yawRecovery || 13.0) * safeDt);
  const decayKick = Math.exp(-16.0 * safeDt);

  recoilState.pitch = (recoilState.pitch || 0) * decayPitch;
  recoilState.yaw = (recoilState.yaw || 0) * decayYaw;
  recoilState.kick = (recoilState.kick || 0) * decayKick;
  recoilState.posZ = (recoilState.posZ || 0) * Math.exp(-18.0 * safeDt);
  recoilState.roll = (recoilState.roll || 0) * Math.exp(-14.0 * safeDt);

  if (Math.abs(recoilState.pitch) < 0.0002) recoilState.pitch = 0;
  if (Math.abs(recoilState.yaw) < 0.0002) recoilState.yaw = 0;
  if (Math.abs(recoilState.kick) < 0.0002) recoilState.kick = 0;
  if (Math.abs(recoilState.posZ) < 0.0001) recoilState.posZ = 0;
  if (Math.abs(recoilState.roll) < 0.0002) recoilState.roll = 0;
  return recoilState;
}

/**
 * Seleciona 1 entre 6 variantes contextuais de animação de morte (0..5) conforme
 * zona de impacto, tipo de arma, direção do disparo e semente determinística:
 *  0 = Headshot / queda seca para trás
 *  1 = Colapso frontal de joelhos (de bruços)
 *  2 = Giro lateral direito (flanco)
 *  3 = Giro lateral esquerdo (flanco oposto)
 *  4 = Empurrão forte / arremesso curto (espingarda/sniper)
 *  5 = Tropeço por tiro nas pernas
 */
export function selectContextualDeathStyle(hitZone = 'torso', opts = {}) {
  const { isShotgun = false, isSniper = false, isMelee = false, impactSideDot = 0, seed = 1 } = opts;
  const r = Math.abs(Math.floor(seed)) % 100;
  if (isShotgun || (isSniper && hitZone !== 'limb')) return 4;
  if (hitZone === 'head') return (r < 75) ? 0 : 1;
  if (hitZone === 'limb') return 5;
  if (isMelee) return (r < 60) ? 1 : 2;
  if (impactSideDot > 0.42) return 2;
  if (impactSideDot < -0.42) return 3;
  return r % 4; // 0, 1, 2 ou 3
}

/**
 * Calcula queda balística vertical (metros) em função da distância, zeroing e velocidade inicial.
 * Retorna o deslocamento Y real da bala em relação à linha de visada zerada.
 */
export function computeBallisticDrop(distMeters, zeroingMeters = 100, muzzleVelocity = 820, gravity = 9.81) {
  const d = Math.max(0, Number(distMeters) || 0);
  const z = Math.max(25, Number(zeroingMeters) || 100);
  const v = Math.max(120, Number(muzzleVelocity) || 820);
  const t = d / v;
  const tz = z / v;
  // Ângulo de elevação do zeroing compensa exatamente a queda em dist === zeroingMeters
  const dropAtD = 0.5 * gravity * t * t;
  const dropAtZ = 0.5 * gravity * tz * tz;
  const zeroComp = dropAtZ * (d / z);
  return zeroComp - dropAtD; // 0 em d===z, negativo (cai) além do zeroing
}




// Teste de segmento contra o volume horizontal expandido pelo raio do zumbi.
export function sweptVehicleContact(fromX, fromZ, toX, toZ, target, forwardX, forwardZ, spec, radius) {
  const dx = toX - fromX, dz = toZ - fromZ;
  const x = target.x - fromX, z = target.z - fromZ;
  const axes = [
    [x * forwardX + z * forwardZ, dx * forwardX + dz * forwardZ, -spec.hitLenBack - radius, spec.hitLenFront + radius],
    [-x * forwardZ + z * forwardX, -dx * forwardZ + dz * forwardX, -spec.hitHalfW - radius, spec.hitHalfW + radius]
  ];
  let enter = 0, exit = 1;
  for (const [origin, speed, min, max] of axes) {
    if (Math.abs(speed) < 1e-8) {
      if (origin < min || origin > max) return false;
      continue;
    }
    const a = (origin - max) / speed, b = (origin - min) / speed;
    enter = Math.max(enter, Math.min(a, b));
    exit = Math.min(exit, Math.max(a, b));
    if (enter > exit) return false;
  }
  return true;
}

/* ============================================================================
   PATHFINDING TÁTICO 2D DOS ZUMBIS (A* EM GRADE LOCAL + SAÍDA DE CASAS / PORTAS)
   ============================================================================ */

/**
 * Avalia se um ponto (px, pz) expandido por `radius` colide com um colisor sólido (AABB ou OBB)
 * na faixa vertical do tronco do zumbi [footY + 0.48, footY + 1.55].
 * Retorna:
 *   0 = livre
 *   1 = porta fechada arrombável (custo extra transitável)
 *   2 = janela baixa quebrável (custo extra transitável)
 *   3 = parede / obstáculo sólido intransponível
 */
export function classifyZombieObstacleAtPoint(px, pz, footY, radius, b) {
  if (!b) return 0;
  const isClosedDoor = Boolean(b.isDoorCollider && b.active);
  const isBreakableWin = Boolean(b.isWindowCollider && b.active && b.minY <= footY + 1.08);
  if (!b.active) return 0;
  if (b.maxY <= footY + 0.46 || b.minY >= footY + 1.55) return 0;

  let hit = false;
  if (b.obb) {
    const o = b.obb;
    const dx = px - o.cx, dz = pz - o.cz;
    const lx = dx * o.ux + dz * o.uz;
    const lz = dx * o.vx + dz * o.vz;
    const qx = Math.max(-o.hx, Math.min(lx, o.hx));
    const qz = Math.max(-o.hz, Math.min(lz, o.hz));
    const ex = lx - qx, ez = lz - qz;
    hit = (ex * ex + ez * ez) < (radius * radius);
  } else {
    const cx = Math.max(b.minX, Math.min(px, b.maxX));
    const cz = Math.max(b.minZ, Math.min(pz, b.maxZ));
    const dx = px - cx, dz = pz - cz;
    hit = (dx * dx + dz * dz) < (radius * radius);
  }
  if (!hit) return 0;
  if (isClosedDoor) return 1;
  if (isBreakableWin) return 2;
  return 3;
}

function sampleCellTraversalCode(px, pz, footY, radius, obstacles) {
  let worst = 0;
  for (let i = 0; i < obstacles.length; i++) {
    const code = classifyZombieObstacleAtPoint(px, pz, footY, radius, obstacles[i]);
    if (code === 3) return 3;
    if (code > worst) worst = code;
  }
  return worst;
}

/**
 * Verifica se o segmento reto (x0,z0)->(x1,z1) está 100% desobstruído (sem paredes nem portas fechadas).
 */
export function hasZombieLineOfSight(x0, z0, x1, z1, footY, obstacles, radius = 0.36) {
  const dx = x1 - x0, dz = z1 - z0;
  const dist = Math.hypot(dx, dz);
  if (dist < 0.05) return true;
  const steps = Math.max(2, Math.ceil(dist / 0.42));
  for (let s = 1; s <= steps; s++) {
    const t = s / steps;
    const sx = x0 + dx * t;
    const sz = z0 + dz * t;
    for (let i = 0; i < obstacles.length; i++) {
      if (classifyZombieObstacleAtPoint(sx, sz, footY, radius, obstacles[i]) > 0) {
        return false;
      }
    }
  }
  return true;
}

function isWalkableSegment(x0, z0, x1, z1, footY, obstacles, radius = 0.34) {
  const dx = x1 - x0, dz = z1 - z0;
  const dist = Math.hypot(dx, dz);
  if (dist < 0.05) return true;
  const steps = Math.max(2, Math.ceil(dist / 0.45));
  for (let s = 1; s < steps; s++) {
    const t = s / steps;
    const code = sampleCellTraversalCode(x0 + dx * t, z0 + dz * t, footY, radius, obstacles);
    if (code === 3) return false;
  }
  return true;
}

/**
 * Calcula o caminho mais rápido para o zumbi sair de dentro de uma casa ou contornar paredes/prédios
 * até o sobrevivente usando A* 8-direcional + suavização por linha de visada (string-pulling).
 *
 * @returns {{ direct: boolean, waypoints: Array<{x:number, z:number, breach?:boolean}> }}
 */
export function findZombieTacticalPath(startX, startZ, goalX, goalZ, footY, obstacles, opts = {}) {
  const radius = opts.radius ?? 0.35;
  if (!obstacles || obstacles.length === 0 || hasZombieLineOfSight(startX, startZ, goalX, goalZ, footY, obstacles, radius)) {
    return { direct: true, waypoints: [{ x: goalX, z: goalZ }] };
  }

  const cell = opts.cellSize ?? 1.05;
  const halfGrid = opts.halfGridCells ?? 26; // Janela ~54m x 54m centrada no zumbi
  const gridSpan = halfGrid * 2 + 1;
  const maxExpanded = opts.maxExpanded ?? 560;

  // Clampa o alvo na borda da janela caso o jogador esteja muito longe (> 27m)
  const rawGdx = goalX - startX, rawGdz = goalZ - startZ;
  let gx = Math.round(rawGdx / cell);
  let gz = Math.round(rawGdz / cell);
  const maxCoord = halfGrid - 1;
  if (Math.abs(gx) > maxCoord || Math.abs(gz) > maxCoord) {
    const scale = maxCoord / Math.max(Math.abs(gx), Math.abs(gz));
    gx = Math.round(gx * scale);
    gz = Math.round(gz * scale);
  }

  const toIdx = (ix, iz) => (iz + halfGrid) * gridSpan + (ix + halfGrid);
  const worldX = (ix) => startX + ix * cell;
  const worldZ = (iz) => startZ + iz * cell;

  // Cache preguiçoso de código de colisão por célula
  const cellCache = new Int8Array(gridSpan * gridSpan);
  cellCache.fill(-1);
  const getCellCode = (ix, iz) => {
    if (ix === 0 && iz === 0) return 0; // célula inicial sempre liberada para permitir sair se encostado na parede
    const id = toIdx(ix, iz);
    let c = cellCache[id];
    if (c === -1) {
      c = sampleCellTraversalCode(worldX(ix), worldZ(iz), footY, radius, obstacles);
      cellCache[id] = c;
    }
    return c;
  };

  // Se a célula final cair exatamente dentro de uma parede grossa, procura a célula vizinha livre mais próxima
  if (getCellCode(gx, gz) === 3) {
    let foundNear = false;
    for (let r = 1; r <= 3 && !foundNear; r++) {
      let bestD = Infinity, bIx = gx, bIz = gz;
      for (let dz = -r; dz <= r; dz++) {
        for (let dx = -r; dx <= r; dx++) {
          const nx = gx + dx, nz = gz + dz;
          if (nx < -halfGrid || nx > halfGrid || nz < -halfGrid || nz > halfGrid) continue;
          if (getCellCode(nx, nz) < 3) {
            const d2 = (worldX(nx) - goalX) ** 2 + (worldZ(nz) - goalZ) ** 2;
            if (d2 < bestD) { bestD = d2; bIx = nx; bIz = nz; foundNear = true; }
          }
        }
      }
      if (foundNear) { gx = bIx; gz = bIz; }
    }
  }

  const totalCells = gridSpan * gridSpan;
  const gScore = new Float32Array(totalCells);
  gScore.fill(1e9);
  const parent = new Int32Array(totalCells);
  parent.fill(-1);
  const closed = new Uint8Array(totalCells);

  // Min-heap binário enxuto sobre índices de célula
  const heapNodes = [];
  const heapF = [];
  const heapPush = (nodeIdx, fVal) => {
    let i = heapNodes.length;
    heapNodes.push(nodeIdx);
    heapF.push(fVal);
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (heapF[p] <= fVal) break;
      heapNodes[i] = heapNodes[p]; heapF[i] = heapF[p];
      i = p;
    }
    heapNodes[i] = nodeIdx; heapF[i] = fVal;
  };
  const heapPop = () => {
    const top = heapNodes[0];
    const lastN = heapNodes.pop();
    const lastF = heapF.pop();
    const len = heapNodes.length;
    if (len > 0) {
      let i = 0;
      while (true) {
        const l = (i << 1) + 1, r = l + 1;
        let sm = i;
        if (l < len && heapF[l] < (sm === i ? lastF : heapF[sm])) sm = l;
        if (r < len && heapF[r] < (sm === i ? lastF : heapF[sm])) sm = r;
        if (sm === i) break;
        heapNodes[i] = heapNodes[sm]; heapF[i] = heapF[sm];
        i = sm;
      }
      heapNodes[i] = lastN; heapF[i] = lastF;
    }
    return top;
  };

  const heuristic = (ix, iz) => Math.hypot(goalX - worldX(ix), goalZ - worldZ(iz)) / cell;
  const startIdx = toIdx(0, 0);
  const goalIdx = toIdx(gx, gz);
  gScore[startIdx] = 0;
  heapPush(startIdx, heuristic(0, 0));

  let bestPartialIdx = startIdx;
  let bestPartialH = heuristic(0, 0);
  let expanded = 0;
  let reachedGoal = false;

  const DIRS = [
    [1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0],
    [1, 1, 1.4142], [1, -1, 1.4142], [-1, 1, 1.4142], [-1, -1, 1.4142]
  ];

  while (heapNodes.length > 0 && expanded < maxExpanded) {
    const cur = heapPop();
    if (closed[cur]) continue;
    closed[cur] = 1;
    expanded++;

    if (cur === goalIdx) {
      reachedGoal = true;
      bestPartialIdx = cur;
      break;
    }

    const czIdx = Math.floor(cur / gridSpan) - halfGrid;
    const cxIdx = (cur % gridSpan) - halfGrid;
    const curH = heuristic(cxIdx, czIdx);
    if (cur !== startIdx && curH < bestPartialH) {
      bestPartialH = curH;
      bestPartialIdx = cur;
    }

    const baseG = gScore[cur];
    for (let d = 0; d < 8; d++) {
      const dx = DIRS[d][0], dz = DIRS[d][1];
      const nx = cxIdx + dx, nz = czIdx + dz;
      if (nx < -halfGrid || nx > halfGrid || nz < -halfGrid || nz > halfGrid) continue;
      const nIdx = toIdx(nx, nz);
      if (closed[nIdx]) continue;

      const code = getCellCode(nx, nz);
      if (code === 3) continue;

      // Impede cortar quina diagonal atravessando parede sólida adjacente!
      if (dx !== 0 && dz !== 0) {
        if (getCellCode(cxIdx + dx, czIdx) === 3 || getCellCode(cxIdx, czIdx + dz) === 3) continue;
      }

      // Porta fechada tem leve penalidade (+2.4 células) -> prefere porta aberta próxima, mas usa porta fechada se for o jeito rápido de sair!
      // Janela baixa tem penalidade (+3.6 células) -> prefere portas, mas estilhaça janela se trancado!
      const penalty = code === 1 ? 2.4 : (code === 2 ? 3.6 : 0.0);
      const tentativeG = baseG + DIRS[d][2] + penalty;
      if (tentativeG < gScore[nIdx]) {
        gScore[nIdx] = tentativeG;
        parent[nIdx] = cur;
        heapPush(nIdx, tentativeG + heuristic(nx, nz) * 1.08);
      }
    }
  }

  if (bestPartialIdx === startIdx) {
    return { direct: false, waypoints: [{ x: goalX, z: goalZ }] };
  }

  // Reconstrói cadeia bruta de células do destino até a origem
  const rawPts = [];
  let trace = bestPartialIdx;
  while (trace !== -1 && trace !== startIdx) {
    const tz = Math.floor(trace / gridSpan) - halfGrid;
    const tx = (trace % gridSpan) - halfGrid;
    const cCode = cellCache[trace];
    rawPts.push({ x: worldX(tx), z: worldZ(tz), breach: cCode === 1 || cCode === 2 });
    trace = parent[trace];
  }
  rawPts.reverse();
  if (reachedGoal && Math.hypot(goalX - worldX(gx), goalZ - worldZ(gz)) < cell * 2.2) {
    rawPts.push({ x: goalX, z: goalZ, breach: false });
  }

  // String-pulling (suavização): conecta waypoints distantes em linha reta quando não há parede sólida nem porta fechada no meio
  const smooth = [];
  let anchorX = startX, anchorZ = startZ;
  let i = 0;
  while (i < rawPts.length) {
    if (rawPts[i].breach) {
      smooth.push(rawPts[i]);
      anchorX = rawPts[i].x;
      anchorZ = rawPts[i].z;
      i++;
      continue;
    }
    let furthest = i;
    for (let j = i + 1; j < rawPts.length; j++) {
      if (rawPts[j].breach) break;
      if (isWalkableSegment(anchorX, anchorZ, rawPts[j].x, rawPts[j].z, footY, obstacles, radius * 0.92)
          && hasZombieLineOfSight(anchorX, anchorZ, rawPts[j].x, rawPts[j].z, footY, obstacles, radius * 0.88)) {
        furthest = j;
      }
    }
    smooth.push(rawPts[furthest]);
    anchorX = rawPts[furthest].x;
    anchorZ = rawPts[furthest].z;
    i = furthest + 1;
  }

  return { direct: false, waypoints: smooth.length > 0 ? smooth : [{ x: goalX, z: goalZ }] };
}

/**
 * Seleciona o clip esquelético e modo de animação de um zumbi vivo.
 * Regra invariante: se `legHit` for verdadeiro (zumbi rastejando no chão),
 * ele NUNCA retorna clip em pé ('attack', 'hit', 'idle', 'walk', 'run') —
 * permanece sempre em 'crawl' e usa overlay procedural no chão para atacar/sofrer dano.
 */
export function selectZombieAnimState({
  legHit = false,
  atkAnimT = 0,
  stagger = 0,
  moveSpd = 0,
  isChasing = false,
  archetype = 0
} = {}) {
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  if (legHit) {
    if (atkAnimT > 0) {
      return { clip: 'crawl', mode: 'crawl_attack', fade: 0.12, timeScale: 0.25 };
    }
    if (stagger > 0) {
      return { clip: 'crawl', mode: 'crawl_hit', fade: 0.10, timeScale: 0.14 };
    }
    if (moveSpd > 0.08) {
      return { clip: 'crawl', mode: 'crawl_move', fade: 0.16, timeScale: clamp(moveSpd / 0.95, 0.75, 1.65) };
    }
    return { clip: 'crawl', mode: 'crawl_idle', fade: 0.18, timeScale: 0.08 };
  }

  if (atkAnimT > 0) {
    return { clip: 'attack', mode: 'attack', fade: 0.08, timeScale: 1.25 };
  }
  if (stagger > 0) {
    return { clip: 'hit', mode: 'hit', fade: 0.06, timeScale: 1.3 };
  }
  if (moveSpd > 0.25 && isChasing) {
    const useRun = archetype === 1 || moveSpd > 1.45;
    return {
      clip: useRun ? 'run' : 'walk',
      mode: useRun ? 'run' : 'walk',
      fade: 0.14,
      timeScale: clamp(moveSpd / (useRun ? 2.5 : 1.35), 0.78, 1.85)
    };
  }
  if (moveSpd > 0.12) {
    return { clip: 'walk', mode: 'walk', fade: 0.18, timeScale: clamp(moveSpd / 1.25, 0.55, 1.35) };
  }
  return { clip: 'idle', mode: 'idle', fade: 0.22, timeScale: 1.0 };
}


