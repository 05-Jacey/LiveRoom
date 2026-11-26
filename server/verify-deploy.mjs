'use strict';

/**
 * 部署自检：一条命令确认云端服务端真的可用（HTTP + WebSocket 全链路）。
 *
 *   node verify-deploy.mjs                          # 检查本机
 *   node verify-deploy.mjs https://xxx.onrender.com  # 检查云端部署
 *
 * 需要 Node 18+（用到全局 fetch 和 WebSocket），零依赖。
 */

const base = (process.argv[2] || 'http://localhost:3000').replace(/\/+$/, '');
const u = new URL(base);
const wsUrl = (u.protocol === 'https:' ? 'wss://' : 'ws://') + u.host + '/ws';
const results = [];
const TIMEOUT = 12000;

function pass(label, extra) {
  results.push(true);
  console.log('PASS  ' + label + (extra ? '  ' + extra : ''));
}
function fail(label, err) {
  results.push(false);
  console.log('FAIL  ' + label + '  ' + err);
}

async function checkHttp(pathname, label, wantText) {
  try {
    const res = await fetch(base + pathname, { signal: AbortSignal.timeout(TIMEOUT) });
    const body = await res.text();
    if (res.status !== 200) { fail(label, 'HTTP ' + res.status); return false; }
    if (wantText && !body.includes(wantText)) { fail(label, '响应内容不含 ' + wantText); return false; }
    pass(label, 'HTTP 200');
    return true;
  } catch (e) {
    fail(label, e.message);
    return false;
  }
}

function checkWebSocket() {
  return new Promise((resolve) => {
    const types = [];
    let done = false;
    const finish = (ok, label, err) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try { ws.close(); } catch (e) { /* ignore */ }
      if (ok) pass(label, types.join(', ')); else fail(label, err || '超时');
      resolve(ok);
    };
    const timer = setTimeout(() => finish(false, 'WebSocket 全链路', TIMEOUT + 'ms 超时'), TIMEOUT);
    let ws;
    try {
      ws = new WebSocket(wsUrl);
    } catch (e) {
      finish(false, 'WebSocket 握手', e.message);
      return;
    }
    ws.onmessage = (e) => {
      let m;
      try { m = JSON.parse(String(e.data)); } catch (err) { return; }
      types.push(m.type);
      if (m.type === 'joined') {
        ws.send(JSON.stringify({ type: 'chat', text: 'deploy-check' }));
      }
      if (m.type === 'chat' && m.text === 'deploy-check') {
        finish(true, 'WebSocket 全链路（握手 → 入房 → 消息回传）');
      }
    };
    ws.onopen = () => {
      ws.send(JSON.stringify({ type: 'join', roomId: 'chat-lobby', name: '部署自检' }));
    };
    ws.onerror = () => finish(false, 'WebSocket 握手', '连接错误（检查域名 / wss / 服务是否休眠）');
    ws.onclose = (e) => {
      if (!done) finish(false, 'WebSocket 握手', '提前关闭 code=' + e.code);
    };
  });
}

async function main() {
  console.log('目标：' + base);
  console.log('WebSocket：' + wsUrl);
  console.log('');
  await checkHttp('/', '静态页面可访问', 'LiveRoom');
  const info = await checkHttp('/api/info', '健康检查接口');
  await checkHttp('/api/rooms', '房间列表接口');
  await checkWebSocket();
  console.log('');
  const ok = results.length === 4 && results.every(Boolean);
  console.log(ok ? '全部通过：这个地址可以发给朋友了' : '有失败项：按上面的 FAIL 排查（常见原因是免费层休眠或 wss 未生效）');
  process.exit(ok ? 0 : 1);
}

main().catch((e) => {
  console.error('自检脚本异常：' + e.message);
  process.exit(1);
});
