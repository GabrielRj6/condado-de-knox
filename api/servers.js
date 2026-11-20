// Diretório de Servidores Ativos e em Espera (Suporta Migração de Host, Mundos Procedurais, OSM e Google Maps!)
const activeRooms = globalThis.__KNOX_ACTIVE_ROOMS__ || (globalThis.__KNOX_ACTIVE_ROOMS__ = new Map());

const ACTIVE_WINDOW_MS = 38000;          // Sem heartbeat há >38s entra em modo EM ESPERA (standby)
const STANDBY_TTL_MS = 20 * 60 * 1000;   // Mantém a sala listada por 20 minutos para reconexão/retomada caso o criador caia

function pruneExpired() {
  const now = Date.now();
  for (const [id, room] of activeRooms.entries()) {
    if (now - room.updatedAt > STANDBY_TTL_MS) {
      activeRooms.delete(id);
    }
  }
}

function toPublicRoom(room, now) {
  const standby = (now - room.updatedAt) > ACTIVE_WINDOW_MS;
  return {
    peerId: room.peerId,
    name: room.name,
    hostName: room.hostName,
    ownerId: room.ownerId || '',
    ownerName: room.ownerName || room.hostName,
    players: standby ? 0 : room.players,
    maxPlayers: room.maxPlayers,
    seed: room.seed,
    worldMode: room.worldMode,
    placeName: room.placeName,
    areaKm2: room.areaKm2,
    worldId: room.worldId,
    worldHash: room.worldHash,
    standby,
    updatedAt: room.updatedAt
  };
}

module.exports = function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  pruneExpired();
  const now = Date.now();

  if (req.method === 'GET') {
    const list = Array.from(activeRooms.values())
      .sort((a, b) => b.updatedAt - a.updatedAt)
      .map((r) => toPublicRoom(r, now));
    return res.status(200).json({ servers: list });
  }

  if (req.method === 'POST') {
    const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
    if (body.action === 'remove' && body.peerId) {
      const pid = String(body.peerId);
      const existing = activeRooms.get(pid);
      if (existing && existing.ownerKey && existing.ownerKey !== String(body.ownerKey || '')) {
        return res.status(403).json({ error: 'Apenas o criador pode fechar este servidor' });
      }
      activeRooms.delete(pid);
      return res.status(200).json({ ok: true });
    }

    if (!body.peerId || !body.name) {
      return res.status(400).json({ error: 'peerId e name são obrigatórios' });
    }

    const peerId = String(body.peerId).slice(0, 64);
    const prev = activeRooms.get(peerId);
    const ownerId = String(body.ownerId || (prev && prev.ownerId) || '').slice(0, 48);
    const ownerKey = String(body.ownerKey || (prev && prev.ownerKey) || '').slice(0, 64);
    const ownerName = String(body.ownerName || (prev && prev.ownerName) || body.hostName || 'Sobrevivente').slice(0, 24);

    activeRooms.set(peerId, {
      peerId,
      name: String(body.name).slice(0, 42),
      hostName: String(body.hostName || 'Sobrevivente').slice(0, 24),
      ownerId,
      ownerKey,
      ownerName,
      players: Math.max(1, Number(body.players) || 1),
      maxPlayers: Math.min(24, Math.max(2, Number(body.maxPlayers) || 12)),
      seed: Number(body.seed) || 1000,
      worldMode: String(body.worldMode || 'procedural').slice(0, 20),
      placeName: String(body.placeName || '').slice(0, 64),
      areaKm2: Number(body.areaKm2) || 0,
      worldId: String(body.worldId || '').slice(0, 80),
      worldHash: String(body.worldHash || '').slice(0, 40),
      updatedAt: now
    });

    return res.status(200).json({ ok: true, count: activeRooms.size });
  }

  return res.status(405).json({ error: 'Method not allowed' });
};
