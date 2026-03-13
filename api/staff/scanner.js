// Vercel Serverless Function: /api/staff/scanner
// 크롤러 → 스캐너 전용 OG 메타
// 일반 브라우저 → JS로 index.html 기반 Flutter SPA로 이동

module.exports = (req, res) => {
  const ua = (req.headers['user-agent'] || '');
  const isCrawler =
    /kakaotalk-scrap|facebookexternalhit|twitterbot|telegrambot|slackbot|linkedinbot|whatsapp|line-poker|discord|googlebot/i.test(ua);

  // 쿼리 파라미터 보존
  const qs = req.url && req.url.includes('?') ? req.url.substring(req.url.indexOf('?')) : '';
  const fullUrl = `https://melonticket-web-20260216.vercel.app/staff/scanner${qs}`;

  if (isCrawler) {
    const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta property="og:type" content="website">
  <meta property="og:title" content="멜론티켓 스캐너 초대">
  <meta property="og:description" content="이 링크를 눌러 스캐너에 접속하세요. 로그인 후 자동으로 기기가 승인됩니다.">
  <meta property="og:image" content="https://melonticket-web-20260216.vercel.app/icons/Icon-512.png">
  <meta property="og:url" content="${fullUrl}">
  <meta property="og:site_name" content="멜론티켓">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="멜론티켓 스캐너 초대">
  <meta name="twitter:description" content="이 링크를 눌러 스캐너에 접속하세요.">
  <title>멜론티켓 스캐너 초대</title>
</head>
<body></body>
</html>`;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-cache');
    return res.status(200).send(html);
  }

  // 일반 브라우저 → _skip=1 파라미터로 rewrite 건너뛰기
  // vercel.json에서 _skip=1이면 index.html로 직접 보냄
  const sep = qs ? '&' : '?';
  res.writeHead(302, { Location: `/staff/scanner${qs}${sep}_skip=1` });
  res.end();
};
