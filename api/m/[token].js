// Vercel Serverless Function — 모바일 티켓 OG 메타 태그
// 카카오톡/페이스북 등 크롤러에게 공연 포스터 + 제목을 보여줌
// 일반 사용자에게는 Flutter SPA(index.html)를 제공

const https = require('https');

const FIRESTORE_BASE = 'https://firestore.googleapis.com/v1/projects/melon-ticket-mvp-2026/databases/(default)/documents';

function firestoreGet(docPath) {
  return new Promise((resolve, reject) => {
    const url = `${FIRESTORE_BASE}/${docPath}`;
    const u = new URL(url);
    https.get({ hostname: u.hostname, path: u.pathname, headers: { 'Accept': 'application/json' } }, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try { resolve(JSON.parse(d)); } catch { resolve(null); }
      });
    }).on('error', reject);
  });
}

function firestoreQuery(collectionId, fieldPath, op, value) {
  return new Promise((resolve, reject) => {
    const url = `${FIRESTORE_BASE}:runQuery`;
    const u = new URL(url);
    const body = JSON.stringify({
      structuredQuery: {
        from: [{ collectionId }],
        where: { fieldFilter: { field: { fieldPath }, op, value: { stringValue: value } } },
        limit: 1,
      },
    });
    const opts = {
      hostname: u.hostname,
      path: u.pathname,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    };
    const req = https.request(opts, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try { resolve(JSON.parse(d)); } catch { resolve(null); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function getFieldValue(fields, key) {
  if (!fields || !fields[key]) return null;
  const f = fields[key];
  return f.stringValue || f.integerValue || f.booleanValue || null;
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

module.exports = async (req, res) => {
  const ua = req.headers['user-agent'] || '';
  const isCrawler = /kakaotalk|facebookexternalhit|Twitterbot|Slackbot|LinkedInBot|Googlebot|bot|crawler|spider|preview/i.test(ua);

  // 일반 사용자: Flutter SPA 제공
  // Vercel 서버리스에서는 빌드 출력에 직접 접근 불가 → 자체 CDN에서 index.html fetch
  if (!isCrawler) {
    try {
      const origin = `https://${req.headers.host}`;
      const indexHtml = await new Promise((resolve, reject) => {
        https.get(`${origin}/index.html`, (resp) => {
          let d = '';
          resp.on('data', c => d += c);
          resp.on('end', () => resolve(d));
        }).on('error', reject);
      });
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.setHeader('Cache-Control', 'public, max-age=0, must-revalidate');
      return res.send(indexHtml);
    } catch {
      // fallback: 302 redirect — URL 유지를 위해 같은 경로로 direct 파라미터 추가
      return res.redirect(302, `/`);
    }
  }

  // 크롤러: 티켓 정보 조회 → OG 메타 태그 반환
  const token = req.query.token;
  let title = '멜팅 - No.1 모바일티켓';
  let description = 'AI 좌석추천, 360' 좌석예매, 스마트 티켓';
  let imageUrl = 'https://melonticket-web-20260216.vercel.app/icons/melon-og.png';
  let pageUrl = `https://melonticket-web-20260216.vercel.app/m/${token}`;

  try {
    // accessToken으로 티켓 조회
    const ticketResult = await firestoreQuery('mobileTickets', 'accessToken', 'EQUAL', token);
    if (ticketResult && Array.isArray(ticketResult) && ticketResult[0]?.document) {
      const ticketFields = ticketResult[0].document.fields;
      const eventId = getFieldValue(ticketFields, 'eventId');
      const seatGrade = getFieldValue(ticketFields, 'seatGrade');
      const buyerName = getFieldValue(ticketFields, 'buyerName');

      if (eventId) {
        const eventDoc = await firestoreGet(`events/${eventId}`);
        if (eventDoc?.fields) {
          const ef = eventDoc.fields;
          const eventTitle = getFieldValue(ef, 'title') || '공연';
          const eventImage = getFieldValue(ef, 'imageUrl');
          const venueName = getFieldValue(ef, 'venueName') || '';

          title = `🎫 ${eventTitle}`;
          description = `${seatGrade ? seatGrade + '석 · ' : ''}${venueName}`;
          if (eventImage) imageUrl = eventImage;
        }
      }
    }
  } catch {
    // 조회 실패 시 기본값 사용
  }

  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta property="og:type" content="website">
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="${escapeHtml(description)}">
  <meta property="og:image" content="${escapeHtml(imageUrl)}">
  <meta property="og:url" content="${escapeHtml(pageUrl)}">
  <meta property="og:site_name" content="멜론티켓">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapeHtml(title)}">
  <meta name="twitter:description" content="${escapeHtml(description)}">
  <meta name="twitter:image" content="${escapeHtml(imageUrl)}">
  <title>${escapeHtml(title)}</title>
</head>
<body></body>
</html>`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=3600');
  return res.send(html);
};
