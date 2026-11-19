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

const server = http.createServer((req, res) => {
  let pathname;
  try {
    const urlObj = new URL(req.url, `http://localhost:${PORT}`);
    pathname = decodeURIComponent(urlObj.pathname);
  } catch {
    res.writeHead(400);
    res.end('Bad Request');
    return;
  }

  if (pathname === '/api/maps-config') {
    const apiKey = readDotEnvKey();
    res.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store'
    });
    res.end(JSON.stringify({ configured: Boolean(apiKey), apiKey }));
    return;
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
