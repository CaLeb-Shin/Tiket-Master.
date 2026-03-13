// Vercel Serverless Function: /api/staff/scanner
// 크롤러 전용 OG 메타 반환 (vercel.json에서 UA 기반 라우팅)

module.exports = (req, res) => {
  const query = req.query || {};
  const invite = query.invite || '';
  const qs = invite ? `?invite=${encodeURIComponent(invite)}` : '';
  const fullUrl = `https://melonticket-web-20260216.vercel.app/staff/scanner${qs}`;

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
  res.status(200).send(html);
};
