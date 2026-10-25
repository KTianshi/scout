# Scout — family dashboard

The family side of Scout: a tiny zero-dependency Node server plus a mobile-first web page. The Mac app posts alerts and payment-approval requests here, and a family member watches them live on their phone. This is the phone that buzzes in the demo.

## Run

```bash
node family/server.js                 # http://127.0.0.1:4545 (this machine only)
HOST=0.0.0.0 node family/server.js    # also reachable from a phone on the same Wi-Fi
node family/test.js                   # self-test: random port + temp data dir, exits 0/1
```

The server needs Node 18+ (tested on v24) and has no npm dependencies or build step. It works from the repo root or from inside `family/`. At startup it prints the local URL and, with `HOST=0.0.0.0`, the LAN URL(s) to open on the phone.

For the demo: `curl -X POST localhost:4545/api/demo/seed` fills the past week with realistic history so "This week" looks lived-in. Open the page on the phone and tap once anywhere so the browser allows the chime.

## Environment

| Var | Default | Meaning |
|---|---|---|
| `PORT` | `4545` | Listen port (`0` = random) |
| `HOST` | `127.0.0.1` | Bind address; `0.0.0.0` exposes it on the LAN |
| `ELDER_NAME` | `Mom` | Person being protected ("Watching over Mom") |
| `FAMILY_NAME` | `Sarah` | Family member using the dashboard |
| `SCOUT_DATA_DIR` | `family/data` | Where `state.json` lives (gitignored) |
| `PUBLIC_URL` | unset | When set, it is appended to SMS texts as a link |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM`, `FAMILY_PHONE` | unset | Twilio credentials and numbers |
| `SCOUT_SMS_ENABLED` | unset | Must be `1` to send real SMS, even when all the Twilio vars are set |

The server also reads `~/.config/scout/secrets.env` (simple `KEY=VALUE` lines; `#` comments, optional quotes and `export` are allowed). Real environment variables take precedence over the file. Only key **names** are logged, never values.

## SMS

`notify(event)` runs for `scam_alert`, `remote_access`, `payment_pause` and `help` events. It sends a text only when all four Twilio vars are set **and** `SCOUT_SMS_ENABLED=1`. It POSTs to `https://api.twilio.com/2010-04-01/Accounts/{SID}/Messages.json` using the built-in `https` module. Otherwise it only logs:

```
[sms:mock] would text family: "Scout: someone tried to remote into Mom's Mac. ... (Closed AnyDesk)"
```

## API

JSON in and out. CORS is `*`. `OPTIONS` preflight is handled. Bodies are limited to 2 MB.

### Events

```bash
# Create an event. type: scam_alert | remote_access | payment_pause | help | info
curl -X POST localhost:4545/api/events -H 'Content-Type: application/json' -d '{
  "type": "scam_alert",
  "title": "Fake \"virus detected\" pop-up",
  "explanation": "A web page pretended to be Apple and told her to call a number.",
  "risk": 0.92,
  "url": "http://apple-support-alert.help",
  "app": "Safari",
  "action": "Closed the tab",
  "screenshot": "data:image/jpeg;base64,..."
}'
# -> 201 {"ok":true,"id":"evt_...","ts":1761300000000}

curl 'localhost:4545/api/events?limit=20'         # newest first (optional &type=scam_alert)
```

`title` is required. `risk` is clamped to 0..1. `screenshot` must be a `data:image/(jpeg|png|webp|gif);base64,...` URI up to about 1.5 MB, and anything else is dropped without an error. An unknown `type` returns 400. The server keeps the newest 500 events.

### Approvals (payment pauses)

```bash
curl -X POST localhost:4545/api/approvals -H 'Content-Type: application/json' -d '{
  "title": "$500 in Target gift cards",
  "explanation": "Scammers ask for gift cards because they cannot be traced.",
  "amount": 500, "payee": "Target.com", "method": "gift card", "risk": 0.95,
  "screenshot": "data:image/jpeg;base64,..."
}'
# -> 201 {"ok":true,"id":"apr_...","status":"pending","eventId":"evt_..."}
# also creates a payment_pause feed event (with approvalId) and broadcasts both

curl localhost:4545/api/approvals/apr_xxx          # the Mac polls this every 2s
# -> {"id":"apr_xxx","status":"pending"}   or   {"id":..,"status":"denied","note":"..","decidedAt":1761300000000}
curl 'localhost:4545/api/approvals/apr_xxx?full=1' # full record
curl 'localhost:4545/api/approvals?status=pending' # list, newest first (status optional)

curl -X POST localhost:4545/api/approvals/apr_xxx/approve -H 'Content-Type: application/json' -d '{"note":"OK!"}'
curl -X POST localhost:4545/api/approvals/apr_xxx/deny    -H 'Content-Type: application/json' -d '{"note":"Scam, calling you"}'
# -> {"ok":true,"id":..,"status":"approved"|"denied","note":..,"decidedAt":..}; 409 if already decided; 404 if unknown
```

Optional approval fields: `currency` (default USD in the UI) and `action` (overrides the feed event's action text).

### Live stream (SSE)

```bash
curl -N localhost:4545/api/stream
```

- `event: event` with the full event JSON (new alert)
- `event: approval` with the full approval JSON (created or decided)
- `event: reload` after demo seed/reset, which tells the UI to refetch
- `: heartbeat` comment every 15 s, plus `retry: 3000`

### Summary, config, demo, health

```bash
curl localhost:4545/api/summary
# {"from","to","total","countsByType":{scam_alert,remote_access,payment_pause,help,info},
#  "scamsStopped","remoteAccessBlocked","payments":{"paused","approved","denied","pending"},
#  "moneyProtected","helpSessions","headline":"Quiet week. Scout stopped 2 scam attempts.",
#  "perDay":[{"date":"2026-10-18","label":"Sun","total":2,"counts":{...}} x7, oldest first]}

curl localhost:4545/api/config            # {"elderName":"Mom","familyName":"Sarah"}
curl -X POST localhost:4545/api/demo/seed # adds ~9 past events + 2 decided approvals across the last 7 days
curl -X POST localhost:4545/api/demo/reset
curl localhost:4545/healthz               # ok
```

## Frontend (`public/index.html`)

The page is a single file with inline CSS and JS, no CDN, and the system font stack. It follows the system light/dark setting.

- **Live**: feed cards with a type icon and color, a "High risk" tag (risk >= 0.7), the explanation, the app and URL, time-ago, a screenshot thumbnail that opens full screen on tap, and a pill showing what Scout did.
- **Approvals**: pending payments at the top, each with the amount, payee, method (gift card, wire and crypto are highlighted), a note field and big Deny / Approve buttons. Decided payments are listed below.
- **This week**: the headline, stat tiles, a stacked bar chart for each day, and a breakdown.
- **Live updates**: EventSource with automatic reconnect and a full resync after an outage. The header dot is green when connected and amber while reconnecting.
- **Alerts**: `scam_alert`, `remote_access` and `payment_pause` show a slide-down banner, play a WebAudio chime and call `navigator.vibrate`. The tab title shows an unread count, e.g. `(2) Scout · Mom`. Opens on the Approvals tab when something is pending. Deep links: `#live`, `#approvals`, `#week`.

## Decisions / notes

- **No auth.** This is a demo on a trusted LAN. Anyone who can reach the port can approve or deny. Put it behind a tunnel with auth (or add a shared token) before using it for real.
- **State.** Everything is kept in memory and written to `family/data/state.json` through an atomic tmp+rename, debounced to 100 ms. Limits: 500 events, 200 approvals (the oldest decided approval is dropped first).
- **"Scams stopped"** = `scam_alert` + `remote_access` events in the last 7 days. "Money kept safe" = the sum of numeric `amount` on denied approvals.
- **Headline tone.** "Quiet week." when scams + paused payments <= 5, otherwise "Busy week.", with "N payment(s) still waiting on you." added when relevant.
- **Approval IDs** are opaque strings (`apr_...`), not UUIDs. Deciding twice returns 409 with the existing status, so the Mac app can treat 409 as final.
- **Sound.** Browsers block audio until the user interacts with the page, so the chime is unlocked on the first tap. The speaker button toggles it, and the choice is remembered in localStorage.
- **SMS** goes to the family number only, and only for alert-worthy types (not `info`).


## CRS sender check

`POST /api/crs/check-sender` with `{"email": "notice@irs-gov-payments.co"}` runs CRS Fraud Finder (AtData) on a suspicious message's **sender** and returns:
- `verdict`: `high`, `medium`, `low` or `unknown`
- `score`: 0–100
- `firstSeen` and `newToday`
- `sentence`: plain-language text the buddy can say
- `source`: `crs` or `mock`

Credentials come from `CRS_USERNAME` / `CRS_PASSWORD` (env or `~/.config/scout/secrets.env`) and are never logged. Results are cached for 24 h per address. Without credentials, or when `CRS_MOCK=1` is set or CRS is unreachable, a mock answer marked `source: "mock"` is returned. `GET /api/crs/status` reports whether CRS is configured.
