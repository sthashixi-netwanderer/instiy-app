/* Instiy Control Room — service worker.
 * App-shell caching for the admin PWA. Static same-origin assets are served
 * stale-while-revalidate; navigations fall back to the cached index.html so
 * client-side routes and relaunches work offline. API traffic (Supabase and
 * any other cross-origin request except Google Fonts) is never cached. */

const STATIC_CACHE = 'instiy-admin-static-v1';
const FONT_CACHE = 'instiy-admin-fonts-v1';

const CORE_ASSETS = [
  '/',
  '/index.html',
  '/manifest.webmanifest',
  '/favicon.svg',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/icons/maskable-192.png',
  '/icons/maskable-512.png',
  '/icons/apple-touch-icon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(STATIC_CACHE)
      .then((cache) => cache.addAll(CORE_ASSETS))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter(
              (key) =>
                key.startsWith('instiy-admin-') &&
                key !== STATIC_CACHE &&
                key !== FONT_CACHE,
            )
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

const isNavigation = (request) =>
  request.mode === 'navigate' ||
  (request.method === 'GET' &&
    request.headers.get('accept')?.includes('text/html'));

async function handleNavigation(request) {
  try {
    const fresh = await fetch(request);
    const cache = await caches.open(STATIC_CACHE);
    cache.put('/index.html', fresh.clone());
    return fresh;
  } catch (_) {
    const cached = await caches.match('/index.html');
    if (cached) return cached;
    return Response.error();
  }
}

async function handleSameOriginAsset(request) {
  const cached = await caches.match(request);
  const network = fetch(request)
    .then((response) => {
      if (response && response.status === 200) {
        const copy = response.clone();
        caches.open(STATIC_CACHE).then((cache) => cache.put(request, copy));
      }
      return response;
    })
    .catch(() => cached);
  return cached || network;
}

async function handleFont(request) {
  const cached = await caches.match(request);
  if (cached) return cached;
  try {
    const response = await fetch(request);
    if (response && response.status === 200) {
      const copy = response.clone();
      caches.open(FONT_CACHE).then((cache) => cache.put(request, copy));
    }
    return response;
  } catch (_) {
    return Response.error();
  }
}

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  if (isNavigation(request)) {
    event.respondWith(handleNavigation(request));
    return;
  }

  if (url.origin === self.location.origin) {
    event.respondWith(handleSameOriginAsset(request));
    return;
  }

  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    event.respondWith(handleFont(request));
  }
  // All other cross-origin traffic (Supabase API/Realtime/Storage) bypasses
  // the service worker cache so live data is never served stale.
});
