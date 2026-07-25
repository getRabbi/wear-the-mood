// Phase 5 §E — constant-arrival-rate API load gate, run from a US GitHub runner.
//
// One iteration performs EXACTLY ONE weighted API request, so `iterations`,
// `http_reqs` and the arrival rate are the same number and the achieved RPS is
// unambiguous. constant-arrival-rate (not ramping) holds the target open-model
// rate regardless of response latency; if the VU pool cannot keep up, k6 records
// dropped_iterations, which the gate requires to be 0.
//
// Writes are restricted to endpoints that do NOT create tryon_jobs or ai_jobs:
// staging shares the production database with the still-live DigitalOcean worker,
// which would claim any queued job and call the PAID providers (§14.1).

import http from 'k6/http';
import { check } from 'k6';
import { SharedArray } from 'k6/data';

const BASE = __ENV.BASE;
const RATE = parseInt(__ENV.RATE || '120');
const VUS = parseInt(__ENV.VUS || '900');
const DURATION = __ENV.DURATION || '30m';

const users = new SharedArray('users', () => JSON.parse(open('./users.json')));

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: VUS,
      maxVUs: VUS,
      gracefulStop: '30s',
    },
  },
  thresholds: {
    'http_req_duration{kind:read}': ['p(95)<600'],
    'http_req_duration{kind:write}': ['p(95)<900'],
    http_req_failed: ['rate<0.005'],
    dropped_iterations: ['count==0'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const u = users[Math.floor(Math.random() * users.length)];
  const auth = { Authorization: `Bearer ${u.token}` };
  const json = { ...auth, 'Content-Type': 'application/json' };
  const r = Math.random() * 100;

  // Exactly one request per iteration.
  if (r < 25) {
    http.get(`${BASE}/v1/wardrobe`, { headers: auth, tags: { kind: 'read', ep: 'wardrobe' } });
  } else if (r < 45) {
    const lim = [10, 20, 30][Math.floor(Math.random() * 3)];
    http.get(`${BASE}/v1/news?limit=${lim}`, { headers: auth, tags: { kind: 'read', ep: 'news' } });
  } else if (r < 57) {
    http.get(`${BASE}/v1/me`, { headers: auth, tags: { kind: 'read', ep: 'me' } });
  } else if (r < 67) {
    http.get(`${BASE}/v1/credits`, { headers: auth, tags: { kind: 'read', ep: 'credits' } });
  } else if (r < 75) {
    http.get(`${BASE}/v1/social/feed?limit=20`, { headers: auth, tags: { kind: 'read', ep: 'feed' } });
  } else if (r < 78) {
    http.get(`${BASE}/v1/notifications`, { headers: auth, tags: { kind: 'read', ep: 'notifications' } });
  } else if (r < 80) {
    http.get(`${BASE}/v1/flags`, { headers: auth, tags: { kind: 'read', ep: 'flags' } });
  } else if (r < 90) {
    http.patch(`${BASE}/v1/profile`, JSON.stringify({ display_name: `wtm-p5-load ${__VU}` }),
      { headers: json, tags: { kind: 'write', ep: 'profile' } });
  } else if (r < 98) {
    const item = u.items[Math.floor(Math.random() * u.items.length)];
    http.patch(`${BASE}/v1/wardrobe/${item}`, JSON.stringify({ title: `wtm-p5-load ${__ITER}` }),
      { headers: json, tags: { kind: 'write', ep: 'wardrobe_patch' } });
  } else {
    const ids = u.items.slice(0, 3);
    http.post(`${BASE}/v1/outfits`,
      JSON.stringify({ name: `wtm-p5-load outfit ${__VU}-${__ITER}`, item_ids: ids }),
      { headers: json, tags: { kind: 'write', ep: 'outfit_create' } });
  }
}
