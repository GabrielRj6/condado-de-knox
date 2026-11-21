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
  '.fbx': 'application/octet-stream',
  '.obj': 'text/plain; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8'
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
    const query = `[out:json][timeout:16];
(
  way["highway"~"^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|living_street|service)$"](${bbox});
  way["building"](${bbox});
  relation["building"](${bbox});
  way["shop"~"^(mall|department_store|supermarket|convenience)$"](${bbox});
  way["amenity"~"^(hospital|clinic|pharmacy|police|fire_station|fuel|school|university|bank|parking|place_of_worship|townhall|courthouse|public_building|post_office|library|community_centre|grave_yard)$"](${bbox});
  node["amenity"~"^(hospital|clinic|pharmacy|police|fire_station|fuel|school|university|supermarket|bank|restaurant|cafe|parking|place_of_worship|townhall|courthouse|public_building|post_office|library|community_centre|grave_yard)$"](${bbox});
  node["shop"~"^(mall|department_store|chemist|pharmacy|supermarket|convenience)$"](${bbox});
  node["building"](${bbox});
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
          const timer = setTimeout(() => ctrl.abort(), 12000);
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
  const wayMap = new Map();
  for (const el of elements) {
    if (el.type === 'node') {
      nodeMap.set(el.id, { lat: el.lat, lon: el.lon, tags: el.tags || null });
    } else if (el.type === 'way') {
      wayMap.set(el.id, el);
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
    'fuel', 'school', 'university', 'supermarket', 'bank', 'restaurant', 'cafe',
    'parking', 'place_of_worship', 'townhall', 'courthouse', 'public_building',
    'post_office', 'library', 'community_centre', 'grave_yard'
  ]);
  const VALID_POI_SHOPS = new Set(['mall', 'department_store', 'chemist', 'pharmacy', 'supermarket', 'convenience']);

  const classifyOsmPrefab = (tags, areaApprox = 120, levels = 1) => {
    const bTag = String(tags.building || '').toLowerCase();
    const amTag = String(tags.amenity || '').toLowerCase();
    const hcTag = String(tags.healthcare || '').toLowerCase();
    const shTag = String(tags.shop || '').toLowerCase();
    const offTag = String(tags.office || '').toLowerCase();
    const luTag = String(tags.landuse || '').toLowerCase();
    const leiTag = String(tags.leisure || '').toLowerCase();
    const nm = String(tags.name || tags.brand || tags.operator || '').toLowerCase();

    // 1. Cemitério / Necrópole
    if (
      luTag === 'cemetery' || amTag === 'grave_yard' ||
      /\b(cemit[eé]rio|necr[oó]pole|campo santo|memorial da paz)\b/i.test(nm)
    ) {
      return 'cemetery';
    }
    // 2. Farmácia / Drogaria (SEPARADA de Hospital!)
    if (
      amTag === 'pharmacy' || hcTag === 'pharmacy' || shTag === 'chemist' || shTag === 'pharmacy' ||
      /\b(farm[aá]cia|drogaria|drogasil|raia|pague menos|extrafarma|panvel|ultrafarma|drogaraia|farma)\b/i.test(nm)
    ) {
      return 'pharmacy';
    }
    // 3. Hospital / Pronto-Socorro / Clínica / UPA
    if (
      bTag === 'hospital' || amTag === 'hospital' || amTag === 'clinic' ||
      hcTag === 'hospital' || hcTag === 'clinic' || hcTag === 'centre' ||
      /\b(hospital|pronto.?socorro|upa\b|maternidade|santa casa|cl[ií]nica|centro m[eé]dico|benefic[eê]ncia|ambul[aâ]ncia)\b/i.test(nm)
    ) {
      return 'hospital';
    }
    // 4. Delegacia de Polícia / Batalhão / Segurança Pública
    if (
      amTag === 'police' || bTag === 'police' || amTag === 'fire_station' ||
      /\b(delegacia|pol[ií]cia|seccional|batalh[aã]o|guarda municipal|policia militar|policia civil|prf\b|dp\b|bombeiros)\b/i.test(nm)
    ) {
      return 'police';
    }
    // 5. Shopping Center / Galeria / Grande Centro Comercial
    if (
      bTag === 'mall' || shTag === 'mall' || shTag === 'department_store' ||
      (bTag === 'retail' && areaApprox > 750) ||
      /\b(shopping|mall|boulevard|galeria|p[aá]tio|center\b|centro comercial)\b/i.test(nm)
    ) {
      return 'mall';
    }
    // 6. Supermercado / Atacarejo / Hipermercado
    if (
      shTag === 'supermarket' || bTag === 'supermarket' || amTag === 'supermarket' ||
      /\b(supermercado|hipermercado|atacad[aã]o|atacarejo|carrefour|assa[ií]|mateus|l[ií]der|extra\b|p[aã]o de a[çc][uú]car|guanabara|mundial|super\s?nosso|hortifruti|mercadinho)\b/i.test(nm)
    ) {
      return 'supermarket';
    }
    // 7. Igreja / Catedral / Templo / Capela
    if (
      amTag === 'place_of_worship' || bTag === 'church' || bTag === 'cathedral' || bTag === 'chapel' || bTag === 'temple' ||
      /\b(igreja|par[oó]quia|catedral|bas[ií]lica|capela|santu[aá]rio|templo|assembleia de deus|batista|presbiteriana|cat[oó]lica|evang[eé]lica|matriz\b|nossa senhora|s[aã]o\s+(jos[eé]|pedro|paulo|jo[aã]o|francisco|jorge|lucas|marcos))\b/i.test(nm)
    ) {
      return 'church';
    }
    // 8. Banco / Agência Bancária
    if (
      amTag === 'bank' || bTag === 'bank' ||
      /\b(banco\b|bradesco|ita[uú]|santander|caixa econ[oô]mica|banco do brasil|sicredi|sicoob|banpar[aá]|banrisul|safra|ag[eê]ncia banc[aá]ria)\b/i.test(nm)
    ) {
      return 'bank';
    }
    // 9. Prédio Público / Prefeitura / Fórum / Tribunal / Correios / Biblioteca
    if (
      amTag === 'townhall' || amTag === 'courthouse' || amTag === 'public_building' ||
      amTag === 'post_office' || amTag === 'library' || amTag === 'community_centre' ||
      bTag === 'public' || bTag === 'civic' || bTag === 'government' || offTag === 'government' ||
      /\b(prefeitura|c[aâ]mara|f[oó]rum|tribunal|secretaria|minist[eé]rio|correios|receita federal|inss\b|detran|defensoria|assembleia|pal[aá]cio|biblioteca|cart[oó]rio|pr[eé]dio p[uú]blico)\b/i.test(nm)
    ) {
      return 'public';
    }
    // 10. Posto de Combustível
    if (
      amTag === 'fuel' || bTag === 'fuel' ||
      /\b(posto\b|auto posto|combust[ií]vel|shell|ipiranga|petrobras|ale combust|gasolina)\b/i.test(nm)
    ) {
      return 'gas';
    }
    // 11. Estacionamento / Garagem
    if (
      amTag === 'parking' || bTag === 'parking' ||
      /\b(estacionamento|parking|garagem|rotativo)\b/i.test(nm)
    ) {
      return 'parking';
    }
    // 12. Parque / Praça
    if (leiTag === 'park' || leiTag === 'garden' || leiTag === 'playground' || /\b(pra[çc]a|parque)\b/i.test(nm)) {
      return 'park';
    }
    // 13. Prédios Urbanos / Corporativos / Residenciais altos
    if (
      bTag === 'apartments' || bTag === 'office' || bTag === 'hotel' || bTag === 'university' ||
      bTag === 'school' || bTag === 'industrial' || amTag === 'school' || amTag === 'university' ||
      levels >= 3 || areaApprox > 360
    ) {
      return 'building';
    }
    // 14. Comércios / Lojas / Restaurantes
    if (
      bTag === 'commercial' || bTag === 'retail' ||
      shTag || amTag === 'restaurant' || amTag === 'cafe'
    ) {
      return 'shop';
    }
    return 'house';
  };

  const roads = [];
  const buildings = [];
  const greenAreas = [];
  const halfBound = sq.halfM * 1.08;

  const pushPolygonBuilding = (nodeIds, tags) => {
    let sx = 0, sz = 0, cnt = 0;
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (const nid of nodeIds) {
      const nd = nodeMap.get(nid);
      if (!nd) continue;
      const p = latLngToLocalXZ(nd.lat, nd.lon, centerLat, centerLng);
      sx += p.x; sz += p.z; cnt++;
      if (p.x < minX) minX = p.x; if (p.x > maxX) maxX = p.x;
      if (p.z < minZ) minZ = p.z; if (p.z > maxZ) maxZ = p.z;
    }
    if (cnt < 3) return;
    const cx = +(sx / cnt).toFixed(2);
    const cz = +(sz / cnt).toFixed(2);
    if (Math.abs(cx) > sq.halfM - 12 || Math.abs(cz) > sq.halfM - 12) return;

    const spanX = Math.max(4.5, maxX - minX);
    const spanZ = Math.max(4.5, maxZ - minZ);
    const areaApprox = spanX * spanZ;
    if (areaApprox < 12) return; // aceita casas geminadas e comércios pequenos (>= 12 m²)

    const levels = Math.min(5, Math.max(0, parseInt(tags['building:levels'] || '0', 10) || 0));
    const prefab = classifyOsmPrefab(tags, areaApprox, levels || 1);

    buildings.push({
      x: cx,
      z: cz,
      w: +Math.min(34, spanX).toFixed(1),
      d: +Math.min(34, spanZ).toFixed(1),
      floors: levels || (
        prefab === 'building' ? (areaApprox > 520 ? 4 : 3) :
        (['hospital', 'mall', 'police', 'public', 'bank'].includes(prefab) ? 2 :
        (prefab === 'house' && areaApprox > 155 ? 2 : 1))
      ),
      prefab,
      name: tags.name || tags.brand || tags['addr:street'] || ''
    });
  };

  for (const el of elements) {
    const tags = el.tags || {};

    // 1. Estradas, rodovias, avenidas, ruas e passagens (com análise real de LARGURA e SENTIDO oneway!)
    if (el.type === 'way' && tags.highway && Array.isArray(el.nodes) && el.nodes.length >= 2) {
      const hw = String(tags.highway);
      if (!DRIVABLE_HIGHWAYS.has(hw)) continue;
      if (hw === 'service' && (tags.service === 'parking_aisle' || tags.service === 'driveway')) continue;

      const nmLow = String(tags.name || tags.ref || '').toLowerCase();
      const rawOneway = String(tags.oneway || '').toLowerCase();
      let oneway = 0; // 0 = mão dupla, 1 = mão única no sentido pts[0] -> pts[n-1]
      let reversePts = false;
      if (rawOneway === 'yes' || rawOneway === '1' || rawOneway === 'true') {
        oneway = 1;
      } else if (rawOneway === '-1' || rawOneway === 'reverse') {
        oneway = 1;
        reversePts = true;
      } else if (tags.junction === 'roundabout' || ((hw === 'motorway' || hw === 'motorway_link') && rawOneway !== 'no')) {
        oneway = 1;
      }

      const parsedLanes = Math.min(6, Math.max(0, parseInt(tags.lanes || '0', 10) || 0));

      let roadClass = 'street';
      let width = 8.2;

      const isHighwayName = /\b(rod\.?|rodovia|br[-\s]?\d+|sp[-\s]?\d+|pa[-\s]?\d+|mg[-\s]?\d+|rj[-\s]?\d+|estrada|via expressa|marginal|anel vi[aá]rio|freeway|highway)\b/i.test(nmLow);
      const isAvenueName = /^(av\.?|avenida|alameda|boulevard|blvd|perimetral)\b/i.test(nmLow);
      const isPassageName = /^(passagem|pass\.?|beco|viela|servid[aã]o|vila\s)\b/i.test(nmLow);

      if (hw === 'motorway' || hw === 'motorway_link' || hw === 'trunk' || hw === 'trunk_link' || isHighwayName) {
        roadClass = 'highway';
        width = oneway ? 12.6 : 16.0;
        if (parsedLanes >= 2) width = Math.max(11.6, Math.min(19.5, parsedLanes * 3.55 + 1.8));
      } else if (hw === 'primary' || hw === 'primary_link' || hw === 'secondary' || hw === 'secondary_link' || isAvenueName) {
        roadClass = 'avenue';
        width = oneway ? 9.8 : 12.4;
        if (parsedLanes >= 2) width = Math.max(9.2, Math.min(15.2, parsedLanes * 3.25 + 1.2));
      } else if (hw === 'service' || isPassageName || (parsedLanes === 1 && (hw === 'residential' || hw === 'unclassified' || hw === 'living_street'))) {
        roadClass = 'passage';
        width = oneway ? 5.2 : 5.8;
      } else {
        roadClass = 'street';
        width = oneway ? 6.8 : 8.2;
        if (parsedLanes >= 2) width = Math.max(6.8, Math.min(9.8, parsedLanes * 3.1 + 0.9));
      }

      const orderedNodes = reversePts ? el.nodes.slice().reverse() : el.nodes;
      const pts = [];
      for (const nid of orderedNodes) {
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
          name: tags.name || tags.ref || '',
          roadClass,
          width: +width.toFixed(1),
          oneway,
          lanes: parsedLanes || (roadClass === 'highway' ? (oneway ? 3 : 4) : (roadClass === 'avenue' ? (oneway ? 2 : 4) : (roadClass === 'passage' ? 1 : (oneway ? 1 : 2)))),
          pts
        });
      }
      continue;
    }

    // 2. Construções reais e grandes estruturas (building, supermercado, igreja, banco, público, estacionamento, cemitério)
    if (
      el.type === 'way' &&
      (
        tags.building ||
        tags.shop === 'mall' || tags.shop === 'department_store' || tags.shop === 'supermarket' ||
        tags.amenity === 'parking' || tags.amenity === 'place_of_worship' || tags.amenity === 'bank' ||
        tags.amenity === 'hospital' || tags.amenity === 'police' || tags.amenity === 'fuel' ||
        tags.amenity === 'townhall' || tags.amenity === 'courthouse' || tags.amenity === 'public_building' ||
        tags.amenity === 'post_office' || tags.amenity === 'library' || tags.amenity === 'community_centre' ||
        tags.amenity === 'grave_yard' || tags.landuse === 'cemetery'
      ) &&
      Array.isArray(el.nodes) && el.nodes.length >= 3
    ) {
      pushPolygonBuilding(el.nodes, tags);
      continue;
    }

    // 2b. Multipolígonos OSM (shoppings, hospitais, igrejas, prédios públicos e cemitérios grandes)
    if (el.type === 'relation' && (tags.building || tags.amenity || tags.landuse === 'cemetery') && Array.isArray(el.members)) {
      const outerIds = [];
      for (const mem of el.members) {
        if (mem.type === 'way' && (!mem.role || mem.role === 'outer')) {
          const w = wayMap.get(mem.ref);
          if (w && Array.isArray(w.nodes)) {
            for (const nid of w.nodes) outerIds.push(nid);
          }
        }
      }
      if (outerIds.length >= 3) {
        pushPolygonBuilding(outerIds, tags);
      }
      continue;
    }

    // 3. POIs pontuais (hospitais, farmácias, shoppings, delegacias, postos, supermercados, bancos, igrejas, prédios públicos, estacionamentos)
    if (el.type === 'node' && (tags.amenity || tags.shop || tags.healthcare || tags.building)) {
      const p = latLngToLocalXZ(el.lat, el.lon, centerLat, centerLng);
      if (Math.abs(p.x) > sq.halfM - 14 || Math.abs(p.z) > sq.halfM - 14) continue;
      const am = String(tags.amenity || '').toLowerCase();
      const sh = String(tags.shop || '').toLowerCase();
      const hc = String(tags.healthcare || '').toLowerCase();
      const isBldNode = Boolean(tags.building && tags.building !== 'no');
      if (!isBldNode && !VALID_POI_AMENITIES.has(am) && !VALID_POI_SHOPS.has(sh) && !['hospital', 'clinic', 'pharmacy'].includes(hc)) continue;
      const prefab = classifyOsmPrefab(tags, isBldNode ? 110 : 220, 1);
      buildings.push({
        x: p.x,
        z: p.z,
        w: prefab === 'mall' ? 22 : (prefab === 'hospital' || prefab === 'supermarket' || prefab === 'public' ? 17 : 13),
        d: prefab === 'mall' ? 16 : 13,
        floors: prefab === 'building' ? 3 : (['hospital', 'mall', 'police', 'public', 'bank'].includes(prefab) ? 2 : 1),
        prefab,
        name: tags.name || tags.brand || (am || sh || hc || '').toUpperCase()
      });
      continue;
    }

    // 4. Áreas Verdes Reais (parques, bosques, praças, campos, grama — cemitérios já viraram estrutura dedicada acima!)
    if (el.type === 'way' && (tags.leisure || tags.landuse || tags.natural) && Array.isArray(el.nodes) && el.nodes.length >= 3) {
      const isGreen =
        ['park', 'garden', 'pitch', 'recreation_ground', 'nature_reserve', 'playground'].includes(tags.leisure) ||
        ['forest', 'grass', 'meadow', 'recreation_ground', 'village_green', 'orchard'].includes(tags.landuse) ||
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

      // Parques e praças urbanos ganham uma praça 3D completa (fonte, bancos, pergolado, trilhas) no centro!
      if (!isForest && ['park', 'garden', 'playground', 'recreation_ground'].includes(tags.leisure) && rx >= 9 && rz >= 9 && Math.abs(cx) <= sq.halfM - 16 && Math.abs(cz) <= sq.halfM - 16) {
        buildings.push({
          x: cx,
          z: cz,
          w: Math.min(22, +(rx * 1.4).toFixed(1)),
          d: Math.min(20, +(rz * 1.4).toFixed(1)),
          floors: 1,
          prefab: 'park',
          name: tags.name || 'Parque Municipal'
        });
      }
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
