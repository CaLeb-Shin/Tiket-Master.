// 모바일티켓 전용 서비스 워커
// 한 번 열면 오프라인에서도 QR + 티켓 정보 표시 가능
const CACHE_NAME = 'melon-ticket-v1';
const TICKET_DATA_CACHE = 'melon-ticket-data-v1';

// 앱 셸 캐시 (정적 리소스)
const APP_SHELL = [
  '/',
  '/index.html',
  '/manifest.json',
  '/favicon.png',
  '/flutter_bootstrap.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(
        names
          .filter((name) => name !== CACHE_NAME && name !== TICKET_DATA_CACHE)
          .map((name) => caches.delete(name))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Cloud Functions API 호출 캐시 (getMobileTicketByToken 등)
  if (url.pathname.includes('cloudfunctions.net') || url.hostname.includes('cloudfunctions.net')) {
    event.respondWith(networkFirstWithCache(event.request, TICKET_DATA_CACHE));
    return;
  }

  // Firebase Storage 이미지 캐시 (포스터 등)
  if (url.hostname.includes('firebasestorage.googleapis.com') ||
      url.hostname.includes('storage.googleapis.com')) {
    event.respondWith(cacheFirstWithNetwork(event.request, CACHE_NAME));
    return;
  }

  // 앱 셸 (HTML, JS, CSS) — 네트워크 우선, 실패 시 캐시
  if (event.request.mode === 'navigate') {
    event.respondWith(networkFirstWithCache(event.request, CACHE_NAME));
    return;
  }

  // 기타 정적 리소스 — 캐시 우선
  event.respondWith(cacheFirstWithNetwork(event.request, CACHE_NAME));
});

// 네트워크 우선 → 실패 시 캐시 (API 호출, 페이지 탐색)
async function networkFirstWithCache(request, cacheName) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(cacheName);
      cache.put(request, response.clone());
    }
    return response;
  } catch (err) {
    const cached = await caches.match(request);
    if (cached) return cached;
    // 페이지 탐색 실패 시 캐시된 index.html 반환 (SPA)
    if (request.mode === 'navigate') {
      const cachedIndex = await caches.match('/index.html');
      if (cachedIndex) return cachedIndex;
    }
    return new Response('오프라인 상태입니다', { status: 503, statusText: 'Offline' });
  }
}

// 캐시 우선 → 없으면 네트워크 (이미지, 정적 리소스)
async function cacheFirstWithNetwork(request, cacheName) {
  const cached = await caches.match(request);
  if (cached) return cached;
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(cacheName);
      cache.put(request, response.clone());
    }
    return response;
  } catch (err) {
    return new Response('', { status: 503 });
  }
}

// 메시지 핸들러 — 수동 캐시 삭제
self.addEventListener('message', (event) => {
  if (event.data === 'clearCache') {
    caches.keys().then((names) => Promise.all(names.map((n) => caches.delete(n))));
  }
});
