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
const _ikS = new THREE.Vector3();
const _ikE0 = new THREE.Vector3();
const _ikW0 = new THREE.Vector3();
const _ikToT = new THREE.Vector3();
const _ikDir = new THREE.Vector3();
const _ikBend = new THREE.Vector3();
const _ikDesE = new THREE.Vector3();
const _ikCurD = new THREE.Vector3();
const _ikDesD = new THREE.Vector3();
const _ikQW = new THREE.Quaternion();
const _ikQP = new THREE.Quaternion();
const _ikQPInv = new THREE.Quaternion();
const _ikRightTgt = new THREE.Vector3();
const _ikLeftTgt = new THREE.Vector3();
const _ikPoleR = new THREE.Vector3();
const _ikPoleL = new THREE.Vector3();
const _ikGrpQ = new THREE.Quaternion();
const _ikHandQ = new THREE.Quaternion();
const _ikGunQ = new THREE.Quaternion();
const _ikGunEuler = new THREE.Euler(0, 0, 0, 'YXZ');

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
      footL: findBone(model, ['Foot.L', 'LeftFoot']),
      footR: findBone(model, ['Foot.R', 'RightFoot']),
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

  _solveArmWorldIK(upperBone, lowerBone, endBone, targetWorld, poleDirWorld) {
    if (!upperBone || !lowerBone || !endBone || !upperBone.parent) return;
    this._saveBonePose(upperBone);
    this._saveBonePose(lowerBone);

    upperBone.getWorldPosition(_ikS);
    lowerBone.getWorldPosition(_ikE0);
    endBone.getWorldPosition(_ikW0);
    const L1 = _ikS.distanceTo(_ikE0);
    const L2 = _ikE0.distanceTo(_ikW0);
    if (L1 < 1e-4 || L2 < 1e-4) return;

    _ikToT.copy(targetWorld).sub(_ikS);
    const rawDist = _ikToT.length();
    const minD = Math.abs(L1 - L2) + 0.015;
    const maxD = (L1 + L2) * 0.992;
    const d = THREE.MathUtils.clamp(rawDist, minD, maxD);
    if (rawDist > 1e-5) _ikDir.copy(_ikToT).divideScalar(rawDist);
    else _ikDir.set(0, 0, -1);

    const cosA = THREE.MathUtils.clamp((L1 * L1 + d * d - L2 * L2) / (2 * L1 * d), -1, 1);
    const sinA = Math.sqrt(Math.max(0, 1 - cosA * cosA));

    _ikBend.copy(poleDirWorld).addScaledVector(_ikDir, -poleDirWorld.dot(_ikDir));
    if (_ikBend.lengthSq() < 1e-6) {
      _ikBend.set(0, -1, 0).addScaledVector(_ikDir, -_ikDir.y);
    }
    _ikBend.normalize();

    _ikDesE.copy(_ikS).addScaledVector(_ikDir, L1 * cosA).addScaledVector(_ikBend, L1 * sinA);

    _ikCurD.copy(_ikE0).sub(_ikS).normalize();
    _ikDesD.copy(_ikDesE).sub(_ikS).normalize();
    _ikQW.setFromUnitVectors(_ikCurD, _ikDesD);
    upperBone.parent.getWorldQuaternion(_ikQP);
    _ikQPInv.copy(_ikQP).invert();
    upperBone.quaternion.premultiply(_ikQPInv.multiply(_ikQW).multiply(_ikQP));
    upperBone.updateMatrixWorld(true);

    lowerBone.getWorldPosition(_ikE0);
    endBone.getWorldPosition(_ikW0);
    _ikCurD.copy(_ikW0).sub(_ikE0).normalize();
    _ikDesD.copy(targetWorld).sub(_ikE0).normalize();
    _ikQW.setFromUnitVectors(_ikCurD, _ikDesD);
    lowerBone.parent.getWorldQuaternion(_ikQP);
    _ikQPInv.copy(_ikQP).invert();
    lowerBone.quaternion.premultiply(_ikQPInv.multiply(_ikQW).multiply(_ikQP));
    lowerBone.updateMatrixWorld(true);
  }

  applyStancePosture({
    crouchAlpha = 0,
    proneAlpha = 0,
    isMoving = false,
    isSprinting = false,
    inCombat = false,
    isMelee = false,
    isTwoHand = false,
    isThrow = false,
    weaponId = '',
    pitch = 0,
    recoilKick = 0,
    reloading = false,
    reloadProgress = 0,
    walkPhase = 0,
    crawlPhase = 0
  } = {}) {
    if (this.disposed || this.isZombie) return;
    const p = THREE.MathUtils.clamp(proneAlpha || 0, 0, 1);
    const c = THREE.MathUtils.clamp(crouchAlpha || 0, 0, 1) * (1 - p);
    const holdGun3P = !isMelee && !isThrow && p < 0.5;
    if (c < 0.005 && p < 0.005 && !holdGun3P) return;

    const b = this.bones;
    this.group.updateMatrixWorld(true);

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
      this._rotateBoneModelAxis(b.torso, 1, 0, 0, 0.24 * c);
      this._rotateBoneModelAxis(b.head, 1, 0, 0, -0.20 * c);
    }

    // Empunhadura tática de DUAS MÃOS em 3ª pessoa (Mirando + Guarda de Lado + Correndo com a Arma de Lado no Peito!)
    if (holdGun3P && b.upperArmR && b.lowerArmR && b.rightHand && b.upperArmL && b.lowerArmL && b.leftHand) {
      const targetSprint = (isMoving && isSprinting && !inCombat && !reloading) ? 1 : 0;
      const targetAim = (inCombat && !targetSprint) ? 1 : 0;
      this._sprintBlend = THREE.MathUtils.lerp(this._sprintBlend ?? 0, targetSprint, 0.22);
      this._aimBlend = THREE.MathUtils.lerp(this._aimBlend ?? 0, targetAim, 0.24);
      const spB = this._sprintBlend;
      const aimB = this._aimBlend * (1 - spB);
      const lowB = Math.max(0, 1 - spB - aimB);

      const aimPitch = THREE.MathUtils.clamp(pitch || 0, -0.88, 0.88) * aimB;
      if (Math.abs(aimPitch) > 0.005) {
        // No model Quaternius (+Z = frente do personagem), rotacionar em -X inclina peito/cabeça para cima quando pitch > 0
        this._rotateBoneModelAxis(b.torso, 1, 0, 0, -aimPitch * 0.32);
        this._rotateBoneModelAxis(b.chest, 1, 0, 0, -aimPitch * 0.36);
        this._rotateBoneModelAxis(b.head, 1, 0, 0, -aimPitch * 0.32);
      }

      const bob = isMoving ? Math.sin((walkPhase || 0) * (isSprinting ? 1.0 : 0.85)) : 0;
      const crouchDrop = c * 0.31;
      const chestBaseY = 1.24 - crouchDrop;

      // Posição da mão direita (empunhadura) no espaço de this.group (+X = direita, -X = esquerda, +Y = cima, -Z = frente)
      let rhX, rhY, rhZ, gunPitch, gunYaw, gunRoll;
      if (isTwoHand) {
        rhX = 0.14 * aimB + 0.14 * lowB + (0.11 + bob * 0.015) * spB;
        rhY = (chestBaseY + 0.08 + Math.sin(aimPitch) * 0.08) * aimB
            + (chestBaseY - 0.06 + Math.abs(bob) * 0.008) * lowB
            + (chestBaseY - 0.03 + bob * 0.018) * spB;
        rhZ = (-0.21 + recoilKick * 0.09) * aimB
            + (-0.22) * lowB
            + (-0.21) * spB;

        // Orientação da arma:
        // - aimB: reta para o alvo (-Z) com pitch real!
        // - lowB (parado/andando): segurada com as 2 mãos levemente de lado (~30° p/ esquerda) em guarda baixa!
        // - spB (correndo): segurada com as 2 mãos atravessada de lado no peito (~52° p/ esquerda + cano firme)!
        gunPitch = (aimPitch + recoilKick * 0.45) * aimB + (-0.18) * lowB + (0.18 + bob * 0.05) * spB;
        gunYaw   = (0.04) * aimB + (0.52) * lowB + (0.90 + bob * 0.04) * spB;
        gunRoll  = (0.0) * aimB + (0.12) * lowB + (0.24) * spB;
      } else {
        // Pistolas / Revólver: empunhadura dupla (2 mãos juntas no punho!) tanto mirando quanto parado/correndo
        rhX = 0.05 * aimB + 0.07 * lowB + (0.06 + bob * 0.014) * spB;
        rhY = (chestBaseY + 0.11 + Math.sin(aimPitch) * 0.12) * aimB
            + (chestBaseY - 0.05) * lowB
            + (chestBaseY + 0.01 + bob * 0.018) * spB;
        rhZ = (-0.34 + recoilKick * 0.08) * aimB
            + (-0.25) * lowB
            + (-0.22) * spB;

        gunPitch = (aimPitch + recoilKick * 0.55) * aimB + (-0.24) * lowB + (0.34 + bob * 0.05) * spB;
        gunYaw   = (0.02) * aimB + (0.24) * lowB + (0.48) * spB;
        gunRoll  = 0.0;
      }

      this.group.getWorldQuaternion(_ikGrpQ);
      _ikRightTgt.set(rhX, rhY, rhZ);
      this.group.localToWorld(_ikRightTgt);
      _ikPoleR.set(0.45, -1.0, 0.32).applyQuaternion(_ikGrpQ).normalize();

      // 1) Resolve Braço Direito levando Wrist.R exatamente até a empunhadura!
      this._solveArmWorldIK(b.upperArmR, b.lowerArmR, b.rightHand, _ikRightTgt, _ikPoleR);

      // 2) Orienta weaponMount para que o cano da arma fique exatamente no ângulo tático (imune a torções do clip!)
      _ikGunEuler.set(gunPitch, gunYaw, gunRoll, 'YXZ');
      _ikGunQ.copy(_ikGrpQ).multiply(_postureQLoc.setFromEuler(_ikGunEuler));
      b.rightHand.getWorldQuaternion(_ikHandQ);
      this.weaponMount.position.set(0, 0.055, 0);
      this.weaponMount.quaternion.copy(_ikHandQ).invert().multiply(_ikGunQ);
      this.weaponMount.scale.setScalar(this._gunOffset.scale || 0.95);
      this.weaponMount.updateMatrixWorld(true);
      this._weaponHoldMode = 'gun_ik';

      // 3) Calcula o ponto exato do guarda-mão (ou punho duplo em pistola) na arma equipada e resolve IK do Braço Esquerdo!
      const activeAsm = (this.weaponMap && weaponId) ? this.weaponMap[weaponId] : null;
      if (isTwoHand) {
        const u = activeAsm && activeAsm.underPos ? activeAsm.underPos : null;
        const fx = u ? u.x : 0;
        const fy = u ? (u.y - 0.015) : 0.01;
        const fz = u ? THREE.MathUtils.clamp(u.z, -0.34, -0.16) : -0.24;
        // Durante a recarga, a mão esquerda desce até o carregador e sobe de volta!
        if (reloading && reloadProgress > 0.10 && reloadProgress < 0.85) {
          const dip = Math.sin(((reloadProgress - 0.10) / 0.75) * Math.PI);
          _ikLeftTgt.set(fx, THREE.MathUtils.lerp(fy, -0.12, dip), THREE.MathUtils.lerp(fz, -0.05, dip));
        } else {
          _ikLeftTgt.set(fx, fy, fz);
        }
      } else {
        // Pistola: mão esquerda envolvendo o punho junto à mão direita!
        if (reloading && reloadProgress > 0.12 && reloadProgress < 0.82) {
          const dip = Math.sin(((reloadProgress - 0.12) / 0.70) * Math.PI);
          _ikLeftTgt.set(-0.02, -0.02 - dip * 0.14, 0.01 + dip * 0.04);
        } else {
          _ikLeftTgt.set(-0.022, -0.014, 0.016);
        }
      }
      this.weaponMount.localToWorld(_ikLeftTgt);
      _ikPoleL.set(-0.48, -1.0, 0.28).applyQuaternion(_ikGrpQ).normalize();
      this._solveArmWorldIK(b.upperArmL, b.lowerArmL, b.leftHand, _ikLeftTgt, _ikPoleL);
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

  applyVehiclePosture({ isMoto, carSeat, carLeanAlpha }, vehicle) {
    const frame = vehicle.bodyGroup;
    const b = this.bones;
    if (!b.body) return;
    const driver = carSeat === 0;
    const aiming = !driver && carLeanAlpha > 0.15;
    const seat = vehicle.seatOffsets?.[carSeat];
    if (!seat) return;
    const world = (x, y, z) => frame.localToWorld(new THREE.Vector3(x, y, z));
    this.group.updateWorldMatrix(true, true);
    const hipHeight = isMoto ? (driver ? 0.94 : 1.03) : 0.65;
    const pelvis = world(seat.x + (!isMoto ? seat.side * carLeanAlpha * 0.50 : 0), hipHeight, seat.z);
    const hip = this.group.parent.worldToLocal(b.body.getWorldPosition(new THREE.Vector3()));
    this.group.position.add(this.group.parent.worldToLocal(pelvis).sub(hip));
    if (isMoto && driver) this._rotateBoneModelAxis(b.abdomen || b.torso, 1, 0, 0, 0.62);
    const aimBone = (bone, from, to) => {
      this._saveBonePose(bone);
      const inv = bone.parent.getWorldQuaternion(new THREE.Quaternion()).invert();
      const rotation = new THREE.Quaternion().setFromUnitVectors(from.normalize().applyQuaternion(inv), to.normalize().applyQuaternion(inv));
      bone.quaternion.premultiply(rotation);
      bone.updateWorldMatrix(false, true);
    };
    const reach = (upper, lower, end, target, bendPoint) => {
      if (!upper || !lower || !end) return;
      const start = upper.getWorldPosition(new THREE.Vector3());
      const knee = lower.getWorldPosition(new THREE.Vector3());
      const tip = end.getWorldPosition(new THREE.Vector3());
      const first = start.distanceTo(knee), second = knee.distanceTo(tip);
      if (Math.min(first, second) < 0.01) return;
      const tipLocal = lower.worldToLocal(tip.clone());
      const along = target.clone().sub(start);
      const distance = THREE.MathUtils.clamp(along.length(), Math.abs(first - second) + 0.001, first + second - 0.001);
      along.normalize();
      const bend = bendPoint.sub(start);
      bend.addScaledVector(along, -bend.dot(along)).normalize();
      const projection = (first * first + distance * distance - second * second) / (2 * distance);
      const towardKnee = along.clone().multiplyScalar(projection).addScaledVector(bend, Math.sqrt(Math.max(0, first * first - projection * projection)));
      aimBone(upper, knee.sub(start), towardKnee);
      lower.getWorldPosition(knee);
      aimBone(lower, lower.localToWorld(tipLocal.clone()).sub(knee), start.addScaledVector(along, distance).sub(knee));
      if (end.parent !== lower) {
        this._saveBonePose(end);
        end.position.copy(end.parent.worldToLocal(lower.localToWorld(tipLocal)));
      }
    };
    for (const [side, sign, hand] of [['L', -1, b.leftHand], ['R', 1, b.rightHand]]) {
      const footX = seat.x + sign * (isMoto ? 0.25 : 0.14);
      reach(b['upperLeg' + side], b['lowerLeg' + side], b['foot' + side],
        world(footX, isMoto ? (driver ? 0.40 : 0.52) : 0.21, seat.z - (isMoto ? 0.04 : 0.35)),
        world(footX + (isMoto ? sign * 0.18 : 0), hipHeight, seat.z - 1));
      if (aiming) continue;
      const handle = isMoto && driver && vehicle.wheels.find(wheel => wheel.isFront)?.steerPivot;
      let grip = world(seat.x + sign * 0.19, hipHeight + 0.12, seat.z - 0.12);
      if (handle) grip = handle.localToWorld(new THREE.Vector3(sign * 0.31, 0.74, 0.27));
      else if (driver && vehicle.steerWheel) grip = vehicle.steerWheel.localToWorld(new THREE.Vector3(sign * 0.15, 0, 0));
      reach(b['upperArm' + side], b['lowerArm' + side], hand, grip,
        world(seat.x + sign * 0.42, hipHeight, seat.z + 0.18));
    }
  }

  prepareZombieFall() {
    const meshes = [];
    const bones = new Set();
    this.model.traverseVisible(mesh => {
      if (!mesh.isSkinnedMesh) return;
      meshes.push(mesh);
      for (const bone of mesh.skeleton.bones) bones.add(bone);
    });

    const pose = Array.from(bones, bone => ({
      bone, startPosition: bone.position.clone(), startRotation: bone.quaternion.clone()
    }));
    for (const mesh of meshes) mesh.skeleton.pose();

    // Com o modelo ainda em pé, deixe braços e pernas apontados para os pés.
    // A inclinação do corpo transforma essa pose em repouso de costas.
    const modelRotation = this.model.getWorldQuaternion(new THREE.Quaternion());
    const relaxLimb = (bone, end, x, z) => {
      if (!bone || !end) return;
      const direction = end.getWorldPosition(new THREE.Vector3())
        .sub(bone.getWorldPosition(new THREE.Vector3())).normalize();
      const target = new THREE.Vector3(x, -1, z).normalize().applyQuaternion(modelRotation);
      const worldRotation = bone.getWorldQuaternion(new THREE.Quaternion());
      const inverseParent = bone.parent.getWorldQuaternion(new THREE.Quaternion()).invert();
      bone.quaternion.setFromUnitVectors(direction, target).multiply(worldRotation).premultiply(inverseParent);
    };
    const b = this.bones;
    relaxLimb(b.upperArmL, b.lowerArmL, 0.42, 0.03);
    relaxLimb(b.lowerArmL, b.leftHand, 0.24, 0.15);
    relaxLimb(b.upperArmR, b.lowerArmR, -0.29, 0.04);
    relaxLimb(b.lowerArmR, b.rightHand, -0.14, 0.18);
    relaxLimb(b.upperLegL, b.lowerLegL, 0.12, 0.03);
    relaxLimb(b.upperLegR, b.lowerLegR, -0.16, 0.04);

    for (const joint of pose) {
      joint.restPosition = joint.bone.position.clone();
      joint.restRotation = joint.bone.quaternion.clone();
    }

    const groundY = this.group.getWorldPosition(new THREE.Vector3()).y;
    this.group.rotation.x = Math.PI / 2;
    this.group.updateMatrixWorld(true);
    const bounds = new THREE.Box3();
    for (const mesh of meshes) bounds.expandByObject(mesh, true);
    const parentScale = this.group.parent?.getWorldScale(new THREE.Vector3()).y ?? 1;
    this.fallClearance = bounds.isEmpty() ? 0 : (groundY - bounds.min.y + 0.015) / parentScale;
    this.fallPose = pose;
  }

  updateZombieFall(progress) {
    if (this.fallSettled) return;
    if (!this.fallPose) this.prepareZombieFall();
    const tilt = THREE.MathUtils.smoothstep(progress, 0, 0.88);
    const relax = THREE.MathUtils.smoothstep(progress, 0.08, 1);
    for (const joint of this.fallPose) {
      joint.bone.position.lerpVectors(joint.startPosition, joint.restPosition, relax);
      joint.bone.quaternion.slerpQuaternions(joint.startRotation, joint.restRotation, relax);
    }
    this.group.rotation.x = tilt * Math.PI / 2;
    this.group.position.y = this.fallClearance * tilt;
    if (progress >= 1) {
      this.fallSettled = true;
      this.fallPose = null;
    }
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
        attack: ['ZombieAttack', 'ZombieBite'], hit: 'ZombieIdle' } },
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
