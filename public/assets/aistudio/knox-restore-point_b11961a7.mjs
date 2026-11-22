#!/usr/bin/env node
/**
 * knox-restore-point.mjs — ponto de restauração do Condado de Knox (sem dependências, Node 18.15+)
 *
 *   node tools/knox-restore-point.mjs create [--label nome] [--dest PASTA] [--exclude nome]... [--no-git] [--no-hash] [--allow-pointers]
 *   node tools/knox-restore-point.mjs verify PASTA_DO_PONTO
 *   node tools/knox-restore-point.mjs diff   PASTA_DO_PONTO [--out arquivo.md]
 *
 * Rode DENTRO da pasta do jogo. O ponto é uma cópia COMPLETA (com .git) FORA do projeto, com manifesto SHA-256,
 * mais uma tag e um branch git no commit atual. Nada é apagado nem alterado no projeto (só cria tag/branch).
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const argv = process.argv.slice(2);
const cmd = argv[0];
const flag = (n) => argv.includes('--' + n);
const val = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : d; };
const vals = (n) => argv.flatMap((a, i) => (a === '--' + n && argv[i + 1] ? [argv[i + 1]] : []));
const ROOT = process.cwd();
const MANIFEST = 'RESTORE_MANIFEST.json';
const README = 'RESTORE_README.txt';
const DEFAULT_EXCLUDES = ['node_modules', '.vercel', '_audit', '.next', 'Personagens Novos e Animações'];
const nfc = (s) => s.normalize('NFC');
const fmt = (n) => (n >= 1e9 ? (n / 1e9).toFixed(2) + ' GB' : n >= 1e6 ? (n / 1e6).toFixed(1) + ' MB' : n >= 1e3 ? (n / 1e3).toFixed(1) + ' KB' : n + ' B');
const die = (msg, code = 1) => { console.error('\n✖ ' + msg); process.exit(code); };

function git(args, cwd = ROOT) {
  try { return execFileSync('git', ['-c', 'core.quotepath=false', ...args], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024 }).trim(); }
  catch { return null; }
}

function sha256File(p) {
  const h = crypto.createHash('sha256'); const fd = fs.openSync(p, 'r'); const buf = Buffer.allocUnsafe(1 << 20);
  try { let n; while ((n = fs.readSync(fd, buf, 0, buf.length, null)) > 0) h.update(buf.subarray(0, n)); } finally { fs.closeSync(fd); }
  return h.digest('hex');
}

/** Lista arquivos (caminhos relativos com "/"), ignorando pastas excluídas pelo NOME no 1º nível ou em qualquer nível. */
function walk(root, excludes, { skipGit = false } = {}) {
  const ex = new Set(excludes.map(nfc)); const out = [];
  (function rec(dir) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const abs = path.join(dir, e.name); const rel = nfc(path.relative(root, abs).split(path.sep).join('/'));
      if (ex.has(nfc(e.name)) || ex.has(rel)) continue;
      if (skipGit && e.name === '.git') continue;
      if (e.isSymbolicLink()) continue;
      if (e.isDirectory()) rec(abs);
      else if (e.isFile()) out.push({ rel, abs, size: fs.statSync(abs).size });
    }
  })(root);
  return out;
}

function isLfsPointer(f) {
  if (f.size > 300) return false;
  try { return fs.readFileSync(f.abs, 'utf8').startsWith('version https://git-lfs.github.com/spec/v1'); } catch { return false; }
}

const stamp = () => new Date().toISOString().replace(/[-:]/g, '').replace(/\..*/, '').replace('T', '-');
const slug = (s) => String(s).toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'ponto';

// ───────────────────────── create
function create() {
  const label = slug(val('label', 'antes-da-troca'));
  const ts = stamp();
  const excludes = [...new Set([...DEFAULT_EXCLUDES, ...vals('exclude')])];
  const noGit = flag('no-git'); const noHash = flag('no-hash');
  const dest = path.resolve(val('dest', path.join(path.dirname(ROOT), `${path.basename(ROOT)}__RESTORE_${label}_${ts}`)));
  const inside = path.relative(ROOT, dest);
  if (inside === '' || (!inside.startsWith('..') && !path.isAbsolute(inside))) die(`O destino não pode ficar DENTRO da pasta do jogo (iria para o deploy/git): ${dest}`);
  if (fs.existsSync(dest) && fs.readdirSync(dest).length) die(`O destino já existe e não está vazio: ${dest}`);

  console.log(`Pasta do jogo : ${ROOT}\nDestino       : ${dest}\nExcluídos     : ${excludes.join(', ')}\n`);
  let files = walk(ROOT, excludes, { skipGit: noGit });
  const total = files.reduce((a, f) => a + f.size, 0);
  console.log(`${files.length} arquivos, ${fmt(total)} para copiar.`);

  const ptrs = files.filter(isLfsPointer);
  if (ptrs.length) {
    console.log(`\n⚠ ${ptrs.length} arquivo(s) são apenas PONTEIROS LFS (o conteúdo real não está nesta máquina):`);
    ptrs.slice(0, 10).forEach((f) => console.log('   - ' + f.rel));
    if (!flag('allow-pointers')) die('Ponto de restauração abortado: ele NÃO guardaria os assets reais. Rode "git lfs pull" (se houver cota) ou use --allow-pointers sabendo disso.', 2);
  }

  fs.mkdirSync(dest, { recursive: true });
  try {
    const st = fs.statfsSync(dest); const free = st.bavail * st.bsize;
    console.log(`Espaço livre no destino: ${fmt(free)} (necessário ~${fmt(total * 1.05 + 5e7)})`);
    if (free < total * 1.05 + 5e7) die('Espaço insuficiente no destino.');
  } catch { /* statfs indisponível: segue */ }

  // git: tag + branch no commit atual (não mexe nos arquivos)
  let gitInfo = null;
  if (!noGit && fs.existsSync(path.join(ROOT, '.git'))) {
    const head = git(['rev-parse', 'HEAD']);
    if (head) {
      const dirty = (git(['status', '--porcelain']) || '').split('\n').filter(Boolean).length;
      const tag = `restore/${label}-${ts}`; const branch = `backup/${label}-${ts}`;
      if (git(['tag', tag, head]) !== null && git(['branch', branch, head]) !== null) {
        gitInfo = { commit: head, tag, branch, dirtyFiles: dirty };
        console.log(`Git: tag ${tag} e branch ${branch} criados no commit ${head.slice(0, 8)}.`);
        if (dirty) console.log(`ℹ ${dirty} arquivo(s) modificados/não rastreados: ficam na CÓPIA DA PASTA, mas não dentro da tag/branch (que apontam para o último commit).`);
      } else console.log('⚠ Não consegui criar tag/branch (repositório sem commits?). A cópia da pasta continua válida.');
    }
  }

  files = walk(ROOT, excludes, { skipGit: noGit }); // re-varre: inclui as referências git recém-criadas
  console.log('\nCopiando…');
  const entries = []; let done = 0, bytes = 0;
  for (const f of files) {
    const to = path.join(dest, ...f.rel.split('/')); fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(f.abs, to);
    entries.push({ path: f.rel, size: f.size, sha256: noHash ? null : sha256File(to) });
    done++; bytes += f.size;
    if (done % 25 === 0 || done === files.length) process.stdout.write(`\r  ${done}/${files.length} arquivos, ${fmt(bytes)}   `);
  }
  console.log('');
  const manifest = { tool: 'knox-restore-point', version: 1, label, createdAt: new Date().toISOString(), sourceRoot: ROOT, excludes, hashed: !noHash, git: gitInfo, files: entries };
  fs.writeFileSync(path.join(dest, MANIFEST), JSON.stringify(manifest, null, 1));
  fs.writeFileSync(path.join(dest, README), [
    `PONTO DE RESTAURAÇÃO "${label}" — criado em ${manifest.createdAt}`,
    `Origem: ${ROOT}`, `Arquivos: ${entries.length} (${fmt(bytes)})`, gitInfo ? `Git: tag ${gitInfo.tag} | branch ${gitInfo.branch} | commit ${gitInfo.commit}` : 'Git: não registrado',
    '', 'COMO VOLTAR:',
    ' 1) Código versionado:  git switch -c voltar ' + (gitInfo ? gitInfo.tag : '<tag>'),
    ' 2) Pasta inteira:      copie o conteúdo desta pasta (menos RESTORE_*) de volta por cima do projeto,',
    '                       ou apague o projeto e use esta cópia como o projeto.',
    ' 3) Conferir integridade: node tools/knox-restore-point.mjs verify "' + dest + '"', ''].join('\n'));

  // verificação imediata
  const bad = verifyDir(dest, manifest);
  if (bad.problems) die('A cópia recém-criada NÃO bateu com o manifesto. Não use este ponto.', 3);
  console.log(`\n✔ Ponto de restauração criado e verificado (${noHash ? 'tamanho' : 'SHA-256'}).\n  Cópia : ${dest}` + (gitInfo ? `\n  Tag   : ${gitInfo.tag}\n  Branch: ${gitInfo.branch}\n  (opcional) enviar só as referências ao GitHub:  git push origin ${gitInfo.tag} ${gitInfo.branch}` : '') +
    `\n  Conferir depois:  node tools/knox-restore-point.mjs verify "${dest}"`);
}

// ───────────────────────── verify
function readManifest(dir) {
  const p = path.join(dir, MANIFEST);
  if (!fs.existsSync(p)) die(`Não achei ${MANIFEST} em ${dir}. Essa pasta é um ponto de restauração?`);
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}
function verifyDir(dir, manifest) {
  const missing = [], changed = [], known = new Set();
  for (const e of manifest.files) {
    known.add(e.path); const p = path.join(dir, ...e.path.split('/'));
    if (!fs.existsSync(p)) { missing.push(e.path); continue; }
    const size = fs.statSync(p).size;
    if (size !== e.size) { changed.push(`${e.path} (tamanho ${size} ≠ ${e.size})`); continue; }
    if (manifest.hashed && e.sha256 && sha256File(p) !== e.sha256) changed.push(`${e.path} (conteúdo diferente)`);
  }
  const extras = walk(dir, [], {}).map((f) => f.rel).filter((r) => !known.has(r) && r !== MANIFEST && r !== README);
  return { missing, changed, extras, problems: missing.length + changed.length + extras.length };
}
function verify() {
  const dir = path.resolve(argv[1] || ''); if (!argv[1]) die('Uso: verify PASTA_DO_PONTO');
  const m = readManifest(dir); const r = verifyDir(dir, m);
  console.log(`\nPonto: ${m.label} — criado em ${m.createdAt} — ${m.files.length} arquivos (${m.hashed ? 'SHA-256' : 'só tamanho'})`);
  console.log(`Faltando: ${r.missing.length} | Corrompidos/alterados: ${r.changed.length} | Extras: ${r.extras.length}`);
  r.missing.slice(0, 20).forEach((x) => console.log('  faltando: ' + x));
  r.changed.slice(0, 20).forEach((x) => console.log('  alterado: ' + x));
  r.extras.slice(0, 20).forEach((x) => console.log('  extra: ' + x));
  console.log(r.problems ? '\n✖ Cópia NÃO está íntegra.' : '\n✔ Cópia íntegra.');
  process.exit(r.problems ? 1 : 0);
}

// ───────────────────────── diff (projeto atual × ponto)
function diff() {
  const dir = path.resolve(argv[1] || ''); if (!argv[1]) die('Uso: diff PASTA_DO_PONTO [--out arquivo.md]');
  const m = readManifest(dir);
  const now = walk(ROOT, m.excludes, { skipGit: true }); // .git interno fica de fora: são só objetos/refs
  const old = new Map(m.files.filter((e) => !e.path.startsWith('.git/')).map((e) => [e.path, e]));
  const added = [], removed = [], modified = []; let same = 0;
  for (const f of now) {
    const o = old.get(f.rel);
    if (!o) { added.push({ p: f.rel, s: f.size }); continue; }
    old.delete(f.rel);
    if (o.size !== f.size || (m.hashed && o.sha256 && sha256File(f.abs) !== o.sha256)) modified.push({ p: f.rel, a: o.size, b: f.size }); else same++;
  }
  for (const o of old.values()) removed.push(o.path);
  const top = (arr, key) => { const t = {}; for (const x of arr) { const k = (typeof x === 'string' ? x : x.p).split('/')[0]; t[k] = t[k] || { n: 0, s: 0 }; t[k].n++; t[k].s += x[key] || 0; } return t; };
  const lines = [`# Mudanças desde o ponto de restauração "${m.label}" (${m.createdAt})`, '',
    `Comparação ${m.hashed ? 'completa (SHA-256)' : 'por tamanho'}`, '',
    `- Iguais: ${same}`, `- Adicionados: ${added.length} (${fmt(added.reduce((a, x) => a + x.s, 0))})`, `- Removidos: ${removed.length}`, `- Modificados: ${modified.length}`, '',
    '## Modificados', '', ...(modified.length ? modified.map((x) => `- ${x.p} (${fmt(x.a)} → ${fmt(x.b)})`) : ['_(nenhum)_']), '',
    '## Removidos', '', ...(removed.length ? removed.map((x) => `- ${x}`) : ['_(nenhum)_']), '',
    '## Adicionados', '', ...(added.length ? added.sort((a, b) => b.s - a.s).map((x) => `- ${x.p} (${fmt(x.s)})`) : ['_(nenhum)_'])];
  void top;
  const out = val('out', null);
  if (out) { fs.writeFileSync(out, lines.join('\n')); console.log('Relatório gravado em ' + out); }
  console.log(lines.slice(0, 60).join('\n'));
}

if (cmd === 'create') create();
else if (cmd === 'verify') verify();
else if (cmd === 'diff') diff();
else console.log('Uso:\n  create [--label nome] [--dest PASTA] [--exclude nome]... [--no-git] [--no-hash] [--allow-pointers]\n  verify PASTA\n  diff PASTA [--out arquivo.md]');
