/* Cloudflare Worker: serve a staged Cart Slop GP Web release from R2.
 *
 * This is the optional R2 + CDN path (the primary path is Cloudflare Pages,
 * which needs no Worker). It exists because a plain R2 bucket cannot do the two
 * things the Godot client needs from a production host:
 *
 *   1. Content-Encoding negotiation - the stager writes .gz and .br siblings so
 *      nobody ever gzip-compresses 120 MB per request; this Worker picks the
 *      sibling with `Accept-Encoding` and returns one compressed object.
 *   2. Version-pointer caching rules - the root redirect and version.json are
 *      no-store, while /game/<version>/<build-id>/* is immutable and can be
 *      cached at every edge for a year.
 *
 * Object layout (produced by scripts/stage_release.ps1 -Precompress and
 * uploaded by scripts/upload_r2.ps1):
 *   version.json                      release stamp (pointer, no-store)
 *   release.json                      hosting metadata (pointer, no-store)
 *   game/<version>/<build>/index.*    payload, immutable
 *   game/<version>/<build>/index.*.br gzip/brotli siblings, chosen by encoding
 *
 * Bindings: WEB_ASSETS (R2 bucket), THREADED ("1" only for a threaded export,
 * see the COOP/COEP note in README.md).
 */

const IMMUTABLE = 'public, max-age=31536000, immutable';
const NO_STORE = 'no-store, must-revalidate';
const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'SAMEORIGIN',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
};

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
  '.json': 'application/json',
};

let releaseCache = { at: 0, value: null };
const RELEASE_TTL_MS = 60_000;

function mimeFor(key) {
  const dot = key.lastIndexOf('.');
  return (dot >= 0 && MIME_TYPES[key.slice(dot).toLowerCase()]) || 'application/octet-stream';
}

function baseHeaders(extra) {
  return { ...SECURITY_HEADERS, ...extra };
}

function isolationHeaders(env) {
  if (String(env.THREADED || '0') !== '1') { return {}; }
  return {
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'same-origin',
  };
}

async function readRelease(env) {
  const now = Date.now();
  if (releaseCache.value && now - releaseCache.at < RELEASE_TTL_MS) {
    return releaseCache.value;
  }
  const object = await env.WEB_ASSETS.get('release.json');
  if (!object) { return null; }
  try {
    const value = await object.json();
    releaseCache = { at: now, value };
    return value;
  } catch {
    return null;
  }
}

async function serveObject(env, key, { cacheControl, request }) {
  const accept = (request.headers.get('Accept-Encoding') || '').toLowerCase();
  let chosenKey = key;
  let encoding = '';
  if (accept.includes('br')) {
    const probe = await env.WEB_ASSETS.head(key + '.br');
    if (probe) { chosenKey = key + '.br'; encoding = 'br'; }
  }
  if (!encoding && accept.includes('gzip')) {
    const probe = await env.WEB_ASSETS.head(key + '.gz');
    if (probe) { chosenKey = key + '.gz'; encoding = 'gzip'; }
  }
  const object = await env.WEB_ASSETS.get(chosenKey);
  if (!object) { return null; }
  const headers = baseHeaders({
    'Cache-Control': cacheControl,
    'Content-Type': mimeFor(key),
    'Vary': 'Accept-Encoding',
    'X-Cartslop-Build': key.split('/')[2] || '',
  });
  if (encoding) { headers['Content-Encoding'] = encoding; }
  if (object.size != null) { headers['Content-Length'] = String(object.size); }
  Object.assign(headers, isolationHeaders(env));
  if (request.method === 'HEAD') {
    if (object.body) { object.body.cancel(); }
    return new Response(null, { status: 200, headers });
  }
  return new Response(object.body, { status: 200, headers });
}

function textResponse(body, status, extra) {
  return new Response(body, {
    status,
    headers: baseHeaders({ 'Content-Type': 'text/plain; charset=utf-8', ...extra }),
  });
}

export default {
  async fetch(request, env) {
    const method = request.method.toUpperCase();
    if (method !== 'GET' && method !== 'HEAD') {
      return textResponse('Method Not Allowed', 405, { Allow: 'GET, HEAD' });
    }
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === '/' || path === '/index.html' || path === '/latest' || path === '/latest/') {
      const release = await readRelease(env);
      if (!release || !release.entry) {
        return textResponse('Cart Slop GP: no release staged yet (release.json missing).', 503,
          { 'Cache-Control': NO_STORE });
      }
      return new Response(null, {
        status: 302,
        headers: baseHeaders({ Location: release.entry, 'Cache-Control': NO_STORE }),
      });
    }

    if (path === '/version.json') {
      const object = await env.WEB_ASSETS.get('version.json');
      if (!object) { return textResponse('version.json missing', 503, { 'Cache-Control': NO_STORE }); }
      return new Response(method === 'HEAD' ? null : object.body, {
        status: 200,
        headers: baseHeaders({
          'Content-Type': 'application/json',
          'Cache-Control': NO_STORE,
          'Access-Control-Allow-Origin': '*',
        }),
      });
    }

    if (path === '/release.json') {
      const object = await env.WEB_ASSETS.get('release.json');
      if (!object) { return textResponse('release.json missing', 503, { 'Cache-Control': NO_STORE }); }
      return new Response(method === 'HEAD' ? null : object.body, {
        status: 200,
        headers: baseHeaders({ 'Content-Type': 'application/json', 'Cache-Control': NO_STORE }),
      });
    }

    if (!path.startsWith('/game/')) {
      return textResponse('Not Found', 404, { 'Cache-Control': NO_STORE });
    }

    const key = path.slice(1);
    const isEntryHtml = key.endsWith('/index.html');
    const cacheControl = isEntryHtml ? NO_STORE : IMMUTABLE;
    const response = await serveObject(env, key, { cacheControl, request });
    if (response) { return response; }
    return textResponse('Not Found', 404, { 'Cache-Control': NO_STORE });
  },
};
