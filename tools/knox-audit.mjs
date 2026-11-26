#!/usr/bin/env node
/**
 * knox-audit.mjs — auditoria de assets e deploy do Condado de Knox (sem dependências, Node 18.15+)
 *
 *   node tools/knox-audit.mjs [--root PASTA] [--webroot public] [--new "Personagens Novos e Animações"]
 *
 * Só LÊ. Grava _audit/audit-report.md e _audit/audit-report.json. Mostra:
 *  inventário e peso por pasta/extensão, duplicatas por hash, arquivos sem referência no código,
 *  arquivos que não deveriam ir no deploy, inspeção de GLB (rig, clips, texturas, compressão),
 *  compatibilidade animação × personagem (nomes de ossos), config Vercel/Git/LFS e mudanças recentes.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const argv = process.argv.slice(2);
const val = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const ROOT = path.resolve(val('root', process.cwd()));
const NEW_DIRS = val('new', 'ANIMAÇÕES NOVAS E PERSONAGENS|Personagens Novos e Animações').split('|').map((s) => s.normalize('NFC'));
const SKIP = new Set(['node_modules', '.git', '.vercel', '_audit', '.next', '.cache']);
const nfc = (s) => s.normalize('NFC');
const fmt = (n) => (n >= 1e9 ? (n / 1e9).toFixed(2) + ' GB' : n >= 1e6 ? (n / 1e6).toFixed(1) + ' MB' : n >= 1e3 ? (n / 1e3).toFixed(1) + ' KB' : n + ' B');
const ext = (p) => path.extname(p).toLowerCase();
const GB10 = 10 * 1024 ** 3;

function git(args) {
  try { return execFileSync('git', ['-c', 'core.quotepath=false', ...args], { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024 }).trim(); }
  catch { return null; }
}
function walk() {
  const out = [];
  (function rec(dir) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (SKIP.has(e.name) || e.isSymbolicLink()) continue;
      const abs = path.join(dir, e.name);
      if (e.isDirectory()) rec(abs);
      else if (e.isFile()) { const st = fs.statSync(abs); out.push({ rel: nfc(path.relative(ROOT, abs).split(path.sep).join('/')), abs, size: st.size, mtime: st.mtimeMs }); }
    }
  })(ROOT);
  return out;
}
function sha256File(p) {
  const h = crypto.createHash('sha256'); const fd = fs.openSync(p, 'r'); const buf = Buffer.allocUnsafe(1 << 20);
  try { let n; while ((n = fs.readSync(fd, buf, 0, buf.length, null)) > 0) h.update(buf.subarray(0, n)); } finally { fs.closeSync(fd); }
  return h.digest('hex');
}
const readAt = (fd, pos, len) => { const b = Buffer.alloc(len); const n = fs.readSync(fd, b, 0, len, pos); return b.subarray(0, n); };

// ───────── dimensões de imagem pelo cabeçalho
function imageInfo(buf, mime) {
  try {
    if (buf.length >= 24 && buf.readUInt32BE(0) === 0x89504e47) return { fmt: 'png', w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
    if (buf[0] === 0xff && buf[1] === 0xd8) {
      let i = 2;
      while (i + 9 < buf.length) {
        if (buf[i] !== 0xff) { i++; continue; }
        const m = buf[i + 1];
        if (m >= 0xc0 && m <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(m)) return { fmt: 'jpeg', h: buf.readUInt16BE(i + 5), w: buf.readUInt16BE(i + 7) };
        i += 2 + buf.readUInt16BE(i + 2);
      }
      return { fmt: 'jpeg' };
    }
    if (buf.toString('latin1', 0, 4) === 'RIFF' && buf.toString('latin1', 8, 12) === 'WEBP') {
      const k = buf.toString('latin1', 12, 16);
      if (k === 'VP8X') return { fmt: 'webp', w: buf.readUIntLE(24, 3) + 1, h: buf.readUIntLE(27, 3) + 1 };
      if (k === 'VP8L') { const b = buf.readUInt32LE(21); return { fmt: 'webp', w: (b & 0x3fff) + 1, h: ((b >> 14) & 0x3fff) + 1 }; }
      return { fmt: 'webp' };
    }
    if (buf[0] === 0xab && buf.toString('latin1', 1, 5) === 'KTX ') return { fmt: 'ktx2', w: buf.readUInt32LE(20), h: buf.readUInt32LE(24) };
  } catch { /* cai abaixo */ }
  return { fmt: (mime || '?').replace('image/', '') };
}

// ───────── GLB
function inspectGlb(f) {
  const fd = fs.openSync(f.abs, 'r');
  try {
    const head = readAt(fd, 0, 20);
    if (head.length < 20 || head.toString('latin1', 0, 4) !== 'glTF') return { error: 'não é GLB válido' };
    const jsonLen = head.readUInt32LE(12);
    if (jsonLen > 64 * 1024 * 1024) return { error: 'JSON do GLB grande demais' };
    const g = JSON.parse(readAt(fd, 20, jsonLen).toString('utf8'));
    const binStart = 20 + jsonLen + 8; // cabeçalho do chunk BIN = 8 bytes
    const nodes = g.nodes || [];
    const nm = (i) => (nodes[i] && nodes[i].name) || `node_${i}`;
    const joints = new Set(); (g.skins || []).forEach((s) => (s.joints || []).forEach((j) => joints.add(nm(j))));
    const clips = (g.animations || []).map((a, i) => {
      const targets = new Set(); let dur = 0;
      (a.channels || []).forEach((c) => { if (c.target && c.target.node !== undefined) targets.add(nm(c.target.node)); const s = a.samplers && a.samplers[c.sampler]; const acc = s && g.accessors && g.accessors[s.input]; if (acc && acc.max && acc.max[0] > dur) dur = acc.max[0]; });
      return { name: a.name || `clip_${i}`, duration: +dur.toFixed(2), channels: (a.channels || []).length, targets };
    });
    const images = (g.images || []).map((im) => {
      if (im.bufferView === undefined) return { fmt: im.uri ? 'uri externo/embutido' : '?', bytes: 0 };
      const bv = g.bufferViews[im.bufferView]; const info = imageInfo(readAt(fd, binStart + (bv.byteOffset || 0), Math.min(bv.byteLength, 128)), im.mimeType);
      return { ...info, bytes: bv.byteLength };
    });
    const ext = new Set([...(g.extensionsUsed || [])]);
    return {
      meshes: (g.meshes || []).length, prims: (g.meshes || []).reduce((a, m) => a + m.primitives.length, 0), nodes: nodes.length,
      skins: (g.skins || []).length, joints, clips, images, textureBytes: images.reduce((a, i) => a + i.bytes, 0), materials: (g.materials || []).length,
      meshCompression: ext.has('EXT_meshopt_compression') ? 'meshopt' : ext.has('KHR_draco_mesh_compression') ? 'draco' : (ext.has('KHR_mesh_quantization') ? 'quantize' : 'nenhuma'),
      texCompression: ext.has('KHR_texture_basisu') ? 'ktx2' : ext.has('EXT_texture_webp') ? 'webp' : 'png/jpg', generator: (g.asset && g.asset.generator) || ''
    };
  } catch (e) { return { error: String(e.message || e) }; } finally { fs.closeSync(fd); }
}
const normBone = (s) => s.replace(/^mixamorig[:_]?/i, '').replace(/^(armature|rig|skeleton)[|:_.]/i, '').replace(/[^a-z0-9]/gi, '').toLowerCase();

// ───────── execução
const files = walk();
const rel2 = (r) => r;
const isNew = (r) => NEW_DIRS.some((d) => r === d || r.startsWith(d + '/'));
const total = files.reduce((a, f) => a + f.size, 0);

// webroot
let vercel = null; try { vercel = JSON.parse(fs.readFileSync(path.join(ROOT, 'vercel.json'), 'utf8')); } catch { /* sem vercel.json */ }
const webroot0 = val('webroot', (vercel && vercel.outputDirectory) || ['public', 'dist', 'build', 'out'].find((d) => fs.existsSync(path.join(ROOT, d))) || '');
const webroot = ['.', './', '/'].includes(webroot0) ? '' : webroot0.replace(/^\.\//, '').replace(/\/$/, '');
const inWeb = (r) => webroot === '' || r === webroot || r.startsWith(webroot + '/');
const vercelignore = fs.existsSync(path.join(ROOT, '.vercelignore')) ? fs.readFileSync(path.join(ROOT, '.vercelignore'), 'utf8') : '';
const ignoredByVercel = (r) => vercelignore.split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#')).some((l) => { const p = l.replace(/^\/|\/$/g, ''); return r === p || r.startsWith(p + '/'); });
const deployFiles = files.filter((f) => inWeb(f.rel) && !ignoredByVercel(f.rel));
const deployBytes = deployFiles.reduce((a, f) => a + f.size, 0);
const newInDeploy = deployFiles.filter((f) => isNew(f.rel));

// peso por pasta / extensão
const byDir = new Map(), byDir2 = new Map(), byExt = new Map();
for (const f of files) {
  const parts = f.rel.split('/'); const d1 = parts.length > 1 ? parts[0] : '(raiz)'; const d2 = parts.length > 2 ? parts.slice(0, 2).join('/') : f.rel;
  for (const [m, k] of [[byDir, d1], [byDir2, d2], [byExt, ext(f.rel) || '(sem extensão)']]) { const v = m.get(k) || { s: 0, n: 0 }; v.s += f.size; v.n++; m.set(k, v); }
}
const rows = (m, n = 99) => [...m.entries()].sort((a, b) => b[1].s - a[1].s).slice(0, n);

// duplicatas
const bySize = new Map(); for (const f of files) if (f.size > 0) (bySize.get(f.size) || bySize.set(f.size, []).get(f.size)).push(f);
const dupGroups = [];
for (const arr of bySize.values()) { if (arr.length < 2) continue; const h = new Map(); for (const f of arr) { const k = sha256File(f.abs); (h.get(k) || h.set(k, []).get(k)).push(f); } for (const g of h.values()) if (g.length > 1) dupGroups.push(g); }
const dupWaste = dupGroups.reduce((a, g) => a + g[0].size * (g.length - 1), 0);

// referências no código
const CODE = new Set(['.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx', '.html', '.htm', '.css', '.json', '.vue', '.svelte', '.md']);
const ASSET = new Set(['.glb', '.gltf', '.bin', '.png', '.jpg', '.jpeg', '.webp', '.ktx2', '.hdr', '.exr', '.mp3', '.wav', '.ogg', '.m4a', '.mp4', '.webm', '.fbx', '.obj', '.svg', '.gif', '.woff', '.woff2', '.ttf']);
const codeFiles = files.filter((f) => CODE.has(ext(f.rel)) && f.size < 8e6 && !isNew(f.rel) && !/(^|\/)(package-lock\.json|audit-report)/.test(f.rel) && !/^ATUALIZACAO|^MELHORIAS/.test(f.rel));
const codeText = nfc(codeFiles.map((f) => { try { return fs.readFileSync(f.abs, 'utf8'); } catch { return ''; } }).join('\n')).toLowerCase();
const codeBytes = codeText.length;
const unused = [], weak = [];
for (const f of files) {
  if (!ASSET.has(ext(f.rel)) || isNew(f.rel)) continue;
  const rel = f.rel.toLowerCase(); const relWeb = webroot && rel.startsWith(webroot.toLowerCase() + '/') ? rel.slice(webroot.length + 1) : rel;
  const base = path.basename(rel); const stem = base.slice(0, base.length - ext(base).length); const dir = path.dirname(relWeb).split('/').pop();
  if (codeText.includes(rel) || codeText.includes(relWeb) || codeText.includes(base)) continue;
  if ((stem.length >= 4 && codeText.includes(stem)) || (dir && dir !== '.' && dir.length >= 3 && codeText.includes(dir + '/'))) { weak.push(f); continue; }
  unused.push(f);
}

// não deveriam ir no deploy
const BAD = /\.(zip|rar|7z|tar|gz|blend\d?|psd|kra|xcf|fbx|max|ma|mb|log|map|bak|tmp|orig)$|(^|\/)(\.DS_Store|Thumbs\.db|\.env.*)$/i;
const badDeploy = deployFiles.filter((f) => BAD.test(f.rel));

// GLB
const glbFiles = files.filter((f) => ['.glb'].includes(ext(f.rel)));
const glb = new Map(); for (const f of glbFiles) glb.set(f.rel, inspectGlb(f));
const glbAlerts = [];
for (const f of glbFiles) {
  const g = glb.get(f.rel); if (!g || g.error) { glbAlerts.push([f.rel, 'erro: ' + (g && g.error)]); continue; }
  const a = [];
  if (g.meshCompression === 'nenhuma' && f.size > 1e6) a.push('malha sem compressão (meshopt/draco)');
  if (g.images.some((i) => i.fmt === 'png' || i.fmt === 'jpeg') && g.textureBytes > 5e5) a.push('texturas PNG/JPG pesadas → WebP/KTX2');
  if (g.images.some((i) => (i.w || 0) > 2048 || (i.h || 0) > 2048)) a.push('textura > 2048 px');
  if (f.size > 0 && g.textureBytes / f.size > 0.6 && f.size > 1e6) a.push('texturas dominam o peso');
  if (g.skins && g.clips.length === 0 && g.joints.size && !/anim/i.test(f.rel)) a.push('tem rig mas nenhum clip (precisa de arquivos de animação)');
  if (a.length) glbAlerts.push([f.rel, a.join('; ')]);
}
// compatibilidade animação × personagem (arquivos das pastas novas)
const newGlb = glbFiles.filter((f) => isNew(f.rel) && glb.get(f.rel) && !glb.get(f.rel).error);
const chars = newGlb.filter((f) => glb.get(f.rel).joints.size > 0); const anims = newGlb.filter((f) => glb.get(f.rel).clips.length > 0);
const matrix = [];
for (const c of chars) for (const a of anims) {
  const J = glb.get(c.rel).joints; const nJ = new Set([...J].map(normBone));
  const T = new Set(); glb.get(a.rel).clips.forEach((cl) => cl.targets.forEach((t) => T.add(t)));
  const exact = [...T].filter((t) => J.has(t)).length; const loose = [...T].filter((t) => nJ.has(normBone(t))).length;
  matrix.push({ char: c.rel, anim: a.rel, targets: T.size, exact, loose });
}

// git / LFS / mudanças recentes
const hasGit = fs.existsSync(path.join(ROOT, '.git'));
const status = hasGit ? (git(['status', '--porcelain']) || '').split('\n').filter(Boolean) : [];
const log = hasGit ? (git(['log', '-n', '15', '--date=short', '--pretty=format:%h|%ad|%s', '--shortstat']) || '') : '';
const gitattr = fs.existsSync(path.join(ROOT, '.gitattributes')) ? fs.readFileSync(path.join(ROOT, '.gitattributes'), 'utf8') : '';
const lfsList = hasGit ? git(['lfs', 'ls-files']) : null;
const ptrs = files.filter((f) => f.size < 300 && (() => { try { return fs.readFileSync(f.abs, 'utf8').startsWith('version https://git-lfs.github.com/spec/v1'); } catch { return false; } })());
const gitSize = hasGit ? (() => { let s = 0; (function rec(d) { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); e.isDirectory() ? rec(p) : (s += fs.statSync(p).size); } })(path.join(ROOT, '.git')); return s; })() : 0;
const recent = [...files].sort((a, b) => b.mtime - a.mtime).slice(0, 25);

// ───────── relatório
const L = [];
const tbl = (h, r) => { L.push('| ' + h.join(' | ') + ' |', '| ' + h.map(() => '---').join(' | ') + ' |'); r.forEach((x) => L.push('| ' + x.join(' | ') + ' |')); L.push(''); };
L.push('# Auditoria de assets — Condado de Knox', '', `Gerado em ${new Date().toISOString()}  `, `Raiz: \`${ROOT}\`  `, `Webroot (o que vai no deploy): \`${webroot || '(a raiz inteira)'}\`  `, `Pastas novas: ${NEW_DIRS.map((d) => '`' + d + '`').join(', ')}`, '');

L.push('## 1. Resumo', '');
tbl(['Item', 'Valor'], [
  ['Arquivos / tamanho varrido', `${files.length} / ${fmt(total)}`],
  ['Vai em CADA deploy (webroot)', fmt(deployBytes)],
  ['Pastas novas DENTRO do deploy', newInDeploy.length ? `**SIM — ${fmt(newInDeploy.reduce((a, f) => a + f.size, 0))} entrariam em cada deploy**` : 'não'],
  ['Duplicatas exatas (desperdício)', `${dupGroups.length} grupos / ${fmt(dupWaste)}`],
  ['Sem nenhuma referência no código', `${unused.length} arquivos / ${fmt(unused.reduce((a, f) => a + f.size, 0))}`],
  ['Que não deveriam ir no deploy', `${badDeploy.length} / ${fmt(badDeploy.reduce((a, f) => a + f.size, 0))}`],
  ['Ponteiros LFS (sem conteúdo real aqui)', String(ptrs.length)],
  ['Tamanho da pasta .git', hasGit ? fmt(gitSize) : 'sem git'],
  ['Deployments que enchem 10 GB (Hobby)', deployBytes ? `~${Math.floor(GB10 / deployBytes)} deployments retidos com este webroot` : '—'],
]);
L.push('> O Deployment Storage soma **tamanho do webroot × deployments retidos**. Reduzir o webroot reduz TODOS os deploys futuros; apagar arquivo do repositório não apaga deploys antigos (para isso: retenção/remoção de deployments no painel).', '');

L.push('## 2. Peso por pasta', '');
tbl(['Pasta (1º nível)', 'Tamanho', 'Arquivos'], rows(byDir).map(([k, v]) => [k, fmt(v.s), v.n]));
tbl(['Pasta (2 níveis)', 'Tamanho', 'Arquivos'], rows(byDir2, 15).map(([k, v]) => [k, fmt(v.s), v.n]));
L.push('## 3. Peso por extensão', ''); tbl(['Extensão', 'Tamanho', 'Arquivos'], rows(byExt).map(([k, v]) => [k, fmt(v.s), v.n]));
L.push('## 4. Maiores arquivos (top 40)', ''); tbl(['Arquivo', 'Tamanho', 'Novo?', 'No deploy?'], [...files].sort((a, b) => b.size - a.size).slice(0, 40).map((f) => [f.rel, fmt(f.size), isNew(f.rel) ? 'sim' : '', inWeb(f.rel) && !ignoredByVercel(f.rel) ? 'sim' : '']));
L.push('## 5. Não deveriam ir para o deploy', ''); tbl(['Arquivo', 'Tamanho'], badDeploy.map((f) => [f.rel, fmt(f.size)]));
L.push('## 6. Duplicatas exatas', ''); tbl(['Tamanho', 'Desperdício', 'Cópias'], dupGroups.sort((a, b) => b[0].size * b.length - a[0].size * a.length).map((g) => [fmt(g[0].size), fmt(g[0].size * (g.length - 1)), g.map((f) => f.rel + (isNew(f.rel) ? ' (novo)' : '')).join(' ; ')]));
L.push('## 7. Candidatos a não usados', '', `Procurado em ${fmt(codeBytes)} de código/JSON. **Sem referência** = nem o caminho, nem o nome, nem o nome sem extensão, nem a pasta aparecem no código. Ainda assim, confirmar antes de apagar (nomes montados dinamicamente, listas vindas de outros arquivos).`, '');
tbl(['Arquivo', 'Tamanho'], unused.sort((a, b) => b.size - a.size).map((f) => [f.rel, fmt(f.size)]));
L.push(`Referência fraca (só o nome sem extensão ou a pasta aparecem — provavelmente carregado dinamicamente, **não apagar sem verificar**): ${weak.length} arquivos / ${fmt(weak.reduce((a, f) => a + f.size, 0))}`, '');
if (weak.length) tbl(['Arquivo', 'Tamanho'], weak.sort((a, b) => b.size - a.size).slice(0, 40).map((f) => [f.rel, fmt(f.size)]));

L.push('## 8. Modelos 3D (GLB)', '');
tbl(['Alerta', 'Arquivo(s)'], glbAlerts.map(([f, a]) => [a, f]));
tbl(['GLB', 'Tamanho', 'Malhas', 'Ossos', 'Clips', 'Texturas', 'Compressão malha/textura'], glbFiles.map((f) => { const g = glb.get(f.rel); return g.error ? [f.rel, fmt(f.size), '-', '-', '-', '-', g.error] : [f.rel + (isNew(f.rel) ? ' (novo)' : ''), fmt(f.size), g.meshes, g.joints.size, g.clips.length, `${g.images.length} (${fmt(g.textureBytes)})`, `${g.meshCompression} / ${g.texCompression}`]; }));
L.push('### Clips por arquivo (novos)', '');
tbl(['GLB', 'Clip', 'Duração (s)', 'Canais'], newGlb.flatMap((f) => glb.get(f.rel).clips.map((c) => [f.rel, c.name, c.duration, c.channels])).slice(0, 120));
L.push('### Compatibilidade animação × personagem (nomes de ossos)', '', '`exato` = nome idêntico; `parecido` = igual ignorando prefixo `mixamorig:`/`Armature|` e maiúsculas. Se `parecido` for 100% e `exato` baixo, basta normalizar os nomes. Se for baixo, é preciso retarget.', '');
tbl(['Personagem', 'Animação em', 'Alvos', 'Exato', 'Parecido'], matrix.map((m) => [m.char, m.anim, m.targets, `${m.exact}/${m.targets}`, `${m.loose}/${m.targets}`]).slice(0, 80));

L.push('## 9. Vercel / Git / LFS', '');
L.push('`vercel.json`: ' + (vercel ? '```json\n' + JSON.stringify(vercel, null, 1) + '\n```' : 'não existe'), '', '`.vercelignore`: ' + (vercelignore ? 'existe' : '**não existe**'), '', '`.gitattributes` (LFS): ' + (/filter=lfs/.test(gitattr) ? '```\n' + gitattr.trim() + '\n```' : 'sem regra LFS'), '', `Arquivos rastreados pelo LFS: ${lfsList == null ? 'n/d' : lfsList.split('\n').filter(Boolean).length}`, '');
L.push('## 10. Mudanças recentes', '', `Arquivos modificados/não rastreados no git: ${status.length}`, ''); if (status.length) L.push(...status.slice(0, 40).map((l) => '- `' + l.slice(3).replace(/^"|"$/g, '') + '` (' + l.slice(0, 2).trim() + ')'), '');
L.push('Últimos commits:', '', '```', log || '(sem git)', '```', '', 'Arquivos mais recentes (por data de modificação):', '', ...recent.map((f) => `- ${new Date(f.mtime).toISOString().slice(0, 16).replace('T', ' ')} — ${f.rel} (${fmt(f.size)})`), '');

fs.mkdirSync(path.join(ROOT, '_audit'), { recursive: true });
fs.writeFileSync(path.join(ROOT, '_audit', 'audit-report.md'), L.join('\n'));
fs.writeFileSync(path.join(ROOT, '_audit', 'audit-report.json'), JSON.stringify({
  generatedAt: new Date().toISOString(), webroot, totals: { files: files.length, bytes: total, deployBytes, dupWaste }, newInDeploy: newInDeploy.map((f) => f.rel),
  duplicates: dupGroups.map((g) => g.map((f) => f.rel)), unused: unused.map((f) => f.rel), weakRef: weak.map((f) => f.rel), badDeploy: badDeploy.map((f) => f.rel), glbAlerts, matrix,
  lfsPointers: ptrs.map((f) => f.rel)
}, null, 1));
console.log(`OK — ${files.length} arquivos, ${fmt(total)} varridos.`);
console.log(`Webroot (vai em CADA deploy): ${fmt(deployBytes)} | pastas novas dentro do deploy: ${newInDeploy.length ? 'SIM ⚠ ' + fmt(newInDeploy.reduce((a, f) => a + f.size, 0)) : 'não'} | duplicatas: ${fmt(dupWaste)} | sem referência: ${unused.length}`);
console.log('Relatórios: _audit/audit-report.md e _audit/audit-report.json');
void rel2;
