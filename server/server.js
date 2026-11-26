'use strict';

/**
 * LiveRoom WebSocket 服务端 —— 零依赖，Node 18+ 直接运行。
 *
 *   node server.js              # 默认 3000 端口
 *   PORT=8080 node server.js    # 换端口
 *
 * 同时提供：
 *   GET  /             Web 客户端（发给朋友的就是这个链接）
 *   GET  /api/rooms    房间列表（含在线人数）
 *   GET  /api/info     服务端信息
 *   WS   /ws           长连接端点
 *
 * 协议全部是 JSON 文本帧，见 README.md。
 */

const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const PORT = Number(process.env.PORT || 3000);
const BIND = process.env.HOST || '0.0.0.0';
const PUBLIC_DIR = path.join(__dirname, 'public');
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const COLORS = ['#4F7DF3', '#E8794B', '#2E9E7B', '#9B6BDB', '#D9538A', '#2C8FB8', '#C08A2E', '#5C6BC0'];
const MAX_HISTORY = 120;
const MAX_STROKES = 600;
const MAX_POINTS = 2000;

let seq = 0;
const clients = new Set();
const rooms = new Map();

function makeRoom(def, temporary) {
  return {
    id: def.id,
    name: def.name,
    type: def.type,
    desc: def.desc || '',
    temporary: temporary,
    clients: new Set(),
    history: [],
    strokes: [],
    strokeIndex: new Map()
  };
}

[
  { id: 'chat-lobby', name: '大厅闲聊', type: 'chat', desc: '随便聊聊，所有人都能进' },
  { id: 'chat-dev', name: '技术茶馆', type: 'chat', desc: 'HarmonyOS / 网络 / 踩坑记录' },
  { id: 'board-canvas', name: '一起画', type: 'board', desc: '多人实时协作白板' },
  { id: 'board-brain', name: '头脑风暴', type: 'board', desc: '画点什么，边聊边改' }
].forEach((d) => rooms.set(d.id, makeRoom(d, false)));

function roomSummaries() {
  return Array.from(rooms.values()).map((r) => ({
    id: r.id, name: r.name, type: r.type, desc: r.desc, members: r.clients.size
  }));
}

function memberOf(c) {
  return { id: c.id, name: c.name, color: c.color };
}

function membersOf(room) {
  return Array.from(room.clients).map(memberOf);
}

/* ------------------------------------------------------------------ *
 * WebSocket 帧编解码（RFC 6455，只处理文本帧，足够本项目用）
 * ------------------------------------------------------------------ */

function sendFrame(socket, opcode, payload) {
  if (!socket || socket.destroyed) return;
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[1] = len;
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  header[0] = 0x80 | opcode; // FIN + opcode，服务端发送不掩码
  try {
    socket.write(Buffer.concat([header, payload]));
  } catch (e) {
    // 对端已断开，忽略
  }
}

function sendJson(c, obj) {
  sendFrame(c.socket, 0x1, Buffer.from(JSON.stringify(obj), 'utf8'));
}

function broadcast(room, obj, exclude) {
  const payload = Buffer.from(JSON.stringify(obj), 'utf8');
  for (const c of room.clients) {
    if (c !== exclude) sendFrame(c.socket, 0x1, payload);
  }
}

function pushRoomList() {
  const payload = Buffer.from(JSON.stringify({ type: 'rooms', rooms: roomSummaries() }), 'utf8');
  for (const c of clients) sendFrame(c.socket, 0x1, payload);
}

function parseFrames(c, chunk) {
  c.buf = c.buf.length === 0 ? chunk : Buffer.concat([c.buf, chunk]);
  while (true) {
    const b = c.buf;
    if (b.length < 2) return;
    const fin = (b[0] & 0x80) !== 0;
    const opcode = b[0] & 0x0f;
    const masked = (b[1] & 0x80) !== 0;
    let len = b[1] & 0x7f;
    let offset = 2;

    if (len === 126) {
      if (b.length < offset + 2) return;
      len = b.readUInt16BE(offset);
      offset += 2;
    } else if (len === 127) {
      if (b.length < offset + 8) return;
      const big = b.readBigUInt64BE(offset);
      if (big > 4n * 1024n * 1024n) { c.socket.destroy(); return; }
      len = Number(big);
      offset += 8;
    }
    if (masked && b.length < offset + 4) return;
    const maskLen = masked ? 4 : 0;
    if (b.length < offset + maskLen + len) return;

    let payload = b.subarray(offset + maskLen, offset + maskLen + len);
    if (masked) {
      const key = b.subarray(offset, offset + 4);
      const copy = Buffer.from(payload);
      for (let i = 0; i < copy.length; i++) copy[i] ^= key[i % 4];
      payload = copy;
    }
    c.buf = b.subarray(offset + maskLen + len);
    handleFrame(c, fin, opcode, payload);
  }
}

function handleFrame(c, fin, opcode, payload) {
  if (opcode === 0x8) {           // close
    sendFrame(c.socket, 0x8, Buffer.alloc(0));
    c.socket.end();
    return;
  }
  if (opcode === 0x9) {           // ping -> pong
    sendFrame(c.socket, 0xA, payload);
    return;
  }
  if (opcode === 0xA) return;    // pong

  if (opcode === 0x0) {          // 分片续帧
    c.fragBuf.push(payload);
    if (fin) {
      const full = Buffer.concat(c.fragBuf);
      const op = c.fragOpcode;
      c.fragBuf = [];
      c.fragOpcode = 0;
      if (op === 0x1) handleText(c, full.toString('utf8'));
    }
    return;
  }
  if (opcode === 0x1 || opcode === 0x2) {
    if (!fin) {
      c.fragOpcode = opcode;
      c.fragBuf = [payload];
      return;
    }
    if (opcode === 0x1) handleText(c, payload.toString('utf8'));
  }
}

/* ------------------------------------------------------------------ *
 * 业务逻辑
 * ------------------------------------------------------------------ */

function clampPoint(p) {
  const x = Number(p && p.x);
  const y = Number(p && p.y);
  return {
    x: Math.max(0, Math.min(1, Number.isFinite(x) ? x : 0)),
    y: Math.max(0, Math.min(1, Number.isFinite(y) ? y : 0))
  };
}

function addSystem(room, text) {
  const item = {
    kind: 'system', id: 's' + (++seq), fromId: '', fromName: '', color: '',
    text: text, ts: Date.now()
  };
  if (room.type === 'chat') {
    room.history.push(item);
    if (room.history.length > MAX_HISTORY) room.history.shift();
  }
  broadcast(room, { type: 'system', text: text, ts: item.ts });
}

function leaveRoom(c, notify) {
  const room = rooms.get(c.roomId);
  c.roomId = null;
  if (!room) return;
  room.clients.delete(c);
  if (notify) {
    addSystem(room, `${c.name} 离开了房间`);
    broadcast(room, { type: 'members', members: membersOf(room) });
  }
  if (room.temporary && room.clients.size === 0) rooms.delete(room.id);
  pushRoomList();
}

function handleCreateRoom(c, msg) {
  const roomId = String(msg.roomId || '').trim().slice(0, 40);
  if (!roomId) return;
  if (rooms.has(roomId)) return;
  const type = msg.roomType === 'board' ? 'board' : 'chat';
  const name = String(msg.name || roomId).trim().slice(0, 20);
  rooms.set(roomId, makeRoom({ id: roomId, name: name, type: type, desc: '大家刚建的房间' }, false));
  pushRoomList();
}

function handleJoin(c, msg) {
  const roomId = String(msg.roomId || '').trim().slice(0, 40);
  if (!roomId) { sendJson(c, { type: 'error', message: '房间号不能为空' }); return; }
  const name = String(msg.name || '').trim().slice(0, 16) || '匿名';
  c.name = name;

  if (c.roomId) leaveRoom(c, true);

  let room = rooms.get(roomId);
  if (!room) {
    const type = /^board/i.test(roomId) ? 'board' : 'chat';
    room = makeRoom({ id: roomId, name: roomId, type: type, desc: '临时房间' }, true);
    rooms.set(roomId, room);
  }
  c.roomId = room.id;
  room.clients.add(c);

  sendJson(c, {
    type: 'joined',
    clientId: c.id,
    room: { id: room.id, name: room.name, type: room.type, desc: room.desc },
    members: membersOf(room),
    history: room.type === 'chat' ? room.history : [],
    strokes: room.type === 'board' ? room.strokes : []
  });
  addSystem(room, `${name} 加入了房间`);
  broadcast(room, { type: 'members', members: membersOf(room) });
  pushRoomList();
}

function handleChat(c, msg) {
  const room = rooms.get(c.roomId);
  if (!room || room.type !== 'chat') return;
  const text = String(msg.text || '').trim().slice(0, 1000);
  if (!text) return;
  const item = {
    kind: 'chat', id: 'm' + (++seq), fromId: c.id, fromName: c.name,
    color: c.color, text: text, ts: Date.now()
  };
  room.history.push(item);
  if (room.history.length > MAX_HISTORY) room.history.shift();
  broadcast(room, Object.assign({ type: 'chat' }, item));
}

function handleStrokeStart(c, msg) {
  const room = rooms.get(c.roomId);
  if (!room || room.type !== 'board') return;
  const id = String(msg.id || '').slice(0, 48);
  if (!id || room.strokeIndex.has(id)) return;
  const stroke = {
    id: id,
    color: String(msg.color || '#1F2329').slice(0, 24),
    width: Math.max(1, Math.min(24, Number(msg.width) || 3)),
    owner: c.id,
    points: [clampPoint(msg.point)]
  };
  room.strokes.push(stroke);
  room.strokeIndex.set(id, stroke);
  if (room.strokes.length > MAX_STROKES) {
    const removed = room.strokes.shift();
    room.strokeIndex.delete(removed.id);
  }
  broadcast(room, {
    type: 'stroke_start', id: id, color: stroke.color, width: stroke.width,
    point: stroke.points[0], from: memberOf(c)
  }, c);
}

function handleStrokeMove(c, msg) {
  const room = rooms.get(c.roomId);
  if (!room || room.type !== 'board') return;
  const stroke = room.strokeIndex.get(String(msg.id || ''));
  if (!stroke) return;
  const p = clampPoint(msg.point);
  stroke.points.push(p);
  if (stroke.points.length > MAX_POINTS) stroke.points.shift();
  broadcast(room, { type: 'stroke_move', id: stroke.id, point: p }, c);
}

function handleStrokeEnd(c, msg) {
  const room = rooms.get(c.roomId);
  if (!room || room.type !== 'board') return;
  const id = String(msg.id || '');
  room.strokeIndex.delete(id);
  broadcast(room, { type: 'stroke_end', id: id }, c);
}

function handleBoardClear(c) {
  const room = rooms.get(c.roomId);
  if (!room || room.type !== 'board') return;
  room.strokes = [];
  room.strokeIndex.clear();
  broadcast(room, { type: 'board_clear' });
}

function handleText(c, text) {
  let msg;
  try {
    msg = JSON.parse(text);
  } catch (e) {
    return;
  }
  if (!msg || typeof msg.type !== 'string') return;
  switch (msg.type) {
    case 'ping':
      sendJson(c, { type: 'pong', ts: Date.now() });
      break;
    case 'join':
      handleJoin(c, msg);
      break;
    case 'create_room':
      handleCreateRoom(c, msg);
      break;
    case 'leave':
      leaveRoom(c, true);
      break;
    case 'list_rooms':
      sendJson(c, { type: 'rooms', rooms: roomSummaries() });
      break;
    case 'chat':
      handleChat(c, msg);
      break;
    case 'stroke_start':
      handleStrokeStart(c, msg);
      break;
    case 'stroke_move':
      handleStrokeMove(c, msg);
      break;
    case 'stroke_end':
      handleStrokeEnd(c, msg);
      break;
    case 'board_clear':
      handleBoardClear(c);
      break;
    default:
      break;
  }
}

/* ------------------------------------------------------------------ *
 * HTTP 静态服务
 * ------------------------------------------------------------------ */

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon'
};

function json(res, obj) {
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(obj));
}

const server = http.createServer((req, res) => {
  let url;
  try {
    url = new URL(req.url, 'http://localhost');
  } catch (e) {
    res.writeHead(400); res.end(); return;
  }
  const pathname = url.pathname;

  if (pathname === '/api/rooms') { json(res, { rooms: roomSummaries() }); return; }
  if (pathname === '/api/info') {
    json(res, {
      name: 'LiveRoom', wsPath: '/ws', port: PORT,
      addresses: localAddresses().map((a) => a.address),
      rooms: roomSummaries().length, clients: clients.size
    });
    return;
  }
  if (pathname === '/favicon.ico') { res.writeHead(204); res.end(); return; }

  const rel = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const file = path.resolve(PUBLIC_DIR, rel);
  if (!file.startsWith(path.resolve(PUBLIC_DIR))) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Cache-Control': 'no-cache'
    });
    res.end(data);
  });
});

server.on('upgrade', (req, socket, head) => {
  let pathname;
  try {
    pathname = new URL(req.url, 'http://localhost').pathname;
  } catch (e) {
    socket.destroy(); return;
  }
  if (pathname !== '/ws') { socket.destroy(); return; }
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }
  const accept = crypto.createHash('sha1').update(key + WS_GUID).digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    'Sec-WebSocket-Accept: ' + accept + '\r\n\r\n'
  );

  const c = {
    id: 'u' + (++seq).toString(36) + Date.now().toString(36).slice(-4),
    socket: socket,
    buf: Buffer.alloc(0),
    fragOpcode: 0,
    fragBuf: [],
    name: '匿名',
    color: COLORS[clients.size % COLORS.length],
    roomId: null,
    lastSeen: Date.now()
  };
  clients.add(c);

  socket.on('data', (chunk) => {
    c.lastSeen = Date.now();
    try {
      parseFrames(c, chunk);
    } catch (e) {
      console.error('[frame]', e.message);
      socket.destroy();
    }
  });
  socket.on('close', () => {
    leaveRoom(c, true);
    clients.delete(c);
  });
  socket.on('error', () => {
    leaveRoom(c, true);
    clients.delete(c);
  });

  sendJson(c, { type: 'hello', clientId: c.id, rooms: roomSummaries() });
  if (head && head.length) parseFrames(c, head);
});

const heartbeat = setInterval(() => {
  const now = Date.now();
  for (const c of clients) {
    if (now - c.lastSeen > 60000) {
      try { c.socket.destroy(); } catch (e) { /* ignore */ }
      continue;
    }
    sendFrame(c.socket, 0x9, Buffer.alloc(0)); // 浏览器会自动回 pong
  }
}, 20000);
heartbeat.unref();

function localAddresses() {
  const out = [];
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const i of ifaces[name] || []) {
      if ((i.family === 'IPv4' || i.family === 4) && !i.internal) {
        const label = name.toLowerCase();
        let score = 0;
        // 真无线网卡优先；VMware / 虚拟适配器降权，避免把手机指到连不上的地址
        if (/wlan|wi-?fi|无线|wireless/.test(label)) score += 100;
        if (/vmware|vmnet|virtual|loopback|docker|hyper-v|虚拟|vethernet|bluetooth/.test(label)) score -= 100;
        if (/^192\.168\.(56|72)\./.test(i.address)) score -= 50;
        out.push({ name: name, address: i.address, score: score });
      }
    }
  }
  out.sort((a, b) => b.score - a.score);
  return out;
}

server.listen(PORT, BIND, () => {
  const lines = [];
  lines.push('');
  lines.push('  LiveRoom 服务端已启动');
  lines.push('  ─────────────────────────────────────────────────');
  lines.push(`  本机访问     http://localhost:${PORT}`);
  const addrs = localAddresses();
  if (addrs.length === 0) {
    lines.push('  未检测到局域网地址，请检查网络连接');
  } else {
    addrs.forEach((a, idx) => {
      const tag = a.score < 0 ? '虚拟网卡，手机连不上' : (idx === 0 ? '推荐' : '备选');
      lines.push(`  ${idx === 0 ? '分享给朋友  ' : '            '}http://${a.address}:${PORT}   (${a.name} · ${tag})`);
    });
    lines.push(`  WebSocket    ws://${addrs[0].address}:${PORT}/ws`);
  }
  lines.push('  ─────────────────────────────────────────────────');
  lines.push('  手机与电脑连同一 WiFi，用上面标「推荐」的地址打开');
  lines.push('  HarmonyOS 端把 IP:端口 填进首页的服务器地址栏');
  lines.push('  Ctrl+C 停止服务');
  lines.push('');
  console.log(lines.join('\n'));
});

process.on('SIGINT', () => {
  clearInterval(heartbeat);
  console.log('\n  LiveRoom 已停止');
  process.exit(0);
});
