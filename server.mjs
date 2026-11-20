import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const apiServersHandler = require('./api/servers.js');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.glb': 'model/gltf-binary',
  '.gltf': 'model/gltf+json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.fbx': 'application/octet-stream'
};

const PORT = Number(process.env.PORT) || 3000;
const HOST = '0.0.0.0';

// Cache autoritativo de World Blueprints (Host -> Servidor -> Clientes)
// Permite que clientes carreguem o mapa real 100% idêntico ao Host SEM precisar de API Key do Google Maps!
const worldBlueprints = new Map();
const MAX_WORLDS = 24;
const WORLD_TTL_MS = 2 * 60 * 60 * 1000;

function pruneWorlds() {
  const now = Date.now();
  for (const [id, entry] of worldBlueprints.entries()) {
    if (now - entry.updatedAt > WORLD_TTL_MS) worldBlueprints.delete(id);
  }
  while (worldBlueprints.size > MAX_WORLDS) {
    const oldestKey = worldBlueprints.keys().next().value;
    if (!oldestKey) break;
    worldBlueprints.delete(oldestKey);
  }
}

function readDotEnvKey() {
  const candidates = ['.env.local', '.env'];
  const keys = ['GOOGLE_MAPS_API_KEY', 'VITE_GOOGLE_MAPS_API_KEY', 'MAPS_API_KEY'];
  for (const k of keys) {
    if (process.env[k] && process.env[k].trim()) return process.env[k].trim();
  }
  for (const file of candidates) {
    try {
      const full = path.join(__dirname, file);
      if (!fs.existsSync(full)) continue;
      const text = fs.readFileSync(full, 'utf8');
      for (const line of text.split(/\r?\n/)) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const idx = trimmed.indexOf('=');
        if (idx === -1) continue;
        const name = trimmed.slice(0, idx).trim();
        let val = trimmed.slice(idx + 1).trim();
        if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
          val = val.slice(1, -1);
        }
        if (keys.includes(name) && val) return val;
      }
    } catch {}
  }
  return '';
}

function readRequestBody(req, maxBytes = 6 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on('data', (chunk) => {
      total += chunk.length;
      if (total > maxBytes) {
        reject(new Error('Payload too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function sendJson(res, status, obj) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*'
  });
  res.end(JSON.stringify(obj));
}

function latLngToLocalXZ(lat, lng, cLat, cLng) {
  const cosLat = Math.max(0.15, Math.cos((cLat * Math.PI) / 180));
  return {
    x: +((lng - cLng) * 111320 * cosLat).toFixed(2),
    z: +(-(lat - cLat) * 110540).toFixed(2)
  };
}

function getBoundsSquare(lat, lng, areaKm2) {
  const halfM = Math.sqrt(Math.max(0.25, Math.min(4.0, Number(areaKm2) || 1.0))) * 500;
  const dLat = halfM / 110540;
  const cosLat = Math.max(0.15, Math.cos((lat * Math.PI) / 180));
  const dLng = halfM / (111320 * cosLat);
  return {
    north: lat + dLat,
    south: lat - dLat,
    east: lng + dLng,
    west: lng - dLng,
    halfM,
    sideM: halfM * 2
  };
}

async function fetchOpenMeteoElevationGrid(sq, gridN = 21) {
  const locs = [];
  for (let iz = 0; iz < gridN; iz++) {
    const fz = iz / (gridN - 1);
    const lat = sq.north - fz * (sq.north - sq.south);
    for (let ix = 0; ix < gridN; ix++) {
      const fx = ix / (gridN - 1);
      const lng = sq.west + fx * (sq.east - sq.west);
      locs.push({ lat: +lat.toFixed(5), lng: +lng.toFixed(5) });
    }
  }

  const batchSize = 95;
  const batches = [];
  for (let i = 0; i < locs.length; i += batchSize) {
    batches.push(locs.slice(i, i + batchSize));
  }

  const results = await Promise.all(
    batches.map(async (batch) => {
      const lats = batch.map((p) => p.lat).join(',');
      const lngs = batch.map((p) => p.lng).join(',');
      const url = `https://api.open-meteo.com/v1/elevation?latitude=${lats}&longitude=${lngs}`;
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 9000);
      try {
        const resp = await fetch(url, {
          signal: ctrl.signal,
          headers: { 'User-Agent': 'KnoxSurvival3D/1.0' }
        });
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        const data = await resp.json();
        if (Array.isArray(data.elevation) && data.elevation.length === batch.length) {
          return data.elevation.map((v) => Number(v) || 0);
        }
        throw new Error('Invalid elevation batch');
      } finally {
        clearTimeout(timer);
      }
    })
  );

  const raw = results.flat();
  let sum = 0, minElev = Infinity, maxElev = -Infinity;
  for (const e of raw) {
    sum += e;
    if (e < minElev) minElev = e;
    if (e > maxElev) maxElev = e;
  }
  const meanElev = raw.length ? sum / raw.length : 0;
  return { gridN, rawElevs: raw, minElev, maxElev, meanElev };
}

async function fetchOsmApiV06Bbox(west, south, east, north, timeoutMs = 12000) {
  const bbox = `${west.toFixed(6)},${south.toFixed(6)},${east.toFixed(6)},${north.toFixed(6)}`;
  const url = `https://api.openstreetmap.org/api/0.6/map.json?bbox=${bbox}`;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const resp = await fetch(url, {
      signal: ctrl.signal,
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'KnoxSurvival3D/1.0 (RealWorldProcedural)'
      }
    });
    if (!resp.ok) {
      const err = new Error(`OSM v0.6 HTTP ${resp.status}`);
      err.status = resp.status;
      throw err;
    }
    const data = await resp.json();
    if (!data || !Array.isArray(data.elements)) {
      throw new Error('OSM v0.6 invalid JSON');
    }
    return data.elements;
  } finally {
    clearTimeout(timer);
  }
}

async function fetchOsmElementsViaV06(sq) {
  const trySingle = sq.sideM <= 1150;
  if (trySingle) {
    try {
      return await fetchOsmApiV06Bbox(sq.west, sq.south, sq.east, sq.north, 12000);
    } catch (err) {
      if (err.status !== 400) throw err;
      // HTTP 400 = >50k nodes (megacidade muito densa) -> divide em 2x2 quadrantes!
    }
  }
  const midLat = (sq.south + sq.north) * 0.5;
  const midLng = (sq.west + sq.east) * 0.5;
  const quads = [
    [sq.west, sq.south, midLng, midLat],
    [midLng, sq.south, sq.east, midLat],
    [sq.west, midLat, midLng, sq.north],
    [midLng, midLat, sq.east, sq.north]
  ];
  const settled = await Promise.allSettled(
    quads.map(([w, s, e, n]) => fetchOsmApiV06Bbox(w, s, e, n, 12000))
  );
  const dedup = new Map();
  let okCount = 0;
  for (const res of settled) {
    if (res.status === 'fulfilled' && Array.isArray(res.value)) {
      okCount++;
      for (const el of res.value) {
        dedup.set(`${el.type}:${el.id}`, el);
      }
    }
  }
  if (okCount === 0) throw new Error('OSM v0.6 quadrantes indisponíveis');
  return Array.from(dedup.values());
}

async function fetchOverpassMapData(sq, centerLat, centerLng) {
  let elements = null;
  let lastErr = null;

  // 1. Fonte Primária: API Oficial OpenStreetMap v0.6 (~1s, sem timeout do Overpass!)
  try {
    elements = await fetchOsmElementsViaV06(sq);
  } catch (err) {
    lastErr = err;
  }

  // 2. Fallback: Overpass API (corrida em paralelo nos mirrors)
  if (!elements || elements.length === 0) {
    const bbox = `${sq.south.toFixed(6)},${sq.west.toFixed(6)},${sq.north.toFixed(6)},${sq.east.toFixed(6)}`;
    const query = `[out:json][timeout:14];
(
  way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)$"](${bbox});
  way["building"](${bbox});
  node["amenity"~"^(hospital|clinic|pharmacy|police|fire_station|fuel|school|university|supermarket|bank|restaurant|cafe)$"](${bbox});
  way["leisure"~"^(park|garden|pitch|recreation_ground|nature_reserve|playground)$"](${bbox});
  way["landuse"~"^(forest|grass|meadow|recreation_ground|village_green|orchard|cemetery)$"](${bbox});
  way["natural"~"^(wood|grassland|scrub|heath)$"](${bbox});
);
out body;
>;
out skel qt;`;

    const endpoints = [
      'https://overpass.openstreetmap.fr/api/interpreter',
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter'
    ];

    try {
      elements = await Promise.any(
        endpoints.map(async (ep) => {
          const ctrl = new AbortController();
          const timer = setTimeout(() => ctrl.abort(), 11000);
          try {
            const resp = await fetch(ep, {
              method: 'POST',
              signal: ctrl.signal,
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
                'User-Agent': 'KnoxSurvival3D/1.0 (RealWorldProcedural)'
              },
              body: `data=${encodeURIComponent(query)}`
            });
            if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
            const data = await resp.json();
            if (data && Array.isArray(data.elements) && data.elements.length > 0) {
              return data.elements;
            }
            throw new Error('Empty Overpass response');
          } finally {
            clearTimeout(timer);
          }
        })
      );
    } catch (err) {
      lastErr = err;
    }
  }

  if (!elements) {
    throw lastErr || new Error('OpenStreetMap indisponível no momento');
  }

  const nodeMap = new Map();
  for (const el of elements) {
    if (el.type === 'node') {
      nodeMap.set(el.id, { lat: el.lat, lon: el.lon, tags: el.tags || null });
    }
  }

  const DRIVABLE_HIGHWAYS = new Set([
    'motorway', 'motorway_link', 'trunk', 'trunk_link',
    'primary', 'primary_link', 'secondary', 'secondary_link',
    'tertiary', 'tertiary_link', 'unclassified', 'residential',
    'living_street', 'service'
  ]);
  const VALID_POI_AMENITIES = new Set([
    'hospital', 'clinic', 'pharmacy', 'police', 'fire_station',
    'fuel', 'school', 'university', 'supermarket', 'bank', 'restaurant', 'cafe'
  ]);

  const roads = [];
  const buildings = [];
  const greenAreas = [];
  const halfBound = sq.halfM * 1.06;

  for (const el of elements) {
    const tags = el.tags || {};

    // 1. Estradas, avenidas, ruas residenciais (filtra trilhas/calçadas/escadas)
    if (el.type === 'way' && tags.highway && Array.isArray(el.nodes) && el.nodes.length >= 2) {
      const hw = String(tags.highway);
      if (!DRIVABLE_HIGHWAYS.has(hw)) continue;
      if (hw === 'service' && (tags.service === 'parking_aisle' || tags.service === 'driveway')) continue;

      let roadClass = 'street';
      let width = 8.6;
      if (hw === 'motorway' || hw === 'motorway_link' || hw === 'trunk' || hw === 'trunk_link' || hw === 'primary' || hw === 'primary_link') {
        roadClass = 'avenue';
        width = 11.8;
      } else if (hw === 'secondary' || hw === 'secondary_link' || hw === 'tertiary' || hw === 'tertiary_link') {
        roadClass = 'street';
        width = 9.4;
      } else if (hw === 'residential' || hw === 'unclassified' || hw === 'living_street') {
        roadClass = 'residential';
        width = 7.4;
      } else {
        roadClass = 'service';
        width = 5.8;
      }

      const pts = [];
      for (const nid of el.nodes) {
        const nd = nodeMap.get(nid);
        if (!nd) continue;
        const p = latLngToLocalXZ(nd.lat, nd.lon, centerLat, centerLng);
        if (Math.abs(p.x) <= halfBound && Math.abs(p.z) <= halfBound) {
          if (pts.length === 0 || Math.hypot(p.x - pts[pts.length - 1].x, p.z - pts[pts.length - 1].z) >= 2.2) {
            pts.push(p);
          }
        }
      }
      if (pts.length >= 2) {
        roads.push({
          name: tags.name || '',
          roadClass,
          width,
          pts
        });
      }
      continue;
    }

    // 2. Construções reais (com polígono, tamanho aproximado, orientação e andares)
    if (el.type === 'way' && tags.building && Array.isArray(el.nodes) && el.nodes.length >= 3) {
      let sx = 0, sz = 0, cnt = 0;
      let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
      const polyPts = [];
      for (const nid of el.nodes) {
        const nd = nodeMap.get(nid);
        if (!nd) continue;
        const p = latLngToLocalXZ(nd.lat, nd.lon, centerLat, centerLng);
        polyPts.push(p);
        sx += p.x; sz += p.z; cnt++;
        if (p.x < minX) minX = p.x; if (p.x > maxX) maxX = p.x;
        if (p.z < minZ) minZ = p.z; if (p.z > maxZ) maxZ = p.z;
      }
      if (cnt < 3) continue;
      const cx = +(sx / cnt).toFixed(2);
      const cz = +(sz / cnt).toFixed(2);
      if (Math.abs(cx) > sq.halfM - 16 || Math.abs(cz) > sq.halfM - 16) continue;

      const spanX = Math.max(5, maxX - minX);
      const spanZ = Math.max(5, maxZ - minZ);
      const areaApprox = spanX * spanZ;
      if (areaApprox < 22) continue; // ignora pequenos galpões/muros

      const bTag = String(tags.building || '').toLowerCase();
      const amTag = String(tags.amenity || tags.healthcare || tags.shop || '').toLowerCase();
      const levels = Math.min(4, Math.max(1, parseInt(tags['building:levels'] || '0', 10) || 0));

      let prefab = 'house';
      if (bTag === 'hospital' || amTag.includes('hospital') || amTag.includes('clinic') || amTag.includes('pharmacy')) {
        prefab = 'hospital';
      } else if (amTag === 'police' || amTag === 'fire_station') {
        prefab = 'police';
      } else if (amTag === 'fuel') {
        prefab = 'gas';
      } else if (
        bTag === 'apartments' || bTag === 'office' || bTag === 'hotel' || bTag === 'university' ||
        bTag === 'school' || bTag === 'public' || bTag === 'civic' || bTag === 'industrial' ||
        levels >= 3 || areaApprox > 340
      ) {
        prefab = 'building';
      } else if (
        bTag === 'commercial' || bTag === 'retail' || bTag === 'supermarket' ||
        tags.shop || amTag === 'supermarket' || amTag === 'bank' || amTag === 'restaurant' || amTag === 'cafe'
      ) {
        prefab = 'shop';
      }

      buildings.push({
        x: cx,
        z: cz,
        w: +Math.min(28, spanX).toFixed(1),
        d: +Math.min(28, spanZ).toFixed(1),
        floors: levels || (prefab === 'building' ? (areaApprox > 520 ? 3 : 2) : (areaApprox > 170 ? 2 : 1)),
        prefab,
        name: tags.name || tags['addr:street'] || ''
      });
      continue;
    }

    // 3. POIs pontuais importantes (hospitais, delegacias, postos)
    if (el.type === 'node' && tags.amenity) {
      const p = latLngToLocalXZ(el.lat, el.lon, centerLat, centerLng);
      if (Math.abs(p.x) > sq.halfM - 18 || Math.abs(p.z) > sq.halfM - 18) continue;
      const am = String(tags.amenity).toLowerCase();
      if (!VALID_POI_AMENITIES.has(am)) continue;
      let prefab = 'shop';
      if (am === 'hospital' || am === 'clinic' || am === 'pharmacy') prefab = 'hospital';
      else if (am === 'police' || am === 'fire_station') prefab = 'police';
      else if (am === 'fuel') prefab = 'gas';
      else if (am === 'school' || am === 'university' || am === 'bank') prefab = 'building';
      buildings.push({
        x: p.x,
        z: p.z,
        w: 16,
        d: 14,
        floors: prefab === 'building' ? 3 : 1,
        prefab,
        name: tags.name || am.toUpperCase()
      });
      continue;
    }

    // 4. Áreas Verdes Reais (parques, bosques, praças, campos, grama)
    if (el.type === 'way' && (tags.leisure || tags.landuse || tags.natural) && Array.isArray(el.nodes) && el.nodes.length >= 3) {
      const isGreen =
        ['park', 'garden', 'pitch', 'recreation_ground', 'nature_reserve', 'playground'].includes(tags.leisure) ||
        ['forest', 'grass', 'meadow', 'recreation_ground', 'village_green', 'orchard', 'cemetery'].includes(tags.landuse) ||
        ['wood', 'grassland', 'scrub', 'heath'].includes(tags.natural);
      if (!isGreen) continue;

      const poly = [];
      let sx = 0, sz = 0, minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
      for (const nid of el.nodes) {
        const nd = nodeMap.get(nid);
        if (!nd) continue;
        const p = latLngToLocalXZ(nd.lat, nd.lon, centerLat, centerLng);
        poly.push([p.x, p.z]);
        sx += p.x; sz += p.z;
        if (p.x < minX) minX = p.x; if (p.x > maxX) maxX = p.x;
        if (p.z < minZ) minZ = p.z; if (p.z > maxZ) maxZ = p.z;
      }
      if (poly.length < 3) continue;
      const cx = +(sx / poly.length).toFixed(1);
      const cz = +(sz / poly.length).toFixed(1);
      const rx = Math.max(8, (maxX - minX) * 0.5);
      const rz = Math.max(8, (maxZ - minZ) * 0.5);
      if (rx < 7 && rz < 7) continue;

      const isForest = tags.landuse === 'forest' || tags.natural === 'wood' || tags.leisure === 'nature_reserve';
      // Simplifica polígono para manter payload enxuto
      const step = Math.max(1, Math.floor(poly.length / 18));
      const simp = [];
      for (let i = 0; i < poly.length; i += step) simp.push(poly[i]);

      greenAreas.push({
        name: tags.name || (isForest ? 'Mata Local' : 'Área Verde'),
        kind: isForest ? 'forest' : 'park',
        cx, cz,
        rx: +rx.toFixed(1),
        rz: +rz.toFixed(1),
        poly: simp
      });
    }
  }

  return { roads, buildings, greenAreas };
}

const server = http.createServer(async (req, res) => {
  let urlObj;
  let pathname;
  try {
    urlObj = new URL(req.url, `http://localhost:${PORT}`);
    pathname = decodeURIComponent(urlObj.pathname);
  } catch {
    res.writeHead(400);
    res.end('Bad Request');
    return;
  }

  if (req.method === 'OPTIONS' && pathname.startsWith('/api/')) {
    res.writeHead(200, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type'
    });
    res.end();
    return;
  }

  if (pathname === '/api/maps-config') {
    const apiKey = readDotEnvKey();
    sendJson(res, 200, { configured: Boolean(apiKey), apiKey });
    return;
  }

  // Geocoding gratuito OpenStreetMap (Nominatim) — zero API key!
  if (pathname === '/api/osm-geocode' && req.method === 'GET') {
    const q = (urlObj.searchParams.get('q') || '').trim();
    if (!q || q.length < 2) {
      sendJson(res, 200, { results: [] });
      return;
    }
    try {
      const nomUrl = `https://nominatim.openstreetmap.org/search?format=json&limit=6&addressdetails=1&q=${encodeURIComponent(q)}`;
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 8000);
      const resp = await fetch(nomUrl, {
        signal: ctrl.signal,
        headers: { 'User-Agent': 'KnoxSurvival3D/1.0 (OSM Geocode)' }
      });
      clearTimeout(timer);
      if (!resp.ok) throw new Error(`Nominatim HTTP ${resp.status}`);
      const arr = await resp.json();
      const results = (Array.isArray(arr) ? arr : []).map((item) => ({
        name: item.display_name,
        shortName: item.name || (item.display_name || '').split(',').slice(0, 2).join(','),
        lat: parseFloat(item.lat),
        lng: parseFloat(item.lon)
      }));
      sendJson(res, 200, { results });
    } catch (err) {
      sendJson(res, 502, { error: 'Falha na busca OpenStreetMap', detail: String(err.message || err), results: [] });
    }
    return;
  }

  // Scanner Completo OpenStreetMap (Overpass + Open-Meteo Elevation) — 100% gratuito, sem API key!
  if (pathname === '/api/osm-scan' && req.method === 'POST') {
    try {
      const raw = await readRequestBody(req, 256 * 1024);
      const body = JSON.parse(raw || '{}');
      const lat = Number(body.lat);
      const lng = Number(body.lng);
      const areaKm2 = Math.max(0.25, Math.min(4.0, Number(body.areaKm2) || 1.0));
      const skipElevation = Boolean(body.skipElevation);

      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        sendJson(res, 400, { error: 'Coordenadas inválidas' });
        return;
      }

      const sq = getBoundsSquare(lat, lng, areaKm2);
      const [osmRes, elevRes] = await Promise.allSettled([
        fetchOverpassMapData(sq, lat, lng),
        skipElevation ? Promise.resolve(null) : fetchOpenMeteoElevationGrid(sq, 17)
      ]);

      const osmData = osmRes.status === 'fulfilled'
        ? osmRes.value
        : { roads: [], buildings: [], greenAreas: [], osmError: String(osmRes.reason?.message || osmRes.reason) };

      const elevData = elevRes.status === 'fulfilled' ? elevRes.value : null;

      sendJson(res, 200, {
        ok: true,
        centerLat: lat,
        centerLng: lng,
        areaKm2,
        sideM: sq.sideM,
        halfM: sq.halfM,
        roads: osmData.roads,
        buildings: osmData.buildings,
        greenAreas: osmData.greenAreas,
        elevation: elevData,
        warnings: [
          osmRes.status === 'rejected' ? `Overpass: ${osmRes.reason?.message || 'timeout'}` : null,
          elevRes.status === 'rejected' ? `Elevação: ${elevRes.reason?.message || 'timeout'}` : null
        ].filter(Boolean)
      });
    } catch (err) {
      sendJson(res, 500, { error: 'Falha ao escanear área OpenStreetMap', detail: String(err.message || err) });
    }
    return;
  }

  // Armazenamento e Validação de World Blueprints (Host <-> Cliente sincronizados 1:1!)
  if (pathname === '/api/worlds') {
    pruneWorlds();
    if (req.method === 'GET') {
      const id = (urlObj.searchParams.get('id') || '').trim();
      if (!id || !worldBlueprints.has(id)) {
        sendJson(res, 404, { error: 'World blueprint não encontrado' });
        return;
      }
      const entry = worldBlueprints.get(id);
      sendJson(res, 200, {
        ok: true,
        worldId: id,
        worldHash: entry.worldHash,
        blueprint: entry.blueprint
      });
      return;
    }

    if (req.method === 'POST') {
      try {
        const raw = await readRequestBody(req, 5 * 1024 * 1024);
        const body = JSON.parse(raw || '{}');
        const worldId = String(body.worldId || '').slice(0, 80).trim();
        const worldHash = String(body.worldHash || '').slice(0, 40).trim();
        const bp = body.blueprint;

        if (!worldId || !worldHash || !bp || typeof bp !== 'object' || !Number.isFinite(bp.sideM)) {
          sendJson(res, 400, { error: 'Blueprint inválido ou incompleto' });
          return;
        }
        worldBlueprints.set(worldId, {
          worldHash,
          blueprint: bp,
          updatedAt: Date.now()
        });
        pruneWorlds();
        sendJson(res, 200, { ok: true, worldId, worldHash, bytes: raw.length });
      } catch (err) {
        sendJson(res, 400, { error: 'Erro ao salvar blueprint do mundo', detail: String(err.message || err) });
      }
      return;
    }
  }

  if (pathname === '/api/servers') {
    let rawBody = '';
    req.on('data', (c) => { rawBody += c; });
    req.on('end', () => {
      req.body = rawBody;
      const fakeRes = {
        setHeader: (k, v) => res.setHeader(k, v),
        status: (code) => ({
          json: (obj) => {
            res.statusCode = code;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify(obj));
          },
          end: () => { res.statusCode = code; res.end(); }
        })
      };
      try {
        apiServersHandler(req, fakeRes);
      } catch {
        res.statusCode = 400;
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({ error: 'Invalid request body' }));
      }
    });
    return;
  }

  const relPath = pathname === '/' ? '/index.html' : pathname;
  let safePath = path.normalize(path.join(__dirname, 'public', relPath));
  if (!fs.existsSync(safePath)) {
    safePath = path.normalize(path.join(__dirname, relPath));
  }
  if (!safePath.startsWith(__dirname)) {
    res.writeHead(403); res.end('Forbidden'); return;
  }

  fs.stat(safePath, (err, st) => {
    if (err || !st.isFile()) {
      res.writeHead(404); res.end('Not found'); return;
    }
    const ext = path.extname(safePath).toLowerCase();
    res.writeHead(200, {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Cache-Control': 'no-cache'
    });
    if (req.method === 'HEAD') {
      res.end();
      return;
    }
    fs.createReadStream(safePath).pipe(res);
  });
});

server.listen(PORT, HOST, () => {
  console.log(`\n======================================================`);
  console.log(`  KNOX // DayZ Survival Server rodando em:`);
  console.log(`  http://${HOST}:${PORT}`);
  console.log(`======================================================\n`);
});
