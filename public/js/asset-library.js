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
      const isGlass = nm.includes('glass') || nm.includes('lens') || nm.includes('optic');
      const isDarkMetal = nm.includes('metal') || nm.includes('black') || nm.includes('grey') || nm.includes('gray') || nm.includes('main');
      const isGreen = nm.includes('green') || nm.includes('olive') || nm.includes('tan');
      // MTLs do Quaternius exportados em linear-RGB têm Kd muito baixo (ex.: 0.016); converte para gama legível sem virar silhueta preta!
      if (!isGlass) {
        const maxC = Math.max(col.r, col.g, col.b);
        if (maxC > 0.0005 && maxC < 0.25) {
          col.setRGB(
            Math.min(1, Math.pow(col.r, 1 / 2.2)),
            Math.min(1, Math.pow(col.g, 1 / 2.2)),
            Math.min(1, Math.pow(col.b, 1 / 2.2))
          );
        }
        const floorVal = isWood ? 0.12 : 0.14;
        col.r = Math.max(floorVal, col.r);
        col.g = Math.max(floorVal, col.g);
        col.b = Math.max(floorVal, col.b);
      }
      const std = isGlass
        ? new THREE.MeshStandardMaterial({
            name: m.name || 'quaternius_glass',
            color: new THREE.Color(0x58c4e8),
            roughness: 0.08,
            metalness: 0.12,
            transparent: true,
            opacity: 0.22,
            depthWrite: false
          })
        : new THREE.MeshStandardMaterial({
            name: m.name || 'quaternius_gun',
            color: col,
            roughness: isWood ? 0.68 : (isGreen ? 0.58 : (isDarkMetal ? 0.44 : 0.50)),
            metalness: isWood ? 0.06 : (isGreen ? 0.16 : (isDarkMetal ? 0.26 : 0.22))
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

// Os OBJ do Gun Pack trazem cores de material. Reutilize os acabamentos
// do arsenal; alguns OBJ também precisam de coordenadas para a textura.
const packSurfaceMaps = new Map();
const surfaceTextureLoader = new THREE.TextureLoader();
function getPackSurfaceMap(channel) {
  if (!packSurfaceMaps.has(channel)) {
    const folder = channel === 'wood' ? 'ak-74m_rifle_ak' : 'm41-t_fuzil';
    const url = `/assets/3d/weapons/01_fuzis/${folder}/textures/${channel}_albedo.png`;
    const texture = surfaceTextureLoader.load(url);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
    packSurfaceMaps.set(channel, texture);
  }
  return packSurfaceMaps.get(channel);
}

function texturePackWeapon(obj) {
  obj.traverse(mesh => {
    if (!mesh.isMesh) return;
    const geo = mesh.geometry;
    if (!geo.getAttribute('uv')) {
      const pos = geo.getAttribute('position'), normal = geo.getAttribute('normal');
      const uv = new Float32Array(pos.count * 2);
      for (let i = 0; i < pos.count; i++) {
        const x = Math.abs(normal.getX(i)), y = Math.abs(normal.getY(i)), z = Math.abs(normal.getZ(i));
        uv[i * 2] = x > y && x > z ? pos.getZ(i) : pos.getX(i);
        uv[i * 2 + 1] = y >= x && y > z ? pos.getZ(i) : pos.getY(i);
      }
      geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    }
    for (const mat of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
      if (mat.transparent || mat.map) continue;
      const channel = /wood/i.test(mat.name) ? 'wood' : /black/i.test(mat.name) ? 'polymer' : 'metal';
      mat.map = getPackSurfaceMap(channel);
      mat.color.lerp(new THREE.Color(0xffffff), 0.45);
      mat.needsUpdate = true;
    }
  });
}

const _postureAxis = new THREE.Vector3();
const _postureQ1 = new THREE.Quaternion();
const _postureQ2 = new THREE.Quaternion();
const _postureQ3 = new THREE.Quaternion();
const _postureQLoc = new THREE.Quaternion();

function findBone(root, candidates) {
  const byExact = new Map();
  const byNorm = new Map();
  root.traverse((obj) => {
    if (!obj.name) return;
    const low = obj.name.toLowerCase();
    const norm = normBoneName(obj.name);
    if (!byExact.has(low) || (obj.isBone && !byExact.get(low).isBone)) {
      byExact.set(low, obj);
    }
    if (norm && (!byNorm.has(norm) || (obj.isBone && !byNorm.get(norm).isBone))) {
      byNorm.set(norm, obj);
    }
  });
  for (const cand of candidates) {
    if (!cand) continue;
    const low = String(cand).toLowerCase();
    if (byExact.has(low)) return byExact.get(low);
    const norm = normBoneName(cand);
    if (norm && byNorm.has(norm)) return byNorm.get(norm);
  }
  return null;
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
    this._savedBonePoses = new Map();

    this.bones = {
      body: findBone(model, ['Body', 'Hips', 'Pelvis']),
      hips: findBone(model, ['Hips', 'Pelvis', 'Body']),
      abdomen: findBone(model, ['Abdomen', 'Spine']),
      torso: findBone(model, ['Torso', 'Spine1', 'Spine']),
      chest: findBone(model, ['Chest', 'Spine2', 'UpperChest']),
      spine: findBone(model, ['Torso', 'Chest', 'Abdomen', 'Spine']),
      head: findBone(model, ['Head']),
      neck: findBone(model, ['Neck']),
      upperLegL: findBone(model, ['UpperLeg.L', 'LeftUpLeg', 'Thigh.L']),
      lowerLegL: findBone(model, ['LowerLeg.L', 'LeftLeg', 'Shin.L']),
      upperLegR: findBone(model, ['UpperLeg.R', 'RightUpLeg', 'Thigh.R']),
      lowerLegR: findBone(model, ['LowerLeg.R', 'RightLeg', 'Shin.R']),
      rightHand: findBone(model, [meta.rightHandBone || 'Wrist.R', 'Hand.R', 'RightHand', 'LowerArm.R']),
      leftHand: findBone(model, ['Wrist.L', 'Hand.L', 'LeftHand', 'LowerArm.L']),
      shoulderL: findBone(model, ['Shoulder.L', 'LeftShoulder']),
      shoulderR: findBone(model, ['Shoulder.R', 'RightShoulder']),
      upperArmL: findBone(model, ['UpperArm.L', 'LeftArm']),
      lowerArmL: findBone(model, ['LowerArm.L', 'LeftForeArm']),
      upperArmR: findBone(model, ['UpperArm.R', 'RightArm']),
      lowerArmR: findBone(model, ['LowerArm.R', 'RightForeArm'])
    };

    // Montagem de arma acoplada ao osso da mão direita (suporta modo 'gun' e 'melee')
    this.weaponMount = new THREE.Group();
    this.weaponMount.name = 'v2_weapon_mount';
    this._gunOffset = meta.weaponOffset || { pos: [0.0, 0.085, -0.015], rot: [Math.PI * 0.5, 0, Math.PI * 0.5], scale: 0.95 };
    this._meleeOffset = meta.meleeOffset || { pos: [0.0, 0.085, -0.01], rot: [0, Math.PI * 0.5, Math.PI], scale: 0.95 };
    this._weaponHoldMode = null;
    this.setWeaponHoldMode('gun');
    if (this.bones.rightHand) {
      this.bones.rightHand.add(this.weaponMount);
    } else {
      group.add(this.weaponMount);
    }

    // Configura sombras, desativa frustumCulled em SkinnedMeshes e oculta armas embutidas nos GLBs (ex.: Pistol / Pistol_1..3 em swat/suit)
    const BAKED_WEAPON_RE = /^(pistol|gun|rifle|sword|knife|weapon|dagger|shotgun)([._\-\s]\d+)?$/i;
    model.traverse((obj) => {
      const cleanName = String(obj.name || '').trim();
      if (BAKED_WEAPON_RE.test(cleanName)) {
        obj.visible = false;
        obj.traverse((sub) => {
          sub.visible = false;
          if (sub.isMesh || sub.isSkinnedMesh) {
            sub.castShadow = false;
            sub.receiveShadow = false;
          }
        });
        return;
      }
      if (obj.isSkinnedMesh || obj.isMesh) {
        let p = obj.parent;
        while (p && p !== model) {
          if (BAKED_WEAPON_RE.test(String(p.name || '').trim())) {
            obj.visible = false;
            obj.castShadow = false;
            obj.receiveShadow = false;
            return;
          }
          p = p.parent;
        }
        obj.castShadow = true;
        obj.receiveShadow = true;
        obj.frustumCulled = false;
      }
    });
  }

  _restorePostureOverrides() {
    if (this._savedBonePoses.size === 0) return;
    for (const [bone, saved] of this._savedBonePoses) {
      bone.position.copy(saved.pos);
      bone.quaternion.copy(saved.quat);
    }
    this._savedBonePoses.clear();
  }

  _saveBonePose(bone) {
    if (!bone || this._savedBonePoses.has(bone)) return;
    this._savedBonePoses.set(bone, {
      pos: bone.position.clone(),
      quat: bone.quaternion.clone()
    });
  }

  _rotateBoneModelAxis(bone, ax, ay, az, angleRad) {
    if (!bone || !bone.parent || !Number.isFinite(angleRad) || Math.abs(angleRad) < 1e-4) return;
    this._saveBonePose(bone);
    this.model.getWorldQuaternion(_postureQ1);
    bone.parent.getWorldQuaternion(_postureQ2);
    _postureQ3.copy(_postureQ2).invert().multiply(_postureQ1);
    _postureAxis.set(ax, ay, az).applyQuaternion(_postureQ3).normalize();
    _postureQLoc.setFromAxisAngle(_postureAxis, angleRad);
    bone.quaternion.premultiply(_postureQLoc);
    bone.updateMatrixWorld(true);
  }

  applyStancePosture({ crouchAlpha = 0, proneAlpha = 0, isMoving = false, isMelee = false, isTwoHand = false, crawlPhase = 0 } = {}) {
    if (this.disposed || this.isZombie) return;
    const p = THREE.MathUtils.clamp(proneAlpha || 0, 0, 1);
    const c = THREE.MathUtils.clamp(crouchAlpha || 0, 0, 1) * (1 - p);
    const twoHandSupport = (!isMelee && isTwoHand && p < 0.5) ? (1 - p * 2) : 0;
    if (c < 0.005 && p < 0.005 && twoHandSupport < 0.01) return;

    const b = this.bones;
    this.model.updateMatrixWorld(true);

    if (c >= 0.005) {
      if (b.body) {
        this._saveBonePose(b.body);
        b.body.position.y -= 0.34 * c;
        b.body.position.z -= 0.05 * c;
        b.body.updateMatrixWorld(true);
      }
      // Dobra real de quadril e joelhos mantendo os pés plantados no chão (y = 0)
      this._rotateBoneModelAxis(b.upperLegL, 1, 0, 0, -0.98 * c);
      this._rotateBoneModelAxis(b.lowerLegL, 1, 0, 0, 1.58 * c);
      this._rotateBoneModelAxis(b.upperLegR, 1, 0, 0, -0.98 * c);
      this._rotateBoneModelAxis(b.lowerLegR, 1, 0, 0, 1.58 * c);
      this._rotateBoneModelAxis(b.torso, 1, 0, 0, 0.26 * c);
      this._rotateBoneModelAxis(b.head, 1, 0, 0, -0.22 * c);
      if (!isMelee) {
        this._rotateBoneModelAxis(b.upperArmR, 1, 0, 0, -0.18 * c);
      }
    }

    // Armas longas 2-mãos em 3ª pessoa: ergue o braço esquerdo para apoiar o guarda-mão do fuzil em vez de ficar solto ao lado do corpo
    if (twoHandSupport >= 0.01) {
      this._rotateBoneModelAxis(b.shoulderL, 0, 1, 0, -0.26 * twoHandSupport);
      this._rotateBoneModelAxis(b.upperArmL, 1, 0, 0, -1.26 * twoHandSupport);
      this._rotateBoneModelAxis(b.upperArmL, 0, 1, 0, -0.44 * twoHandSupport);
      this._rotateBoneModelAxis(b.lowerArmL, 0, 1, 0, -0.26 * twoHandSupport);
    }

    if (p >= 0.005) {
      const wave = isMoving ? Math.sin(crawlPhase || 0) : 0;
      // Ergue tórax e cabeça para olhar e mirar à frente deitado (sem enfiar o rosto/arma no asfalto)
      this._rotateBoneModelAxis(b.torso, 1, 0, 0, -0.22 * p);
      this._rotateBoneModelAxis(b.chest, 1, 0, 0, -0.20 * p);
      this._rotateBoneModelAxis(b.neck, 1, 0, 0, -0.34 * p);
      this._rotateBoneModelAxis(b.head, 1, 0, 0, -0.34 * p);
      this._rotateBoneModelAxis(b.upperArmR, 1, 0, 0, (-0.98 + wave * 0.14) * p);
      this._rotateBoneModelAxis(b.upperArmL, 1, 0, 0, (-1.05 - wave * 0.18) * p);
      this._rotateBoneModelAxis(b.upperLegL, 0, 0, 1, -0.14 * p);
      this._rotateBoneModelAxis(b.upperLegR, 0, 0, 1, 0.14 * p);
      if (isMoving) {
        this._rotateBoneModelAxis(b.lowerLegL, 1, 0, 0, (0.18 + Math.max(0, wave) * 0.34) * p);
        this._rotateBoneModelAxis(b.lowerLegR, 1, 0, 0, (0.18 + Math.max(0, -wave) * 0.34) * p);
      }
    }
  }

  setWeaponHoldMode(mode = 'gun') {
    const nextMode = mode === 'melee' ? 'melee' : 'gun';
    if (this._weaponHoldMode === nextMode) return;
    this._weaponHoldMode = nextMode;
    const off = nextMode === 'melee' ? this._meleeOffset : this._gunOffset;
    this.weaponMount.position.set(off.pos[0], off.pos[1], off.pos[2]);
    this.weaponMount.rotation.set(off.rot[0], off.rot[1], off.rot[2]);
    this.weaponMount.scale.setScalar(off.scale || 0.95);
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
    this._restorePostureOverrides();
    if (Number.isFinite(dt) && dt > 0) {
      this.mixer.update(Math.min(0.12, dt));
    }
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this._savedBonePoses.clear();
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
    if (!this.manifest || !this.manifest.weapons) return null;
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
    tasks.push(this.loadZombiePack());
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

  loadZombiePack() {
    if (!this.zombiePack) {
      this.zombiePack = fetch('/assets/v2/zombies/quaternius-clips.json').then(response => {
        if (!response.ok) throw new Error('Falha ao carregar movimentos Quaternius');
        return response.json();
      }).then(pack => {
        const clips = new Map();
        for (const { name, times, tracks, positions } of pack) {
          const rotations = Object.entries(tracks).map(([bone, values]) =>
            new THREE.QuaternionKeyframeTrack(THREE.PropertyBinding.sanitizeNodeName(bone) + '.quaternion', times, values));
          for (const [bone, values] of Object.entries(positions || {})) {
            rotations.push(new THREE.VectorKeyframeTrack(THREE.PropertyBinding.sanitizeNodeName(bone) + '.position', times, values));
          }
          clips.set(name, new THREE.AnimationClip(name, -1, rotations));
        }
        // O pacote não tem queda. Incline o modelo sobre os pés ao morrer.
        clips.set('Fall', new THREE.AnimationClip('Fall', 0.55, [
          new THREE.NumberKeyframeTrack('.rotation[x]', [0, 0.18, 0.55], [0, -0.22, -Math.PI / 2])
        ]));
        return clips;
      }).catch(error => {
        this.zombiePack = null;
        warnOnce('zombie_pack', String(error));
        return null;
      });
    }
    return this.zombiePack;
  }

  async spawnZombieInstance(archetypeIdx = 0) {
    if (!this.isV2()) return null;
    await this.loadManifest();
    const meta = this.getZombieMeta(archetypeIdx);
    if (!meta) return null;
    const [rec, clips] = await Promise.all([
      this._loadGlbAsset('zombie:' + meta.id, meta.file, meta.boneNormalize !== false),
      this.loadZombiePack()
    ]);
    if (!rec || !clips) return null;

    const model = SkeletonUtils.clone(rec.gltf.scene);
    // Estes GLBs foram salvos em pose de ação; o retarget usa a pose de bind.
    model.traverse(mesh => { if (mesh.isSkinnedMesh) mesh.skeleton.pose(); });
    const group = new THREE.Group();
    group.name = `v2_zombie_${meta.id}`;
    model.scale.setScalar(meta.scale || 1.0);
    model.rotation.y = meta.yawOffset || 0;
    group.add(model);

    return new RigController({
      id: meta.id,
      meta: { ...meta, clips: { idle: 'ZombieIdle', walk: 'ZombieWalk', run: 'ZombieRun', crawl: 'ZombieCrawl',
        attack: ['ZombieAttack', 'ZombieBite'], hit: 'ZombieIdle', death: 'Fall' } },
      group,
      model,
      clipsByName: clips,
      isZombie: true
    });
  }

  async loadWeaponObjMtl(weaponId) {
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
        texturePackWeapon(obj);
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
