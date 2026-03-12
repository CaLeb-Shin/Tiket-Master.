// Vercel Serverless Function — 모바일 티켓 OG 메타 태그
// 카카오톡/페이스북 등 크롤러에게 공연 포스터 + 제목을 보여줌
// 일반 사용자에게는 Flutter SPA(index.html)를 제공

const https = require('https');
const fs = require('fs');
const path = require('path');

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
  if (!isCrawler) {
    try {
      const indexPath = path.join(process.cwd(), 'melon_ticket_app', 'build', 'web', 'index.html');
      const html = fs.readFileSync(indexPath, 'utf8');
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      return res.send(html);
    } catch {
      // fallback: redirect
      return res.redirect(302, `/`);
    }
  }

  // 크롤러: 티켓 정보 조회 → OG 메타 태그 반환
  const token = req.query.token;
  let title = '멜론티켓 - 모바일 티켓';
  let description = 'AI 좌석 추천 · 360° 시야 보기 · 모바일 스마트 티켓';
  let imageUrl = 'https://melonticket-web-20260216.vercel.app/icons/Icon-512.png';
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

  const ogImageUrl = imageUrl
    ? `https://us-central1-melon-ticket-mvp-2026.cloudfunctions.net/ogImage?url=${encodeURIComponent(imageUrl)}`
    : imageUrl;

  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta property="og:type" content="website">
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="${escapeHtml(description)}">
  <meta property="og:image" content="${escapeHtml(ogImageUrl)}">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="1200">
  <meta property="og:url" content="${escapeHtml(pageUrl)}">
  <meta property="og:site_name" content="멜론티켓">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapeHtml(title)}">
  <meta name="twitter:description" content="${escapeHtml(description)}">
  <meta name="twitter:image" content="${escapeHtml(ogImageUrl)}">
  <title>${escapeHtml(title)}</title>
</head>
<body></body>
</html>`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=3600');
  return res.send(html);
};
