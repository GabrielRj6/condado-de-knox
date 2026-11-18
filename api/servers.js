// Diretório leve de Servidores Ativos para Vercel Serverless (Região gru1)
// Funciona em conjunto com a descoberta automática WebRTC/PeerJS dos slots públicos!
const activeRooms = globalThis.__KNOX_ACTIVE_ROOMS__ || (globalThis.__KNOX_ACTIVE_ROOMS__ = new Map());

function pruneExpired() {
  const now = Date.now();
  for (const [id, room] of activeRooms.entries()) {
    if (now - room.updatedAt > 32000) {
      activeRooms.delete(id);
    }
  }
}

module.exports = function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  pruneExpired();

  if (req.method === 'GET') {
    const list = Array.from(activeRooms.values()).sort((a, b) => b.updatedAt - a.updatedAt);
    return res.status(200).json({ servers: list });
  }

  if (req.method === 'POST') {
    const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
    if (body.action === 'remove' && body.peerId) {
      activeRooms.delete(String(body.peerId));
      return res.status(200).json({ ok: true });
    }

    if (!body.peerId || !body.name) {
      return res.status(400).json({ error: 'peerId e name são obrigatórios' });
    }

    const peerId = String(body.peerId).slice(0, 64);
    activeRooms.set(peerId, {
      peerId,
      name: String(body.name).slice(0, 42),
      hostName: String(body.hostName || 'Sobrevivente').slice(0, 24),
      players: Math.max(1, Number(body.players) || 1),
      maxPlayers: Math.min(24, Math.max(2, Number(body.maxPlayers) || 12)),
      seed: Number(body.seed) || 1000,
      updatedAt: Date.now()
    });

    return res.status(200).json({ ok: true, count: activeRooms.size });
  }

  return res.status(405).json({ error: 'Method not allowed' });
};
