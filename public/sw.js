const CACHE = 'floaterm-v1';
const STATIC = [
  '/',
  '/css/style.css',
  '/js/main.js',
  '/js/canvas.js',
  '/js/box.js',
  '/js/input.js',
  '/js/terminal-manager.js',
  '/icon.svg',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(STATIC)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);

  // Skip API calls and WebSocket upgrades — always network
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/ws/')) return;

  // Static assets: cache-first, fall back to network
  e.respondWith(
    caches.match(e.request).then(cached => cached || fetch(e.request).then(res => {
      const clone = res.clone();
      caches.open(CACHE).then(c => c.put(e.request, clone));
      return res;
    }))
  );
});
