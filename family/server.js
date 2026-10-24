#!/usr/bin/env node
// Lookout family dashboard server. Zero dependencies.
// Run: node family/server.js   (PORT=4545, HOST=127.0.0.1 by default)
'use strict';

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const crs = require('./crs');

const ROOT = __dirname;
const PUBLIC_DIR = path.join(ROOT, 'public');

// ---------- env / secrets ----------
function loadSecretsFile(file) {
  try {
    if (!fs.existsSync(file)) return [];
    const loaded = [];
    for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
      const line = raw.trim();
      if (!line || line.startsWith('#')) continue;
      const m = line.replace(/^export\s+/, '').match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
      if (!m) continue;
      let val = m[2].trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) val = val.slice(1, -1);
      if (process.env[m[1]] === undefined) { process.env[m[1]] = val; loaded.push(m[1]); }
    }
    return loaded;
  } catch (e) {
    console.warn('[config] could not read secrets file:', e.message);
    return [];
  }
}

const DATA_DIR = process.env.LOOKOUT_DATA_DIR || path.join(ROOT, 'data');
const STATE_FILE = path.join(DATA_DIR, 'state.json');
const MAX_EVENTS = 500;
const MAX_APPROVALS = 200;
const EVENT_TYPES = ['scam_alert', 'remote_access', 'payment_pause', 'help', 'info'];
const MAX_BODY = 2 * 1024 * 1024; // 2MB (screenshots ~100KB)

// ---------- state ----------
let state = { events: [], approvals: [] };

function loadState() {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    if (fs.existsSync(STATE_FILE)) {
      const s = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
      state.events = Array.isArray(s.events) ? s.events : [];
      state.approvals = Array.isArray(s.approvals) ? s.approvals : [];
    }
  } catch (e) {
    console.warn('[state] could not load state, starting fresh:', e.message);
    state = { events: [], approvals: [] };
  }
}

let saveTimer = null;
function saveState() {
  if (saveTimer) return;
  saveTimer = setTimeout(saveNow, 100);
}
function saveNow() {
  clearTimeout(saveTimer);
  saveTimer = null;
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    const tmp = STATE_FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(state));
    fs.renameSync(tmp, STATE_FILE);
  } catch (e) {
    console.error('[state] save failed:', e.message);
  }
}

function newId(prefix) {
  return prefix + '_' + Date.now().toString(36) + crypto.randomBytes(3).toString('hex');
}

// ---------- SSE ----------
const clients = new Set();
function broadcast(eventName, data) {
  const msg = `event: ${eventName}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const res of clients) {
    try { res.write(msg); } catch (_) { clients.delete(res); }
  }
}
setInterval(() => {
  for (const res of clients) {
    try { res.write(': heartbeat ' + Date.now() + '\n\n'); } catch (_) { clients.delete(res); }
  }
}, 15000).unref();

// ---------- SMS ----------
function smsConfigured() {
  const e = process.env;
  return !!(e.TWILIO_ACCOUNT_SID && e.TWILIO_AUTH_TOKEN && e.TWILIO_FROM && e.FAMILY_PHONE && e.LOOKOUT_SMS_ENABLED === '1');
}

function smsText(ev) {
  const elder = config().elderName;
  const prefix = {
    scam_alert: `Lookout: possible scam on ${elder}'s Mac.`,
    remote_access: `Lookout: someone tried to remote into ${elder}'s Mac.`,
    payment_pause: `Lookout: ${elder} started a payment that needs your OK.`,
    help: `Lookout: ${elder} asked for help.`,
    info: `Lookout:`,
  }[ev.type] || 'Lookout:';
  let body = `${prefix} ${ev.title}`;
  if (ev.action && ev.type !== 'payment_pause') body += ` (${ev.action})`;
  if (ev.type === 'payment_pause') body += ' Open Lookout to approve or deny.';
  const pub = process.env.PUBLIC_URL;
  if (pub) body += ` ${pub}`;
  return body.slice(0, 320);
}

function notify(ev) {
  if (!['scam_alert', 'remote_access', 'payment_pause', 'help'].includes(ev.type)) return;
  const text = smsText(ev);
  if (!smsConfigured()) {
    console.log(`[sms:mock] would text family: "${text}"`);
    return;
  }
  const e = process.env;
  const form = new URLSearchParams({ To: e.FAMILY_PHONE, From: e.TWILIO_FROM, Body: text }).toString();
  const req = https.request({
    hostname: 'api.twilio.com',
    path: `/2010-04-01/Accounts/${encodeURIComponent(e.TWILIO_ACCOUNT_SID)}/Messages.json`,
    method: 'POST',
    auth: `${e.TWILIO_ACCOUNT_SID}:${e.TWILIO_AUTH_TOKEN}`,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(form) },
    timeout: 10000,
  }, (res) => {
    let buf = '';
    res.on('data', (c) => { buf += c; });
    res.on('end', () => {
      if (res.statusCode >= 200 && res.statusCode < 300) console.log(`[sms] sent (${res.statusCode})`);
      else {
        let msg = '';
        try { msg = JSON.parse(buf).message || ''; } catch (_) {}
        console.error(`[sms] Twilio error ${res.statusCode} ${msg}`);
      }
    });
  });
  req.on('timeout', () => req.destroy(new Error('timeout')));
  req.on('error', (err) => console.error('[sms] request failed:', err.message));
  req.write(form);
  req.end();
}

// ---------- domain ----------
function config() {
  return {
    elderName: process.env.ELDER_NAME || 'Mom',
    familyName: process.env.FAMILY_NAME || 'Sarah',
  };
}

function clampRisk(r) {
  const n = Number(r);
  if (!Number.isFinite(n)) return undefined;
  return Math.max(0, Math.min(1, n));
}
function str(v, max) {
  if (v === undefined || v === null) return undefined;
  const s = String(v);
  return max ? s.slice(0, max) : s;
}
function cleanScreenshot(s) {
  if (typeof s !== 'string') return undefined;
  if (!/^data:image\/(jpeg|jpg|png|webp|gif);base64,[A-Za-z0-9+/=\s]+$/.test(s)) return undefined;
  if (s.length > 1.5 * 1024 * 1024) return undefined;
  return s;
}

function addEvent(input, opts = {}) {
  const type = EVENT_TYPES.includes(input.type) ? input.type : 'info';
  const ev = {
    id: newId('evt'),
    ts: typeof input.ts === 'number' ? input.ts : Date.now(),
    type,
    title: str(input.title, 200) || defaultTitle(type),
    explanation: str(input.explanation, 2000) || '',
  };
  const risk = clampRisk(input.risk);
  if (risk !== undefined) ev.risk = risk;
  for (const k of ['url', 'app', 'action']) { const v = str(input[k], 500); if (v) ev[k] = v; }
  const shot = cleanScreenshot(input.screenshot);
  if (shot) ev.screenshot = shot;
  if (input.approvalId) ev.approvalId = String(input.approvalId);
  state.events.push(ev);
  state.events.sort((a, b) => a.ts - b.ts);
  if (state.events.length > MAX_EVENTS) state.events.splice(0, state.events.length - MAX_EVENTS);
  saveState();
  if (!opts.silent) {
    broadcast('event', ev);
    notify(ev);
  }
  return ev;
}

function defaultTitle(type) {
  return {
    scam_alert: 'Possible scam detected',
    remote_access: 'Remote access attempt blocked',
    payment_pause: 'Payment paused for approval',
    help: 'Asked for help',
    info: 'Update from Lookout',
  }[type];
}

function addApproval(input, opts = {}) {
  const ap = {
    id: newId('apr'),
    ts: typeof input.ts === 'number' ? input.ts : Date.now(),
    status: 'pending',
    title: str(input.title, 200) || 'Payment needs your approval',
    explanation: str(input.explanation, 2000) || '',
  };
  if (input.amount !== undefined && input.amount !== null && input.amount !== '') {
    const n = Number(input.amount);
    ap.amount = Number.isFinite(n) ? n : str(input.amount, 50);
  }
  for (const k of ['payee', 'method', 'currency']) { const v = str(input[k], 200); if (v) ap[k] = v; }
  const risk = clampRisk(input.risk);
  if (risk !== undefined) ap.risk = risk;
  const shot = cleanScreenshot(input.screenshot);
  if (shot) ap.screenshot = shot;
  state.approvals.push(ap);
  if (state.approvals.length > MAX_APPROVALS) {
    // drop oldest decided first
    const idx = state.approvals.findIndex((a) => a.status !== 'pending');
    state.approvals.splice(idx >= 0 ? idx : 0, 1);
  }
  const ev = addEvent({
    type: 'payment_pause',
    ts: ap.ts,
    title: ap.title,
    explanation: ap.explanation,
    risk: ap.risk,
    screenshot: ap.screenshot,
    action: input.action || 'Paused the payment and asked you first',
    approvalId: ap.id,
  }, opts);
  ap.eventId = ev.id;
  saveState();
  if (!opts.silent) broadcast('approval', ap);
  return ap;
}

function decideApproval(id, status, note) {
  const ap = state.approvals.find((a) => a.id === id);
  if (!ap) return { error: 404 };
  if (ap.status !== 'pending') return { error: 409, ap };
  ap.status = status;
  ap.decidedAt = Date.now();
  const n = str(note, 500);
  if (n && n.trim()) ap.note = n.trim();
  saveState();
  broadcast('approval', ap);
  return { ap };
}

function publicApproval(ap, full) {
  if (full) return ap;
  const out = { id: ap.id, status: ap.status };
  if (ap.note) out.note = ap.note;
  if (ap.decidedAt) out.decidedAt = ap.decidedAt;
  return out;
}

function summary() {
  const now = Date.now();
  const DAY = 86400000;
  const since = now - 7 * DAY;
  const evs = state.events.filter((e) => e.ts >= since);
  const aps = state.approvals.filter((a) => a.ts >= since);
  const byType = Object.fromEntries(EVENT_TYPES.map((t) => [t, 0]));
  for (const e of evs) byType[e.type] = (byType[e.type] || 0) + 1;

  // per-day: last 7 local days, oldest first
  const days = [];
  const startToday = new Date(); startToday.setHours(0, 0, 0, 0);
  for (let i = 6; i >= 0; i--) {
    const d = new Date(startToday.getTime() - i * DAY);
    const next = new Date(d.getTime() + DAY);
    const dayEvs = state.events.filter((e) => e.ts >= d.getTime() && e.ts < next.getTime());
    const counts = Object.fromEntries(EVENT_TYPES.map((t) => [t, 0]));
    for (const e of dayEvs) counts[e.type]++;
    days.push({
      date: d.toISOString().slice(0, 10),
      label: d.toLocaleDateString('en-US', { weekday: 'short' }),
      total: dayEvs.length,
      counts,
    });
  }

  const scamsStopped = byType.scam_alert + byType.remote_access;
  const payments = {
    paused: aps.length || byType.payment_pause,
    approved: aps.filter((a) => a.status === 'approved').length,
    denied: aps.filter((a) => a.status === 'denied').length,
    pending: aps.filter((a) => a.status === 'pending').length,
  };
  const moneyProtected = aps
    .filter((a) => a.status === 'denied' && typeof a.amount === 'number')
    .reduce((s, a) => s + a.amount, 0);

  const { elderName } = config();
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
  let headline;
  if (evs.length === 0) headline = `All quiet. Nothing worrying on ${elderName}'s Mac this week.`;
  else if (scamsStopped === 0 && payments.paused === 0) headline = `Quiet week. Nothing risky came up for ${elderName}.`;
  else {
    const tone = scamsStopped + payments.paused <= 5 ? 'Quiet week.' : 'Busy week.';
    const parts = [];
    if (scamsStopped) parts.push(`stopped ${plural(scamsStopped, 'scam attempt')}`);
    if (payments.paused) parts.push(`paused ${plural(payments.paused, 'payment')}`);
    headline = `${tone} Lookout ${parts.join(' and ')}.`;
  }
  if (payments.pending) headline += ` ${plural(payments.pending, 'payment')} still waiting on you.`;

  return {
    from: since,
    to: now,
    total: evs.length,
    countsByType: byType,
    scamsStopped,
    remoteAccessBlocked: byType.remote_access,
    payments,
    moneyProtected,
    helpSessions: byType.help,
    headline,
    perDay: days,
  };
}

function seedDemo() {
  const now = Date.now();
  const H = 3600000, D = 24 * H;
  const at = (daysAgo, hour, min = 0) => {
    const d = new Date(now - daysAgo * D); d.setHours(hour, min, 0, 0);
    return Math.min(d.getTime(), now - 60000);
  };
  const o = { silent: true };
  addEvent({ type: 'info', ts: at(6, 9, 5), title: 'Lookout is watching', explanation: 'Protection was turned on and is running quietly in the background.' }, o);
  addEvent({ type: 'scam_alert', ts: at(6, 14, 22), risk: 0.93, app: 'Safari', url: 'http://apple-support-alert.help/fix', title: 'Fake "virus detected" pop-up', explanation: 'A web page pretended to be Apple and told her to call a phone number. Real Apple warnings never ask you to call.', action: 'Closed the tab and showed a calm warning' }, o);
  addEvent({ type: 'help', ts: at(5, 11, 40), app: 'Mail', title: 'Asked: "Is this email from my bank real?"', explanation: 'Lookout explained the email was a real statement from Chase and nothing needed to be done.' }, o);
  addEvent({ type: 'info', ts: at(4, 16, 10), app: 'Messages', title: 'Checked a text about a package', explanation: 'A delivery text looked fine — it came from a USPS short code and had no links.' }, o);
  addEvent({ type: 'remote_access', ts: at(3, 10, 3), risk: 0.97, app: 'AnyDesk', title: 'Someone tried to take control of the Mac', explanation: 'A caller claiming to be from "Microsoft" asked her to install AnyDesk. Lookout recognised the remote-control app and blocked it.', action: 'Closed AnyDesk' }, o);
  const ap1 = addApproval({ ts: at(3, 10, 9), title: '$500 in Target gift cards', explanation: 'Right after the remote-access attempt, she started buying gift cards online. Scammers often ask for gift cards because they cannot be traced.', amount: 500, payee: 'Target.com gift cards', method: 'gift card', risk: 0.95 }, o);
  ap1.status = 'denied'; ap1.decidedAt = at(3, 10, 12); ap1.note = 'Mom, this is a scam — I\'ll call you now. Love, Sarah';
  addEvent({ type: 'scam_alert', ts: at(2, 19, 45), risk: 0.81, app: 'Mail', title: 'Email asking to "verify" her Medicare number', explanation: 'The message came from a look-alike address and linked to a fake form. Medicare never asks for your number by email.', action: 'Hid the link and warned her' }, o);
  addEvent({ type: 'help', ts: at(1, 15, 30), app: 'FaceTime', title: 'Asked for help joining a FaceTime call', explanation: 'Lookout walked her through answering the call from the grandkids.' }, o);
  const ap2 = addApproval({ ts: at(1, 12, 15), title: '$64.20 to CVS Pharmacy', explanation: 'A card payment on cvs.com for a prescription refill. Looks normal, but it was a new card on file.', amount: 64.2, payee: 'CVS Pharmacy', method: 'card', risk: 0.2 }, o);
  ap2.status = 'approved'; ap2.decidedAt = at(1, 12, 20); ap2.note = 'All good!';
  saveState();
}

// ---------- HTTP helpers ----------
function send(res, status, body, headers = {}) {
  const isBuf = Buffer.isBuffer(body);
  const payload = isBuf || typeof body === 'string' ? body : JSON.stringify(body);
  res.writeHead(status, {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Content-Type': isBuf || typeof body === 'string' ? 'text/plain; charset=utf-8' : 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    ...headers,
  });
  res.end(payload);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) { reject(Object.assign(new Error('Body too large'), { status: 413 })); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8').trim();
      if (!raw) return resolve({});
      try {
        const j = JSON.parse(raw);
        resolve(j && typeof j === 'object' ? j : {});
      } catch (_) { reject(Object.assign(new Error('Invalid JSON'), { status: 400 })); }
    });
    req.on('error', reject);
  });
}

const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json', '.jpg': 'image/jpeg',
};
function serveStatic(req, res, pathname) {
  let rel = decodeURIComponent(pathname);
  if (rel === '/' || rel === '') rel = '/index.html';
  const file = path.normalize(path.join(PUBLIC_DIR, rel));
  if (!file.startsWith(PUBLIC_DIR + path.sep)) return send(res, 403, 'Forbidden');
  fs.readFile(file, (err, buf) => {
    if (err) return send(res, 404, { ok: false, error: 'Not found' });
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-cache',
    });
    res.end(req.method === 'HEAD' ? undefined : buf);
  });
}

// ---------- router ----------
async function handle(req, res) {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname.replace(/\/+$/, '') || '/';
  const m = req.method;

  if (m === 'OPTIONS') return send(res, 204, '');
  if (p === '/healthz') return send(res, 200, 'ok');

  if (p.startsWith('/api/')) {
    if (p === '/api/config' && m === 'GET') return send(res, 200, config());

    if (p === '/api/stream' && m === 'GET') {
      res.writeHead(200, {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        Connection: 'keep-alive',
        'Access-Control-Allow-Origin': '*',
        'X-Accel-Buffering': 'no',
      });
      res.write('retry: 3000\n: connected\n\n');
      clients.add(res);
      req.on('close', () => clients.delete(res));
      return;
    }

    if (p === '/api/events') {
      if (m === 'GET') {
        const limit = Math.max(1, Math.min(MAX_EVENTS, parseInt(url.searchParams.get('limit'), 10) || 100));
        const type = url.searchParams.get('type');
        let list = state.events;
        if (type) list = list.filter((e) => e.type === type);
        return send(res, 200, list.slice(-limit).reverse());
      }
      if (m === 'POST') {
        const body = await readBody(req);
        if (body.type && !EVENT_TYPES.includes(body.type)) return send(res, 400, { ok: false, error: `type must be one of ${EVENT_TYPES.join(', ')}` });
        if (!body.title) return send(res, 400, { ok: false, error: 'title is required' });
        const ev = addEvent(body);
        return send(res, 201, { ok: true, id: ev.id, ts: ev.ts });
      }
    }

    if (p === '/api/approvals') {
      if (m === 'GET') {
        const status = url.searchParams.get('status');
        let list = state.approvals;
        if (status) list = list.filter((a) => a.status === status);
        return send(res, 200, list.slice().reverse());
      }
      if (m === 'POST') {
        const body = await readBody(req);
        const ap = addApproval(body);
        return send(res, 201, { ok: true, id: ap.id, status: ap.status, eventId: ap.eventId });
      }
    }

    let mm;
    if ((mm = p.match(/^\/api\/approvals\/([\w-]+)$/)) && m === 'GET') {
      const ap = state.approvals.find((a) => a.id === mm[1]);
      if (!ap) return send(res, 404, { ok: false, error: 'Not found' });
      return send(res, 200, publicApproval(ap, url.searchParams.get('full') === '1'));
    }
    if ((mm = p.match(/^\/api\/approvals\/([\w-]+)\/(approve|deny)$/)) && m === 'POST') {
      const body = await readBody(req);
      const r = decideApproval(mm[1], mm[2] === 'approve' ? 'approved' : 'denied', body.note);
      if (r.error === 404) return send(res, 404, { ok: false, error: 'Not found' });
      if (r.error === 409) return send(res, 409, { ok: false, error: `Already ${r.ap.status}`, ...publicApproval(r.ap) });
      return send(res, 200, { ok: true, ...publicApproval(r.ap) });
    }

    if (p === '/api/summary' && m === 'GET') return send(res, 200, summary());

    // CRS Fraud Finder check of a suspicious message's SENDER (scammer-side data only).
    if (p === '/api/crs/check-sender' && m === 'POST') {
      const body = await readBody(req);
      const r = await crs.checkSender(body.email);
      if (r.error === 'invalid email') return send(res, 400, { ok: false, error: 'email is required' });
      return send(res, 200, { ok: true, ...r });
    }
    if (p === '/api/crs/status' && m === 'GET') return send(res, 200, { configured: crs.configured() });

    if (p === '/api/demo/seed' && m === 'POST') {
      seedDemo();
      broadcast('reload', { reason: 'seed' });
      return send(res, 200, { ok: true, events: state.events.length, approvals: state.approvals.length });
    }
    if (p === '/api/demo/reset' && m === 'POST') {
      state = { events: [], approvals: [] };
      saveNow();
      broadcast('reload', { reason: 'reset' });
      return send(res, 200, { ok: true });
    }

    return send(res, 404, { ok: false, error: 'Not found' });
  }

  if (m === 'GET' || m === 'HEAD') return serveStatic(req, res, p);
  return send(res, 405, { ok: false, error: 'Method not allowed' });
}

function lanIPs() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const ni of list || []) {
      if ((ni.family === 'IPv4' || ni.family === 4) && !ni.internal) out.push(ni.address);
    }
  }
  return out;
}

function start({ port, host, quiet } = {}) {
  loadState();
  const server = http.createServer((req, res) => {
    handle(req, res).catch((err) => {
      const status = err.status || 500;
      if (status === 500) console.error('[http] error:', err);
      if (!res.headersSent) send(res, status, { ok: false, error: err.message });
      else res.end();
    });
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      const actualPort = server.address().port;
      if (!quiet) {
        const { elderName, familyName } = config();
        console.log(`Lookout family dashboard — watching over ${elderName} for ${familyName}`);
        console.log(`  Local:   http://127.0.0.1:${actualPort}`);
        if (host === '0.0.0.0' || host === '::') {
          for (const ip of lanIPs()) console.log(`  Network: http://${ip}:${actualPort}   (open on a phone on the same Wi-Fi)`);
        } else {
          const ips = lanIPs();
          console.log(`  Network: not exposed (set HOST=0.0.0.0 to open on a phone${ips[0] ? `, e.g. http://${ips[0]}:${actualPort}` : ''})`);
        }
        console.log(`  SMS:     ${smsConfigured() ? 'Twilio enabled' : 'mock (console only)'}`);
        console.log(`  Data:    ${STATE_FILE}`);
      }
      resolve(server);
    });
  });
}

module.exports = { start, notify };

if (require.main === module) {
  const loaded = loadSecretsFile(path.join(os.homedir(), '.config', 'lookout', 'secrets.env'));
  if (loaded.length) console.log(`[config] loaded ${loaded.length} value(s) from ~/.config/lookout/secrets.env (${loaded.join(', ')})`);
  const envPort = parseInt(process.env.PORT, 10);
  const port = Number.isInteger(envPort) && envPort >= 0 ? envPort : 4545;
  const host = process.env.HOST || '127.0.0.1';
  start({ port, host }).catch((err) => {
    console.error('Failed to start:', err.message);
    process.exit(1);
  });
  const shutdown = () => { saveNow(); process.exit(0); };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
