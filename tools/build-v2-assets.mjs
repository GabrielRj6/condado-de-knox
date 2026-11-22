#!/usr/bin/env node
/**
 * build-v2-assets.mjs — Converte e empacota os assets de "ANIMAÇÕES NOVAS E PERSONAGENS"
 * em cópias de runtime otimizadas dentro de public/assets/v2/ + public/assets/v2/manifest.json.
 * Nunca modifica nem apaga os arquivos originais.
 */
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const SRC_ROOT = path.join(ROOT, 'ANIMAÇÕES NOVAS E PERSONAGENS');
const CHAR_SRC = path.join(
  SRC_ROOT,
  'Ultimate Modular Men- Feb 2022-20261122T045416Z-1-001',
  'Ultimate Modular Men- Feb 2022',
  'Individual Characters',
  'glTF'
);
const GUN_SRC = path.join(
  SRC_ROOT,
  'Ultimate Gun Pack - July 2019-20261122T045423Z-1-001',
  'Ultimate Gun Pack - July 2019',
  'OBJ'
);
const OUT_ROOT = path.join(ROOT, 'public', 'assets', 'v2');

function ensureDir(d) {
  fs.mkdirSync(d, { recursive: true });
}

/** Empacota um .gltf com buffer base64 embutido em .glb binário compacto (remove ~60% de inflação base64+whitespace). */
function packGltfToGlb(srcGltfPath, destGlbPath, mutateGltf = null) {
  const gltf = JSON.parse(fs.readFileSync(srcGltfPath, 'utf8'));
  if (!Array.isArray(gltf.buffers) || gltf.buffers.length === 0) {
    throw new Error(`Sem buffers em ${srcGltfPath}`);
  }
  const b0 = gltf.buffers[0];
  let binBuf;
  if (typeof b0.uri === 'string' && b0.uri.startsWith('data:')) {
    const comma = b0.uri.indexOf(',');
    binBuf = Buffer.from(b0.uri.slice(comma + 1), 'base64');
  } else if (typeof b0.uri === 'string') {
    binBuf = fs.readFileSync(path.join(path.dirname(srcGltfPath), b0.uri));
  } else {
    throw new Error(`Buffer URI não suportado em ${srcGltfPath}`);
  }

  delete b0.uri;
  b0.byteLength = binBuf.length;

  if (typeof mutateGltf === 'function') {
    mutateGltf(gltf);
  }

  // Padding 4 bytes conforme especificação glTF 2.0 GLB
  let jsonBuf = Buffer.from(JSON.stringify(gltf), 'utf8');
  const jsonPad = (4 - (jsonBuf.length % 4)) % 4;
  if (jsonPad) jsonBuf = Buffer.concat([jsonBuf, Buffer.alloc(jsonPad, 0x20)]);

  const binPad = (4 - (binBuf.length % 4)) % 4;
  const paddedBin = binPad ? Buffer.concat([binBuf, Buffer.alloc(binPad, 0x00)]) : binBuf;

  const totalLen = 12 + 8 + jsonBuf.length + 8 + paddedBin.length;
  const header = Buffer.alloc(12);
  header.write('glTF', 0, 4, 'ascii');
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(totalLen, 8);

  const jsonChunkHdr = Buffer.alloc(8);
  jsonChunkHdr.writeUInt32LE(jsonBuf.length, 0);
  jsonChunkHdr.writeUInt32LE(0x4e4f534a, 4); // JSON

  const binChunkHdr = Buffer.alloc(8);
  binChunkHdr.writeUInt32LE(paddedBin.length, 0);
  binChunkHdr.writeUInt32LE(0x004e4942, 4); // BIN

  ensureDir(path.dirname(destGlbPath));
  fs.writeFileSync(destGlbPath, Buffer.concat([header, jsonChunkHdr, jsonBuf, binChunkHdr, paddedBin]));
  return totalLen;
}

function measureObjBounds(objPath) {
  const txt = fs.readFileSync(objPath, 'utf8');
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity, minZ = Infinity, maxZ = -Infinity;
  for (const line of txt.split('\n')) {
    if (line.startsWith('v ')) {
      const p = line.trim().split(/\s+/);
      const x = +p[1], y = +p[2], z = +p[3];
      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) continue;
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
      if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
    }
  }
  return { minX, maxX, minY, maxY, minZ, maxZ };
}

function zombifyMaterials(palette) {
  return (gltf) => {
    if (!Array.isArray(gltf.materials)) return;
    for (const m of gltf.materials) {
      const n = String(m.name || '').toLowerCase();
      m.pbrMetallicRoughness = m.pbrMetallicRoughness || {};
      if (n.includes('skin')) {
        m.pbrMetallicRoughness.baseColorFactor = palette.skin;
        m.pbrMetallicRoughness.roughnessFactor = 0.88;
      } else if (n.includes('eye') && !n.includes('eyebrow')) {
        m.pbrMetallicRoughness.baseColorFactor = palette.eye;
        m.emissiveFactor = palette.eyeEmissive || [0.18, 0.04, 0.02];
      } else if (n.includes('hair') || n.includes('eyebrow') || n.includes('moustache')) {
        m.pbrMetallicRoughness.baseColorFactor = [0.10, 0.10, 0.09, 1.0];
      } else if (n.includes('red') || n.includes('purple') || n.includes('worker_yellow') || n.includes('worker_vest') || n.includes('white')) {
        m.pbrMetallicRoughness.baseColorFactor = palette.shirt;
        m.pbrMetallicRoughness.roughnessFactor = 0.92;
      } else {
        // Escurece roupas e botas para aspecto rasgado/sujo
        const f = Array.isArray(m.pbrMetallicRoughness.baseColorFactor)
          ? m.pbrMetallicRoughness.baseColorFactor.slice()
          : [0.3, 0.3, 0.3, 1.0];
        m.pbrMetallicRoughness.baseColorFactor = [
          +(f[0] * 0.42 + palette.grime[0] * 0.14).toFixed(3),
          +(f[1] * 0.44 + palette.grime[1] * 0.14).toFixed(3),
          +(f[2] * 0.38 + palette.grime[2] * 0.12).toFixed(3),
          1.0
        ];
        m.pbrMetallicRoughness.roughnessFactor = 0.90;
      }
    }
  };
}

// 1. 11 Personagens jogáveis (Quaternius Ultimate Modular Men)
const CHARACTER_SPECS = [
  { id: 'swat',          src: 'Swat.gltf',          name: 'Operador SWAT',     role: 'Tático',        accent: '#3b82f6' },
  { id: 'adventurer',    src: 'Adventurer.gltf',    name: 'Explorador',        role: 'Sobrevivente',  accent: '#d97706' },
  { id: 'casual_hoodie', src: 'Casual_Hoodie.gltf', name: 'Sobrevivente',      role: 'Urbano',        accent: '#a855f7' },
  { id: 'casual_2',      src: 'Casual_2.gltf',      name: 'Civil',             role: 'Bairro',        accent: '#ef4444' },
  { id: 'farmer',        src: 'Farmer.gltf',        name: 'Fazendeiro',        role: 'Rural',         accent: '#22c55e' },
  { id: 'worker',        src: 'Worker.gltf',        name: 'Operário',          role: 'Industrial',    accent: '#eab308' },
  { id: 'suit',          src: 'Suit.gltf',          name: 'Executivo',         role: 'Centro',        accent: '#64748b' },
  { id: 'punk',          src: 'Punk.gltf',          name: 'Punk',              role: 'Rua',           accent: '#ec4899' },
  { id: 'beach',         src: 'Beach.gltf',         name: 'Turista',           role: 'Costa',         accent: '#06b6d4' },
  { id: 'spacesuit',     src: 'Spacesuit.gltf',     name: 'Traje Hazmat',      role: 'Quarentena',    accent: '#f97316' },
  { id: 'king',          src: 'King.gltf',          name: 'Rei de Knox',       role: 'Lendário',      accent: '#facc15' }
];

const STANDARD_CHAR_CLIPS = {
  idle: 'Idle',
  idleNeutral: 'Idle_Neutral',
  idleGun: 'Idle_Gun',
  idleGunAim: 'Idle_Gun_Pointing',
  idleGunShoot: 'Idle_Gun_Shoot',
  idleMelee: 'Idle_Sword',
  walk: 'Walk',
  run: 'Run',
  runBack: 'Run_Back',
  runLeft: 'Run_Left',
  runRight: 'Run_Right',
  runShoot: 'Run_Shoot',
  crouchIdle: null,   // pendente: fallback procedural agachado sobre Idle/Idle_Gun
  crouchWalk: null,   // pendente: fallback procedural agachado sobre Walk
  prone: null,        // pendente: fallback procedural deitado
  jump: null,         // pendente: fallback procedural pulo/roll
  roll: 'Roll',
  shoot: 'Gun_Shoot',
  melee: 'Sword_Slash',
  punch: ['Punch_Left', 'Punch_Right'],
  interact: 'Interact',
  hit: ['HitRecieve', 'HitRecieve_2'],
  death: ['Death']
};

const manifest = {
  version: 2,
  generatedAt: new Date().toISOString(),
  notes: {
    sourcePackCharacters: 'Quaternius Ultimate Modular Men (62 ossos, 24 clips integrados)',
    sourcePackWeapons: 'Quaternius Ultimate Gun Pack (OBJ+MTL com +X = cano, +Y = cima)',
    sourcePackZombieNote: 'Zombie by @Quaternius continha apenas OBJ estático sem rig/clips; variantes zumbis v2 usam o esqueleto Quaternius 62-ossos zumbificado para animação esquelética completa.'
  },
  characters: [],
  zombies: [],
  weapons: {},
  accessories: {}
};

ensureDir(path.join(OUT_ROOT, 'characters'));
ensureDir(path.join(OUT_ROOT, 'zombies'));
ensureDir(path.join(OUT_ROOT, 'weapons'));
ensureDir(path.join(OUT_ROOT, 'accessories'));

let totalCharBytes = 0;
for (const c of CHARACTER_SPECS) {
  const src = path.join(CHAR_SRC, c.src);
  const relFile = `characters/${c.id}.glb`;
  const dst = path.join(OUT_ROOT, relFile);
  const bytes = packGltfToGlb(src, dst);
  totalCharBytes += bytes;
  manifest.characters.push({
    id: c.id,
    name: c.name,
    role: c.role,
    accent: c.accent,
    file: relFile,
    scale: 0.96,
    yawOffset: Math.PI,
    boneNormalize: true,
    rightHandBone: 'Wrist.R',
    headBone: 'Head',
    weaponOffset: {
      pos: [0.02, 0.08, 0.04],
      rot: [Math.PI * 0.5, 0, -Math.PI * 0.5],
      scale: 0.95
    },
    clips: STANDARD_CHAR_CLIPS
  });
}

// 2. 3 Variantes de Zumbi Rigged (esqueleto Quaternius 62 ossos com pele/roupas zumbificadas)
const ZOMBIE_SPECS = [
  {
    id: 'zombie_walker',
    name: 'Infectado Andarilho',
    src: 'Casual_2.gltf',
    scale: 0.95,
    palette: {
      skin: [0.34, 0.42, 0.30, 1.0],
      shirt: [0.22, 0.14, 0.13, 1.0],
      eye: [0.75, 0.16, 0.10, 1.0],
      eyeEmissive: [0.22, 0.04, 0.02],
      grime: [0.16, 0.19, 0.13]
    }
  },
  {
    id: 'zombie_runner',
    name: 'Infectado Corredor',
    src: 'Casual_Hoodie.gltf',
    scale: 0.94,
    palette: {
      skin: [0.30, 0.36, 0.28, 1.0],
      shirt: [0.15, 0.13, 0.17, 1.0],
      eye: [0.85, 0.12, 0.08, 1.0],
      eyeEmissive: [0.30, 0.04, 0.02],
      grime: [0.14, 0.16, 0.12]
    }
  },
  {
    id: 'zombie_brute',
    name: 'Infectado Operário',
    src: 'Worker.gltf',
    scale: 1.04,
    palette: {
      skin: [0.27, 0.34, 0.25, 1.0],
      shirt: [0.26, 0.24, 0.12, 1.0],
      eye: [0.82, 0.20, 0.08, 1.0],
      eyeEmissive: [0.26, 0.05, 0.02],
      grime: [0.18, 0.16, 0.11]
    }
  }
];

let totalZombieBytes = 0;
for (const z of ZOMBIE_SPECS) {
  const src = path.join(CHAR_SRC, z.src);
  const relFile = `zombies/${z.id}.glb`;
  const dst = path.join(OUT_ROOT, relFile);
  const bytes = packGltfToGlb(src, dst, zombifyMaterials(z.palette));
  totalZombieBytes += bytes;
  manifest.zombies.push({
    id: z.id,
    name: z.name,
    file: relFile,
    scale: z.scale,
    yawOffset: Math.PI,
    boneNormalize: true,
    maxAnimatedCount: 40,
    clips: {
      idle: 'Idle_Neutral',
      walk: 'Walk',
      run: 'Run',
      attack: ['Punch_Left', 'Punch_Right'],
      hit: ['HitRecieve', 'HitRecieve_2'],
      crawl: null,
      death: ['Death']
    }
  });
}

// 3. Armas v2 (Quaternius Ultimate Gun Pack OBJ+MTL)
const WEAPON_MAP = [
  { id: 'assault_rifle',     obj: 'AssaultRifle_2.obj',     mtl: 'AssaultRifle_2.mtl',     barrelYRatio: 0.42 },
  { id: 'ak_rifle',          obj: 'AssaultRifle_5.obj',     mtl: 'AssaultRifle_5.mtl',     barrelYRatio: 0.42 },
  { id: 'dmr_m110',          obj: 'AssaultRifle2_3.obj',    mtl: 'AssaultRifle2_3.mtl',    barrelYRatio: 0.45 },
  { id: 'mdr_rifle',         obj: 'Bullpup_1.obj',          mtl: 'Bullpup_1.mtl',          barrelYRatio: 0.46 },
  { id: 'sniper_rifle',      obj: 'SniperRifle_4.obj',      mtl: 'SniperRifle_4.mtl',      barrelYRatio: 0.45 },
  { id: 'heavy_sniper',      obj: 'SniperRifle_6.obj',      mtl: 'SniperRifle_6.mtl',      barrelYRatio: 0.46 },
  { id: 'tactical_pistol',   obj: 'Pistol_2.obj',           mtl: 'Pistol_2.mtl',           barrelYRatio: 0.62 },
  { id: 'revolver_magnum',   obj: 'Revolver_3.obj',         mtl: 'Revolver_3.mtl',         barrelYRatio: 0.62 },
  { id: 'combat_shotgun',    obj: 'Shotgun_3.obj',          mtl: 'Shotgun_3.mtl',          barrelYRatio: 0.56 },
  { id: 'double_barrel',     obj: 'Shotgun_SawedOff.obj',   mtl: 'Shotgun_SawedOff.mtl',   barrelYRatio: 0.56 },
  { id: 'compact_smg',       obj: 'SubmachineGun_4.obj',    mtl: 'SubmachineGun_4.mtl',    barrelYRatio: 0.48 },
  { id: 'heavy_lmg',         obj: 'AssaultRifle2_4.obj',    mtl: 'AssaultRifle2_4.mtl',    barrelYRatio: 0.48 },
  { id: 'plasma_rifle',      obj: 'Bullpup_3.obj',          mtl: 'Bullpup_3.mtl',          barrelYRatio: 0.48 },
  { id: 'combat_knife',      obj: 'Accessories/Bayonet.obj', mtl: 'Accessories/Bayonet.mtl', barrelYRatio: 0.50, outBase: 'Bayonet' },
  { id: 'tactical_katana',   obj: 'Accessories/Bayonet_2.obj', mtl: 'Accessories/Bayonet_2.mtl', barrelYRatio: 0.50, outBase: 'Bayonet_2' }
];

let totalWeaponBytes = 0;
for (const w of WEAPON_MAP) {
  const srcObj = path.join(GUN_SRC, w.obj);
  const srcMtl = path.join(GUN_SRC, w.mtl);
  const base = w.outBase || path.basename(w.obj, '.obj');
  const dstObjRel = `weapons/${base}.obj`;
  const dstMtlRel = `weapons/${base}.mtl`;
  fs.copyFileSync(srcObj, path.join(OUT_ROOT, dstObjRel));
  fs.copyFileSync(srcMtl, path.join(OUT_ROOT, dstMtlRel));
  totalWeaponBytes += fs.statSync(srcObj).size + fs.statSync(srcMtl).size;

  const b = measureObjBounds(srcObj);
  const spanX = b.maxX - b.minX;
  const spanY = b.maxY - b.minY;
  const barrelY = +(b.minY + spanY * w.barrelYRatio).toFixed(3);
  const opticX = +(b.minX + spanX * 0.36).toFixed(3);
  const sideX = +(b.minX + spanX * 0.72).toFixed(3);
  const underX = +(b.minX + spanX * 0.65).toFixed(3);

  manifest.weapons[w.id] = {
    id: w.id,
    file: dstObjRel,
    mtl: dstMtlRel,
    sourceName: base,
    sockets: {
      muzzle: [+b.maxX.toFixed(3), barrelY, 0],
      grip: [+(b.minX + spanX * 0.25).toFixed(3), +(b.minY * 0.4).toFixed(3), 0],
      ejection: [+(b.minX + spanX * 0.42).toFixed(3), +(barrelY + spanY * 0.08).toFixed(3), +(b.maxZ * 0.95).toFixed(3)],
      optic: [opticX, +(b.maxY * 0.96).toFixed(3), 0],
      side: [sideX, barrelY, +(b.maxZ * 1.02).toFixed(3)],
      under: [underX, +(b.minY + spanY * 0.26).toFixed(3), 0]
    },
    clips: { fire: null, reload: null, draw: null }
  };
}

// Armas sem equivalente direto no Ultimate Gun Pack mantêm fallback explícito para v1
for (const fbId of ['rocket_launcher', 'frag_grenade', 'tactical_crossbow']) {
  manifest.weapons[fbId] = {
    id: fbId,
    fallbackV1: true,
    note: 'Sem equivalente no Ultimate Gun Pack; mantém modelo 3D v1 até novo asset específico.'
  };
}

// 4. Acessórios táticos Quaternius (para attachments)
const ACCESSORY_MAP = {
  reddot:     'Scope_1',
  holo:       'Scope_1',
  acog4x:     'Scope_2',
  scope8x:    'Scope_3',
  scope12x:   'Scope_3',
  suppressor: 'Silencer_long',
  compensator:'Silencer_Short',
  muzzlebrake:'Silencer_1',
  taclight:   'Flashlight',
  laser:      'Flashlight',
  foregrip:   'Grip',
  bipod:      'Bipod'
};

const copiedAcc = new Set();
for (const [attId, base] of Object.entries(ACCESSORY_MAP)) {
  const dstObjRel = `accessories/${base}.obj`;
  const dstMtlRel = `accessories/${base}.mtl`;
  if (!copiedAcc.has(base)) {
    const srcObj = path.join(GUN_SRC, 'Accessories', `${base}.obj`);
    const srcMtl = path.join(GUN_SRC, 'Accessories', `${base}.mtl`);
    fs.copyFileSync(srcObj, path.join(OUT_ROOT, dstObjRel));
    fs.copyFileSync(srcMtl, path.join(OUT_ROOT, dstMtlRel));
    totalWeaponBytes += fs.statSync(srcObj).size + fs.statSync(srcMtl).size;
    copiedAcc.add(base);
  }
  manifest.accessories[attId] = { file: dstObjRel, mtl: dstMtlRel, sourceName: base };
}

fs.writeFileSync(path.join(OUT_ROOT, 'manifest.json'), JSON.stringify(manifest, null, 2));

const fmt = (n) => (n >= 1e6 ? (n / 1e6).toFixed(2) + ' MB' : (n / 1e3).toFixed(1) + ' KB');
console.log('✔ public/assets/v2/ construído com sucesso!');
console.log(`  Personagens (${manifest.characters.length} GLBs): ${fmt(totalCharBytes)}`);
console.log(`  Zumbis      (${manifest.zombies.length} GLBs): ${fmt(totalZombieBytes)}`);
console.log(`  Armas+Acc   (${WEAPON_MAP.length} armas + ${copiedAcc.size} acessórios OBJ+MTL): ${fmt(totalWeaponBytes)}`);
console.log(`  TOTAL v2:   ${fmt(totalCharBytes + totalZombieBytes + totalWeaponBytes)}`);
