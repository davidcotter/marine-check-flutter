// DipReport Service Worker
// Strategy: cache assets (fonts, canvaskit, icons) but NEVER cache entry points.
// Entry points are always fetched from network so deploys take effect immediately.

const CACHE = 'dipreport-v1';

const NEVER_CACHE = [
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/flutter_service_worker.js',
  '/flutter.js',
  '/main.dart.js',
  '/manifest.json',
  '/version.json',
];

const isNeverCache = (url) => {
  const path = new URL(url).pathname;
  // Also never cache flutter_service_worker with query params
  if (path.includes('flutter_service_worker')) return true;
  return NEVER_CACHE.includes(path);
};

self.addEventListener('install', (e) => {
  // Do NOT call skipWaiting() — that causes controllerchange → reload loops.
  // The new SW will wait until all tabs are closed before activating.
});

self.addEventListener('activate', (e) => {
  // Clean up old caches, but do NOT call clients.claim().
  // clients.claim() triggers controllerchange on existing pages → reload loop.
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;

  const url = e.request.url;

  // Never cache entry points — always go to network
  if (isNeverCache(url)) {
    e.respondWith(fetch(e.request));
    return;
  }

  // For everything else: cache-first with network fallback
  e.respondWith(
    caches.open(CACHE).then(cache =>
      cache.match(e.request).then(cached => {
        if (cached) return cached;
        return fetch(e.request).then(response => {
          if (response && response.ok) {
            cache.put(e.request, response.clone());
          }
          return response;
        });
      })
    )
  );
});

// Push notifications
self.addEventListener('push', (event) => {
  let data = { title: 'DipReport', body: 'New update available' };
  try { data = event.data.json(); } catch (_) {}
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      data: data.url || '/',
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification.data || '/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window' }).then(clients => {
      for (const client of clients) {
        if (client.url === url && 'focus' in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    })
  );
});
