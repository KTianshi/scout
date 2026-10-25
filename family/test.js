#!/usr/bin/env node
// Self-test: node family/test.js  — starts the server on a random port with a temp
// data dir, exercises the API, exits 0 on success / 1 on failure. Never sends SMS.
'use strict';
const { spawn } = require('child_process');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'scout-family-test-'));
const env = { ...process.env, PORT: '0', HOST: '127.0.0.1', SCOUT_DATA_DIR: dataDir, SCOUT_SMS_ENABLED: '0', ELDER_NAME: 'Grandma', FAMILY_NAME: 'Sam' };
for (const k of ['TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'TWILIO_FROM', 'FAMILY_PHONE']) delete env[k];

const child = spawn(process.execPath, [path.join(__dirname, 'server.js')], { env, stdio: ['ignore', 'pipe', 'pipe'] });
let out = '';
let port = null;

function req(method, p, body, raw) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : JSON.stringify(body);
    const r = http.request({ host: '127.0.0.1', port, path: p, method, headers: data ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } : {} }, (res) => {
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => {
        let json = null;
        if (!raw) { try { json = JSON.parse(buf); } catch (_) {} }
        resolve({ status: res.statusCode, headers: res.headers, body: raw ? buf : json });
      });
    });
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

let passed = 0;
function check(cond, msg) {
  if (!cond) throw new Error('FAIL: ' + msg);
  passed++;
  console.log('  ok  ' + msg);
}

function openStream() {
  return new Promise((resolve) => {
    const received = [];
    const r = http.get({ host: '127.0.0.1', port, path: '/api/stream' }, (res) => {
      res.setEncoding('utf8');
      let buf = '';
      res.on('data', (c) => {
        buf += c;
        let i;
        while ((i = buf.indexOf('\n\n')) >= 0) {
          const chunk = buf.slice(0, i); buf = buf.slice(i + 2);
          const ev = (chunk.match(/^event: (.*)$/m) || [])[1];
          const data = (chunk.match(/^data: (.*)$/m) || [])[1];
          if (ev) received.push({ ev, data: JSON.parse(data) });
        }
      });
      resolve({ received, close: () => r.destroy(), headers: res.headers });
    });
  });
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function run() {
  check((await req('GET', '/healthz', undefined, true)).body === 'ok', 'GET /healthz');
  const cfg = await req('GET', '/api/config');
  check(cfg.body.elderName === 'Grandma' && cfg.body.familyName === 'Sam', 'GET /api/config uses env');
  check(cfg.headers['access-control-allow-origin'] === '*', 'CORS header present');

  const home = await req('GET', '/', undefined, true);
  check(home.status === 200 && home.body.includes('<title>'), 'GET / serves index.html');

  const stream = await openStream();
  check(/text\/event-stream/.test(stream.headers['content-type']), 'SSE stream opens');

  const bad = await req('POST', '/api/events', { type: 'nope', title: 'x' });
  check(bad.status === 400, 'invalid event type rejected');

  const shot = 'data:image/jpeg;base64,' + Buffer.alloc(90 * 1024, 7).toString('base64');
  const ev = await req('POST', '/api/events', { type: 'scam_alert', title: 'Fake Apple support page', explanation: 'Asked her to call a number.', risk: 0.9, url: 'http://evil.example', app: 'Safari', screenshot: shot, action: 'Closed the tab' });
  check(ev.status === 201 && ev.body.ok && ev.body.id, 'POST /api/events');

  const list = await req('GET', '/api/events?limit=5');
  check(Array.isArray(list.body) && list.body[0].id === ev.body.id && list.body[0].screenshot === shot && typeof list.body[0].ts === 'number', 'GET /api/events newest first, keeps screenshot');

  const ap = await req('POST', '/api/approvals', { title: '$500 gift cards', explanation: 'Buying gift cards', amount: 500, payee: 'Target', method: 'gift card', risk: 0.95 });
  check(ap.status === 201 && ap.body.id && ap.body.status === 'pending', 'POST /api/approvals');

  const pend = await req('GET', '/api/approvals?status=pending');
  check(pend.body.length === 1 && pend.body[0].id === ap.body.id, 'GET /api/approvals?status=pending');

  const feed = await req('GET', '/api/events?limit=1');
  check(feed.body[0].type === 'payment_pause' && feed.body[0].approvalId === ap.body.id, 'approval created payment_pause feed event');

  const poll1 = await req('GET', '/api/approvals/' + ap.body.id);
  check(poll1.body.status === 'pending', 'GET /api/approvals/:id pending');

  const dec = await req('POST', '/api/approvals/' + ap.body.id + '/approve', { note: 'ok mom' });
  check(dec.status === 200 && dec.body.status === 'approved', 'POST /api/approvals/:id/approve');

  const poll2 = await req('GET', '/api/approvals/' + ap.body.id);
  check(poll2.body.status === 'approved' && poll2.body.note === 'ok mom' && poll2.body.decidedAt, 'poll shows approved + note + decidedAt');

  const again = await req('POST', '/api/approvals/' + ap.body.id + '/deny');
  check(again.status === 409, 'second decision rejected (409)');

  const missing = await req('GET', '/api/approvals/apr_nope');
  check(missing.status === 404, 'unknown approval 404');

  await wait(150);
  const kinds = stream.received.map((r) => r.ev);
  check(kinds.filter((k) => k === 'event').length >= 2 && kinds.filter((k) => k === 'approval').length >= 2, 'SSE broadcast event + approval messages');
  stream.close();

  const sum = await req('GET', '/api/summary');
  check(sum.body.scamsStopped === 1 && sum.body.payments.paused === 1 && sum.body.payments.approved === 1, 'summary counts');
  check(typeof sum.body.headline === 'string' && sum.body.headline.length > 5 && sum.body.perDay.length === 7, 'summary headline + perDay');
  console.log('      headline: ' + sum.body.headline);

  await req('POST', '/api/demo/reset');
  const seeded = await req('POST', '/api/demo/seed');
  check(seeded.body.ok && seeded.body.events >= 5, 'POST /api/demo/seed');
  const sum2 = await req('GET', '/api/summary');
  check(sum2.body.scamsStopped >= 2 && sum2.body.payments.denied >= 1, 'seeded summary looks alive');
  console.log('      headline: ' + sum2.body.headline);

  await wait(250);
  const stateFile = path.join(dataDir, 'state.json');
  check(fs.existsSync(stateFile) && JSON.parse(fs.readFileSync(stateFile, 'utf8')).events.length >= 5, 'state persisted to disk');

  check(!/\[sms\] sent/.test(out), 'no real SMS sent');
  check(/\[sms:mock\]/.test(out), 'mock SMS logged');
}

const timeout = setTimeout(() => finish(new Error('timeout')), 15000);
function finish(err) {
  clearTimeout(timeout);
  child.kill();
  try { fs.rmSync(dataDir, { recursive: true, force: true }); } catch (_) {}
  if (err) {
    console.error(err.message);
    console.error('--- server output ---\n' + out);
    process.exit(1);
  }
  console.log(`\nAll ${passed} checks passed.`);
  process.exit(0);
}

child.stdout.on('data', (c) => {
  out += c;
  const m = out.match(/Local:\s+http:\/\/127\.0\.0\.1:(\d+)/);
  if (m && !port) {
    port = Number(m[1]);
    run().then(() => finish(), finish);
  }
});
child.stderr.on('data', (c) => (out += c));
child.on('exit', (code) => { if (!port) finish(new Error('server exited early with code ' + code)); });
