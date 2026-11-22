import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OBJLoader } from 'three/addons/loaders/OBJLoader.js';
import { MTLLoader } from 'three/addons/loaders/MTLLoader.js';
import * as SkeletonUtils from 'three/addons/utils/SkeletonUtils.js';

const V2_BASE_URL = '/assets/v2/';
const warnedKeys = new Set();

function warnOnce(key, msg) {
  if (warnedKeys.has(key)) return;
  warnedKeys.add(key);
  console.warn(`[AssetLibrary] ${msg}`);
}

export function getAssetVersion() {
  try {
    const p = new URLSearchParams(globalThis.location ? globalThis.location.search : '').get('assets');
    if (p === 'v1' || p === '1') return 'v1';
    if (p === 'v2' || p === '2') return 'v2';
  } catch (_) {}
  return 'v2';
}

function normBoneName(name) {
  return String(name || '')
    .replace(/^mixamorig[:_]?/i, '')
    .replace(/^(armature|rig|skeleton|characterarmature)[|:_.]/i, '')
    .replace(/[^a-z0-9]/gi, '')
    .toLowerCase();
}

export function normalizeClipTracks(clip, rootScene) {
  if (!clip || !rootScene) return clip;
  const exactNames = new Set();
  const normMap = new Map();
  rootScene.traverse((obj) => {
    if (!obj.name) return;
    exactNames.add(obj.name);
    const n = normBoneName(obj.name);
    if (n && !normMap.has(n)) normMap.set(n, obj.name);
  });

  let changed = false;
  const tracks = clip.tracks.map((tr) => {
    const dot = tr.name.lastIndexOf('.');
    if (dot <= 0) return tr;
    const bonePart = tr.name.slice(0, dot);
    const propPart = tr.name.slice(dot);
    if (exactNames.has(bonePart)) return tr;
    const mapped = normMap.get(normBoneName(bonePart));
    if (mapped && mapped !== bonePart) {
      changed = true;
      const cloned = tr.clone();
      cloned.name = mapped + propPart;
      return cloned;
    }
    return tr;
  });

  if (!changed) return clip;
  return new THREE.AnimationClip(clip.name, clip.duration, tracks);
}

function upgradeObjMaterials(obj) {
  const matCache = new Map();
  obj.traverse((child) => {
    if (!child.isMesh) return;
    if (child.geometry && !child.geometry.attributes.normal) {
      child.geometry.computeVertexNormals();
    }
    const upgradeOne = (m) => {
      if (!m) return new THREE.MeshStandardMaterial({ color: 0x3a3e44, roughness: 0.45, metalness: 0.65 });
      const key = `${m.name || ''}_${m.color ? m.color.getHexString() : '555'}`;
      if (matCache.has(key)) return matCache.get(key);
      const col = m.color ? m.color.clone() : new THREE.Color(0x3a3e44);
      const nm = String(m.name || '').toLowerCase();
      const isWood = nm.includes('wood');
      const isDarkMetal = nm.includes('metal') || nm.includes('black') || nm.includes('grey') || nm.includes('gray');
      const isGreen = nm.includes('green') || nm.includes('olive') || nm.includes('tan');
      const std = new THREE.MeshStandardMaterial({
        name: m.name || 'quaternius_gun',
        color: col,
        roughness: isWood ? 0.72 : (isGreen ? 0.62 : (isDarkMetal ? 0.38 : 0.52)),
        metalness: isWood ? 0.06 : (isGreen ? 0.25 : (isDarkMetal ? 0.72 : 0.40))
      });
      matCache.set(key, std);
      return std;
    };
    if (Array.isArray(child.material)) {
      child.material = child.material.map(upgradeOne);
    } else {
      child.material = upgradeOne(child.material);
    }
  });
}

function findBone(root, candidates) {
  let found = null;
  const lowered = candidates.map((c) => c.toLowerCase());
  root.traverse((obj) => {
    if (found || !obj.name) return;
    const nm = obj.name.toLowerCase();
    if (lowered.includes(nm)) found = obj;
  });
  return found;
}

class RigController {
  constructor({ id, meta, group, model, clipsByName, isZombie }) {
    this.id = id;
    this.meta = meta;
    this.group = group;
    this.model = model;
    this.isZombie = !!isZombie;
    this.mixer = new THREE.AnimationMixer(model);
    this.clipsByName = clipsByName;
    this.actions = new Map();
    this.activeAction = null;
    this.activeClipName = null;
    this.disposed = false;

    this.bones = {
      hips: findBone(model, ['Hips', 'Pelvis', 'Body']),
      spine: findBone(model, ['Torso', 'Chest', 'Abdomen', 'Spine']),
      head: findBone(model, ['Head']),
      neck: findBone(model, ['Neck']),
      rightHand: findBone(model, [meta.rightHandBone || 'Wrist.R', 'Hand.R', 'RightHand', 'LowerArm.R']),
      leftHand: findBone(model, ['Wrist.L', 'Hand.L', 'LeftHand', 'LowerArm.L']),
      upperArmL: findBone(model, ['UpperArm.L', 'LeftArm']),
      upperArmR: findBone(model, ['UpperArm.R', 'RightArm'])
    };

    // Montagem de arma acoplada ao osso da mão direita
    this.weaponMount = new THREE.Group();
    this.weaponMount.name = 'v2_weapon_mount';
    const wOff = meta.weaponOffset || { pos: [0.02, 0.08, 0.04], rot: [Math.PI * 0.5, 0, -Math.PI * 0.5], scale: 0.95 };
    this.weaponMount.position.set(wOff.pos[0], wOff.pos[1], wOff.pos[2]);
    this.weaponMount.rotation.set(wOff.rot[0], wOff.rot[1], wOff.rot[2]);
    this.weaponMount.scale.setScalar(wOff.scale || 0.95);
    if (this.bones.rightHand) {
      this.bones.rightHand.add(this.weaponMount);
    } else {
      group.add(this.weaponMount);
    }

    // Configura sombras e desativa frustumCulled em SkinnedMeshes (evita sumir quando osso sai da AABB original)
    model.traverse((obj) => {
      if (obj.isSkinnedMesh || obj.isMesh) {
        obj.castShadow = true;
        obj.receiveShadow = true;
        if (obj.isSkinnedMesh) obj.frustumCulled = false;
      }
    });
  }

  _resolveClipName(key) {
    const map = this.meta.clips || {};
    let entry = map[key];
    if (Array.isArray(entry) && entry.length > 0) {
      entry = entry[0];
    }
    if (entry && this.clipsByName.has(entry)) return entry;

    // Fallbacks seguros quando um clip específico não existe no pacote
    const fallbacks = {
      crouchIdle: ['idleGun', 'idle', 'idleNeutral'],
      crouchWalk: ['walk', 'idle'],
      prone: ['idleNeutral', 'idle'],
      jump: ['roll', 'run', 'idle'],
      crawl: ['walk', 'idle'],
      runShoot: ['run', 'idleGunShoot', 'walk'],
      idleGunAim: ['idleGun', 'idle'],
      idleGunShoot: ['idleGunAim', 'idleGun', 'idle'],
      idleMelee: ['idle', 'idleNeutral'],
      runBack: ['walk', 'run'],
      runLeft: ['walk', 'run'],
      runRight: ['walk', 'run']
    };
    if (entry === null) {
      warnOnce(`missing_clip:${this.id}:${key}`, `Clip '${key}' ausente em '${this.id}', usando fallback seguro.`);
    }
    const cands = fallbacks[key] || ['idle', 'idleNeutral', 'walk'];
    for (const c of cands) {
      let fb = map[c];
      if (Array.isArray(fb)) fb = fb[0];
      if (fb && this.clipsByName.has(fb)) return fb;
    }
    const first = this.clipsByName.keys().next().value;
    return first || null;
  }

  _getAction(clipName) {
    if (!clipName || !this.clipsByName.has(clipName)) return null;
    let act = this.actions.get(clipName);
    if (!act) {
      act = this.mixer.clipAction(this.clipsByName.get(clipName));
      this.actions.set(clipName, act);
    }
    return act;
  }

  play(key, { fade = 0.16, loop = THREE.LoopRepeat, clampWhenFinished = false, timeScale = 1.0, variantIndex = null, forceRestart = false } = {}) {
    if (this.disposed) return null;
    let clipName = null;
    const raw = (this.meta.clips || {})[key];
    if (Array.isArray(raw) && raw.length > 0) {
      const idx = variantIndex !== null ? (Math.abs(variantIndex) % raw.length) : 0;
      if (this.clipsByName.has(raw[idx])) clipName = raw[idx];
    }
    if (!clipName) clipName = this._resolveClipName(key);
    if (!clipName) return null;

    const next = this._getAction(clipName);
    if (!next) return null;

    next.setLoop(loop, loop === THREE.LoopOnce ? 1 : Infinity);
    next.clampWhenFinished = !!clampWhenFinished;
    next.timeScale = Number.isFinite(timeScale) ? timeScale : 1.0;

    if (this.activeClipName === clipName && this.activeAction === next && !forceRestart) {
      if (!next.isRunning() && !clampWhenFinished) next.play();
      return next;
    }

    next.reset();
    next.enabled = true;
    next.setEffectiveWeight(1);
    next.play();
    if (this.activeAction && this.activeAction !== next) {
      this.activeAction.crossFadeTo(next, Math.max(0.02, fade), false);
    }
    this.activeAction = next;
    this.activeClipName = clipName;
    return next;
  }

  setTimeScale(scale) {
    if (this.activeAction && Number.isFinite(scale)) {
      this.activeAction.timeScale = scale;
    }
  }

  update(dt) {
    if (this.disposed || !this.mixer) return;
    if (Number.isFinite(dt) && dt > 0) {
      this.mixer.update(Math.min(0.12, dt));
    }
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    try {
      this.mixer.stopAllAction();
      this.mixer.uncacheRoot(this.model);
    } catch (_) {}
    this.actions.clear();
    if (this.group && this.group.parent) {
      this.group.parent.remove(this.group);
    }
  }
}

export class AssetLibrary {
  constructor() {
    this.version = getAssetVersion();
    this.manifest = null;
    this._manifestPromise = null;
    this.gltfLoader = new GLTFLoader();
    this.objLoader = new OBJLoader();
    this.mtlLoader = new MTLLoader();
    this._glbCache = new Map();
    this._glbPromises = new Map();
    this._weaponCache = new Map();
    this._weaponPromises = new Map();
    this._accessoryCache = new Map();
    this._accessoryPromises = new Map();
    this.loadProgress = { loaded: 0, total: 0 };
  }

  isV2() {
    return this.version === 'v2';
  }

  async loadManifest() {
    if (this.manifest) return this.manifest;
    if (this._manifestPromise) return this._manifestPromise;
    this._manifestPromise = fetch(`${V2_BASE_URL}manifest.json`, { cache: 'no-cache' })
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status} ao carregar manifest.json`);
        return res.json();
      })
      .then((data) => {
        if (!data || !Array.isArray(data.characters) || data.characters.length === 0) {
          throw new Error('manifest.json inválido (sem lista characters)');
        }
        // Valida IDs únicos
        const seen = new Set();
        for (const c of data.characters) {
          if (seen.has(c.id)) warnOnce(`dup_char:${c.id}`, `ID duplicado em manifest.characters: ${c.id}`);
          seen.add(c.id);
        }
        this.manifest = data;
        return data;
      })
      .catch((err) => {
        warnOnce('manifest_err', `Falha ao carregar ${V2_BASE_URL}manifest.json: ${err.message}`);
        this._manifestPromise = null;
        return null;
      });
    return this._manifestPromise;
  }

  getCharacters() {
    return (this.manifest && Array.isArray(this.manifest.characters)) ? this.manifest.characters : [];
  }

  getCharacterMeta(charId) {
    const list = this.getCharacters();
    if (!list.length) return null;
    if (!charId) return list[0];
    const found = list.find((c) => c.id === charId);
    if (found) return found;
    warnOnce(`unknown_char:${charId}`, `Personagem '${charId}' não encontrado no manifesto; usando '${list[0].id}'.`);
    return list[0];
  }

  getZombieMeta(archetypeIdx = 0) {
    const list = (this.manifest && Array.isArray(this.manifest.zombies)) ? this.manifest.zombies : [];
    if (!list.length) return null;
    return list[Math.abs(Math.floor(archetypeIdx)) % list.length];
  }

  getWeaponMeta(weaponId) {
    if (!this.isV2() || !this.manifest || !this.manifest.weapons) return null;
    const entry = this.manifest.weapons[weaponId];
    if (!entry || entry.fallbackV1 || !entry.file) return null;
    return entry;
  }

  getAccessoryMeta(attId) {
    if (!this.isV2() || !this.manifest || !this.manifest.accessories) return null;
    return this.manifest.accessories[attId] || null;
  }

  async _loadGlbAsset(cacheKey, relFile, boneNormalize = true) {
    if (this._glbCache.has(cacheKey)) return this._glbCache.get(cacheKey);
    if (this._glbPromises.has(cacheKey)) return this._glbPromises.get(cacheKey);

    const url = `${V2_BASE_URL}${relFile}`;
    this.loadProgress.total++;
    const p = new Promise((resolve) => {
      this.gltfLoader.load(
        url,
        (gltf) => {
          const clipsByName = new Map();
          for (const rawClip of (gltf.animations || [])) {
            const clip = boneNormalize ? normalizeClipTracks(rawClip, gltf.scene) : rawClip;
            clipsByName.set(clip.name, clip);
          }
          const rec = { gltf, clipsByName };
          this._glbCache.set(cacheKey, rec);
          this.loadProgress.loaded++;
          resolve(rec);
        },
        undefined,
        (err) => {
          warnOnce(`glb_err:${url}`, `Erro ao carregar ${url}: ${err && err.message ? err.message : err}`);
          this._glbPromises.delete(cacheKey);
          this.loadProgress.loaded++;
          resolve(null);
        }
      );
    });
    this._glbPromises.set(cacheKey, p);
    return p;
  }

  async preloadCoreAssets(selectedCharId = 'swat') {
    if (!this.isV2()) return false;
    const m = await this.loadManifest();
    if (!m) return false;
    const tasks = [];
    const ch = this.getCharacterMeta(selectedCharId);
    if (ch) tasks.push(this._loadGlbAsset(`char:${ch.id}`, ch.file, ch.boneNormalize !== false));
    for (const z of (m.zombies || [])) {
      tasks.push(this._loadGlbAsset(`zombie:${z.id}`, z.file, z.boneNormalize !== false));
    }
    await Promise.allSettled(tasks);
    return true;
  }

  async spawnCharacterInstance(charId) {
    if (!this.isV2()) return null;
    await this.loadManifest();
    const meta = this.getCharacterMeta(charId);
    if (!meta) return null;
    const rec = await this._loadGlbAsset(`char:${meta.id}`, meta.file, meta.boneNormalize !== false);
    if (!rec) return null;

    const model = SkeletonUtils.clone(rec.gltf.scene);
    const group = new THREE.Group();
    group.name = `v2_char_${meta.id}`;
    model.scale.setScalar(meta.scale || 1.0);
    model.rotation.y = meta.yawOffset || 0;
    group.add(model);

    return new RigController({
      id: meta.id,
      meta,
      group,
      model,
      clipsByName: rec.clipsByName,
      isZombie: false
    });
  }

  async spawnZombieInstance(archetypeIdx = 0) {
    if (!this.isV2()) return null;
    await this.loadManifest();
    const meta = this.getZombieMeta(archetypeIdx);
    if (!meta) return null;
    const rec = await this._loadGlbAsset(`zombie:${meta.id}`, meta.file, meta.boneNormalize !== false);
    if (!rec) return null;

    const model = SkeletonUtils.clone(rec.gltf.scene);
    const group = new THREE.Group();
    group.name = `v2_zombie_${meta.id}`;
    model.scale.setScalar(meta.scale || 1.0);
    model.rotation.y = meta.yawOffset || 0;
    group.add(model);

    return new RigController({
      id: meta.id,
      meta,
      group,
      model,
      clipsByName: rec.clipsByName,
      isZombie: true
    });
  }

  async loadWeaponObjMtl(weaponId) {
    if (!this.isV2()) return null;
    await this.loadManifest();
    const meta = this.getWeaponMeta(weaponId);
    if (!meta) return null;
    const cacheKey = meta.file;
    if (this._weaponCache.has(cacheKey)) return { obj: this._weaponCache.get(cacheKey), meta };
    if (this._weaponPromises.has(cacheKey)) {
      const obj = await this._weaponPromises.get(cacheKey);
      return obj ? { obj, meta } : null;
    }

    const p = (async () => {
      try {
        const mtlUrl = `${V2_BASE_URL}${meta.mtl}`;
        const objUrl = `${V2_BASE_URL}${meta.file}`;
        const [mtlText, objText] = await Promise.all([
          fetch(mtlUrl).then((r) => { if (!r.ok) throw new Error(`MTL HTTP ${r.status}`); return r.text(); }),
          fetch(objUrl).then((r) => { if (!r.ok) throw new Error(`OBJ HTTP ${r.status}`); return r.text(); })
        ]);
        const materials = this.mtlLoader.parse(mtlText, `${V2_BASE_URL}weapons/`);
        materials.preload();
        const loader = new OBJLoader();
        loader.setMaterials(materials);
        const obj = loader.parse(objText);
        upgradeObjMaterials(obj);
        this._weaponCache.set(cacheKey, obj);
        return obj;
      } catch (err) {
        warnOnce(`weapon_err:${weaponId}`, `Falha ao carregar arma v2 '${weaponId}': ${err.message}`);
        this._weaponPromises.delete(cacheKey);
        return null;
      }
    })();

    this._weaponPromises.set(cacheKey, p);
    const obj = await p;
    return obj ? { obj, meta } : null;
  }

  async loadAccessoryObjMtl(attId) {
    if (!this.isV2()) return null;
    await this.loadManifest();
    const meta = this.getAccessoryMeta(attId);
    if (!meta) return null;
    const cacheKey = meta.file;
    if (this._accessoryCache.has(cacheKey)) return this._accessoryCache.get(cacheKey);
    if (this._accessoryPromises.has(cacheKey)) return this._accessoryPromises.get(cacheKey);

    const p = (async () => {
      try {
        const mtlUrl = `${V2_BASE_URL}${meta.mtl}`;
        const objUrl = `${V2_BASE_URL}${meta.file}`;
        const [mtlText, objText] = await Promise.all([
          fetch(mtlUrl).then((r) => { if (!r.ok) throw new Error(`MTL HTTP ${r.status}`); return r.text(); }),
          fetch(objUrl).then((r) => { if (!r.ok) throw new Error(`OBJ HTTP ${r.status}`); return r.text(); })
        ]);
        const materials = this.mtlLoader.parse(mtlText, `${V2_BASE_URL}accessories/`);
        materials.preload();
        const loader = new OBJLoader();
        loader.setMaterials(materials);
        const obj = loader.parse(objText);
        upgradeObjMaterials(obj);
        this._accessoryCache.set(cacheKey, obj);
        return obj;
      } catch (err) {
        warnOnce(`acc_err:${attId}`, `Falha ao carregar acessório v2 '${attId}': ${err.message}`);
        this._accessoryPromises.delete(cacheKey);
        return null;
      }
    })();

    this._accessoryPromises.set(cacheKey, p);
    return p;
  }

  disposeInstance(inst) {
    if (inst && typeof inst.dispose === 'function') {
      inst.dispose();
    }
  }
}

export const assetLibrary = new AssetLibrary();
