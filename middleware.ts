// Vercel Edge Middleware — 카카오톡/SNS 크롤러에게 동적 OG 태그 제공
// 일반 사용자는 Flutter SPA 그대로 제공 (fetch(request) → origin 정적 파일)

const CRAWLER_UA =
  /kakaotalk|kakao|facebookexternalhit|Facebot|Twitterbot|TelegramBot|Slackbot|LinkedInBot|WhatsApp|Discordbot|Googlebot|bingbot|bot|crawler|spider|preview/i;

const CF_BASE = "https://us-central1-melon-ticket-mvp-2026.cloudfunctions.net";

export const config = {
  matcher: "/m/:path*",
};

export default async function middleware(request: Request): Promise<Response> {
  const ua = request.headers.get("user-agent") || "";

  // 일반 사용자 → Flutter SPA 정적 파일로 패스스루 (origin fetch)
  if (!CRAWLER_UA.test(ua)) {
    return fetch(request);
  }

  // 크롤러 → CF에서 OG HTML 가져오기
  const url = new URL(request.url);
  const token = url.pathname.replace("/m/", "").split("/")[0];

  if (!token) {
    return fetch(request);
  }

  try {
    const res = await fetch(
      `${CF_BASE}/getTicketOgMeta?token=${encodeURIComponent(token)}&format=html`
    );
    const ct = res.headers.get("content-type") || "";
    if (ct.includes("text/html")) {
      return new Response(await res.text(), {
        status: 200,
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "public, max-age=300, s-maxage=300",
        },
      });
    }
  } catch {}

  return fetch(request);
}
