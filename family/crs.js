// CRS Credit API client (sandbox): checks the SENDER of a suspicious message with CRS Fraud Finder
// (AtData email risk). Only scammer-side identifiers are ever sent; nothing about the person Scout protects.
//
// Credentials: CRS_USERNAME / CRS_PASSWORD (env or ~/.config/lookout/secrets.env). Never logged.
// Without credentials, or if CRS is unreachable, a clearly-labelled mock answer is returned so demos keep working.
'use strict';

const https = require('https');

const BASE = process.env.CRS_BASE_URL || 'https://api-sandbox.stitchcredit.com:443/api';
const CACHE_MS = 24 * 3600 * 1000;
const cache = new Map(); // email -> { at, result }
let token = null;
let tokenExpires = 0;

function configured() {
  return !!(process.env.CRS_USERNAME && process.env.CRS_PASSWORD) && process.env.CRS_MOCK !== '1';
}

function request(method, path, body, auth) {
  return new Promise((resolve, reject) => {
    const url = new URL(BASE + path);
    const data = body ? JSON.stringify(body) : null;
    const req = https.request(url, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}),
        ...(auth ? { Authorization: 'Bearer ' + auth } : {}),
      },
      timeout: 15000,
    }, (res) => {
      let raw = '';
      res.on('data', (c) => { raw += c; });
      res.on('end', () => {
        let json = null;
        try { json = raw ? JSON.parse(raw) : null; } catch (_) { /* non-JSON */ }
        resolve({ status: res.statusCode, json, raw: raw.slice(0, 300) });
      });
    });
    req.on('timeout', () => req.destroy(new Error('CRS request timed out')));
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function login() {
  if (token && Date.now() < tokenExpires - 60000) return token;
  const r = await request('POST', '/users/login', { username: process.env.CRS_USERNAME, password: process.env.CRS_PASSWORD });
  if (r.status !== 200 || !r.json || !r.json.token) throw new Error(`CRS login failed (HTTP ${r.status})`);
  token = r.json.token;
  tokenExpires = Date.now() + (r.json.expires || 3600) * 1000;
  return token;
}

// Plain-language summary + a coarse verdict the Mac app turns into model evidence.
function interpret(email, j, source) {
  const risk = (j && j.risk) || {};
  const eam = (j && j.eam) || {};
  const score = typeof risk.score === 'number' ? risk.score : null;
  const domainRisk = risk.domain && typeof risk.domain.domain_risk_score === 'number' ? risk.domain.domain_risk_score : null;
  const firstSeen = eam.date_first_seen || null;
  const longevity = typeof eam.longevity === 'number' ? eam.longevity : null;
  const status = (j && j.email_validation && j.email_validation.status) || null;
  const today = new Date().toISOString().slice(0, 10);
  const newToday = firstSeen === 'now' || firstSeen === today;

  let verdict = 'unknown';
  if (score !== null) {
    if (score >= 80 || (domainRisk !== null && domainRisk >= 8)) verdict = 'high';
    else if (score <= 30 && (longevity === null || longevity >= 1)) verdict = 'low';
    else verdict = 'medium';
  }
  let sentence;
  if (verdict === 'high') {
    sentence = newToday
      ? 'I checked who sent this. That email address first appeared today and is rated very high risk.'
      : `I checked who sent this. That email address is rated high risk (${score} out of 100).`;
  } else if (verdict === 'low') {
    sentence = firstSeen ? `The sender's address has been in use since ${firstSeen.slice(0, 4)} and looks normal.` : "The sender's address looks normal.";
  } else {
    sentence = "I couldn't tell much about who sent this.";
  }
  return { email, verdict, score, domainRisk, firstSeen, longevity, status, newToday, sentence, source };
}

// Offline stand-in: crude domain heuristics, clearly marked source:"mock".
function mock(email) {
  const domain = (email.split('@')[1] || '').toLowerCase();
  const established = ['gmail.com', 'yahoo.com', 'outlook.com', 'icloud.com', 'amazon.com', 'apple.com', 'irs.gov', 'ssa.gov', 'paypal.com', 'chase.com'];
  if (established.some((d) => domain === d || domain.endsWith('.' + d))) {
    return interpret(email, { risk: { score: 5, domain: { domain_risk_score: 1 } }, eam: { date_first_seen: '2010-01-01', longevity: 3 } }, 'mock');
  }
  const scammy = /-|gov|irs|ssa|treasury|refund|billing|support|secure|verify|renew/.test(domain) || /\.(info|co|xyz|top|live|online|site)$/.test(domain);
  return interpret(email, scammy
    ? { risk: { score: 100, domain: { domain_risk_score: 10 } }, eam: { date_first_seen: new Date().toISOString().slice(0, 10), longevity: 0 } }
    : { risk: { score: 50, domain: { domain_risk_score: 5 } }, eam: { date_first_seen: null, longevity: null } }, 'mock');
}

async function checkSender(emailRaw) {
  const email = String(emailRaw || '').trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/.test(email)) return { error: 'invalid email' };
  const hit = cache.get(email);
  if (hit && Date.now() - hit.at < CACHE_MS) return { ...hit.result, cached: true };
  let result;
  if (!configured()) {
    result = mock(email);
  } else {
    try {
      const t = await login();
      const r = await request('POST', '/fraud-finder/fraud-finder', { email }, t);
      if (r.status !== 200 || !r.json) throw new Error(`Fraud Finder HTTP ${r.status}`);
      result = interpret(email, r.json, 'crs');
    } catch (e) {
      console.warn('[crs] falling back to mock:', e.message);
      result = mock(email);
      result.error = e.message;
    }
  }
  cache.set(email, { at: Date.now(), result });
  console.log(`[crs] sender ${email.replace(/^[^@]+/, '***')} → ${result.verdict} (score ${result.score}, ${result.source})`);
  return result;
}

module.exports = { checkSender, configured, _interpret: interpret, _mock: mock };
