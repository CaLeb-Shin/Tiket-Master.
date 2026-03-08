// Vercel Edge Middleware — 카카오톡/SNS 크롤러에게 동적 OG 태그 제공

// 크롤러 User-Agent 패턴
const CRAWLER_UA =
  /kakaotalk|kakao|facebookexternalhit|Facebot|Twitterbot|TelegramBot|Slackbot|LinkedInBot|WhatsApp|Discordbot|Applebot|Googlebot|bingbot|DuckDuckBot|ia_archiver|Embedly|outbrain|pinterest|vkShare|W3C_Validator/i;

const CF_BASE = "https://us-central1-melon-ticket-mvp-2026.cloudfunctions.net";

export const config = {
  matcher: "/m/:path*",
};

export default async function middleware(request: Request): Promise<Response> {
  const ua = request.headers.get("user-agent") || "";

  // 일반 사용자 → Flutter 앱으로 패스스루
  if (!CRAWLER_UA.test(ua)) {
    return fetch(request);
  }

  // 크롤러 → 동적 OG 태그 HTML 반환
  const url = new URL(request.url);
  const token = url.pathname.replace("/m/", "");

  if (!token) {
    return fetch(request);
  }

  try {
    const metaRes = await fetch(
      `${CF_BASE}/getTicketOgMeta?token=${encodeURIComponent(token)}`,
      { headers: { Accept: "application/json" } }
    );

    if (!metaRes.ok) {
      return fetch(request);
    }

    const meta = await metaRes.json();

    // 날짜 포맷
    let dateStr = "";
    if (meta.startAt) {
      const ts = meta.startAt._seconds
        ? new Date(meta.startAt._seconds * 1000)
        : new Date(meta.startAt);
      if (!isNaN(ts.getTime())) {
        const days = ["일", "월", "화", "수", "목", "금", "토"];
        const y = ts.getFullYear();
        const m = String(ts.getMonth() + 1).padStart(2, "0");
        const d = String(ts.getDate()).padStart(2, "0");
        const day = days[ts.getDay()];
        const hh = String(ts.getHours()).padStart(2, "0");
        const mm = String(ts.getMinutes()).padStart(2, "0");
        dateStr = `${y}.${m}.${d} (${day}) ${hh}:${mm}`;
      }
    }

    const title = meta.title || "공연";
    const description =
      meta.description || [dateStr, meta.venueName].filter(Boolean).join(" | ");
    const imageUrl = meta.imageUrl || "";
    const imageAlt = meta.imageAlt || `${title} 포스터`;
    const pageUrl = request.url;
    const siteName = meta.siteName || "멜론티켓";

    const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="description" content="${esc(description)}">
  <meta name="robots" content="noindex, nofollow, noarchive">
  <meta property="og:type" content="website">
  <meta property="og:locale" content="ko_KR">
  <meta property="og:title" content="${esc(title)}">
  <meta property="og:description" content="${esc(description)}">
  <meta property="og:image" content="${esc(imageUrl)}">
  <meta property="og:image:alt" content="${esc(imageAlt)}">
  <meta property="og:url" content="${esc(pageUrl)}">
  <meta property="og:site_name" content="${esc(siteName)}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${esc(title)}">
  <meta name="twitter:description" content="${esc(description)}">
  <meta name="twitter:image" content="${esc(imageUrl)}">
  <meta name="twitter:image:alt" content="${esc(imageAlt)}">
  <link rel="canonical" href="${esc(pageUrl)}">
  <title>${esc(title)} - ${esc(siteName)}</title>
  <meta http-equiv="refresh" content="0;url=${esc(pageUrl)}">
</head>
<body>
  <p>${esc(title)}</p>
  <p>${esc(description)}</p>
</body>
</html>`;

    return new Response(html, {
      status: 200,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "public, max-age=300, s-maxage=300",
        "X-Robots-Tag": "noindex, nofollow, noarchive",
      },
    });
  } catch {
    return fetch(request);
  }
}

function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
