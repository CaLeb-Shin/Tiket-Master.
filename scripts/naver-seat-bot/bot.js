#!/usr/bin/env node
/**
 * 네이버 좌석배정 전용 봇
 *
 * 기존 텔레그램 봇(oprncllclcl)과 완전히 분리된 봇.
 * 네이버 커머스 API로 주문 조회 → 텔레그램 승인 → Firebase 좌석 자동배정.
 *
 * 흐름:
 *   1) 네이버 커머스 API로 신규 주문 감지 (2분 간격)
 *   2) 텔레그램으로 승인 요청 ([승인] [거부] 인라인 버튼)
 *   3) 승인 시 → Firebase createNaverOrderHttp 호출
 *      → 등급별 좌석 자동배정 + 모바일 티켓 생성
 *   4) 결과 텔레그램 알림 (좌석 + 티켓 URL)
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

// ============================================================
// 설정
// ============================================================
const CONFIG = {
  // 텔레그램 — BotFather에서 새 봇 생성 후 토큰 입력
  telegramBotToken: process.env.NAVER_SEAT_BOT_TOKEN || 'YOUR_BOT_TOKEN_HERE',
  telegramChatId: process.env.NAVER_SEAT_CHAT_ID || '7718215110',

  // 네이버 커머스 API
  naver: {
    clientId: process.env.NAVER_CLIENT_ID || '',
    clientSecret: process.env.NAVER_CLIENT_SECRET || '',
    // 네이버 커머스 API 토큰 (OAuth)
    tokenUrl: 'https://api.commerce.naver.com/external/v1/oauth2/token',
    ordersUrl: 'https://api.commerce.naver.com/external/v1/pay-order/seller/orders',
  },

  // 네이버 스마트스토어 크롤링 대체 (API 없을 때)
  smartstore: {
    // 기존 봇의 쿠키/상태 공유 (읽기 전용)
    stateFile: process.env.SMARTSTORE_STATE ||
      path.join(__dirname, '../../oprncllclcl/smartstore-state.json'),
  },

  // 멜론티켓 Firebase
  firebase: {
    cfBaseUrl: 'https://us-central1-melon-ticket-mvp-2026.cloudfunctions.net',
    botApiKey: 'melon-bot-secret-2026',
    // 자동 감지: listEventsHttp에서 naverOnly=true 이벤트만 가져옴
    // 수동 오버라이드: perfKey → eventId 직접 매핑
    eventMap: {},
    // Firebase에서 가져온 naverOnly 이벤트 캐시
    _naverOnlyEvents: [],
  },

  // 주기
  checkInterval: 2 * 60 * 1000, // 2분

  // 상태 파일
  stateDir: path.join(__dirname, 'state'),
  processedFile: path.join(__dirname, 'state', 'processed-orders.json'),
  pendingFile: path.join(__dirname, 'state', 'pending-orders.json'),
};

// 상태 디렉토리 생성
if (!fs.existsSync(CONFIG.stateDir)) {
  fs.mkdirSync(CONFIG.stateDir, { recursive: true });
}

// ============================================================
// 유틸리티
// ============================================================
function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return filePath.endsWith('pending-orders.json') ? {} : [];
  }
}

function writeJson(filePath, data) {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
}

function log(msg) {
  const ts = new Date().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' });
  console.log(`[${ts}] ${msg}`);
}

// ============================================================
// 텔레그램 API
// ============================================================
let lastUpdateId = 0;

function telegramRequest(method, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const options = {
      hostname: 'api.telegram.org',
      path: `/bot${CONFIG.telegramBotToken}/${method}`,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) },
    };
    const req = https.request(options, (res) => {
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => {
        try {
          const json = JSON.parse(buf);
          resolve(json.result || json);
        } catch {
          resolve(buf);
        }
      });
    });
    req.on('error', reject);
    req.setTimeout(30000, () => { req.destroy(); reject(new Error('timeout')); });
    req.write(data);
    req.end();
  });
}

function sendMessage(text, replyMarkup = null) {
  const body = { chat_id: CONFIG.telegramChatId, text, parse_mode: 'HTML' };
  if (replyMarkup) body.reply_markup = replyMarkup;
  return telegramRequest('sendMessage', body);
}

function answerCallbackQuery(id, text) {
  return telegramRequest('answerCallbackQuery', { callback_query_id: id, text });
}

async function pollUpdates() {
  try {
    const updates = await telegramRequest('getUpdates', {
      offset: lastUpdateId + 1,
      timeout: 10,
      allowed_updates: ['message', 'callback_query'],
    });
    if (!Array.isArray(updates)) return;
    for (const u of updates) {
      lastUpdateId = Math.max(lastUpdateId, u.update_id);
      if (u.callback_query) await handleCallbackQuery(u.callback_query);
      if (u.message) await handleMessage(u.message);
    }
  } catch (err) {
    log(`⚠️ 텔레그램 폴링 오류: ${err.message}`);
  }
}

// ============================================================
// Firebase Cloud Function 호출
// ============================================================
function callFirebaseCF(functionName, data) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(data);
    const url = new URL(`${CONFIG.firebase.cfBaseUrl}/${functionName}`);
    const options = {
      hostname: url.hostname,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
        Authorization: `Bearer ${CONFIG.firebase.botApiKey}`,
      },
    };
    const req = https.request(options, (res) => {
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => {
        try {
          const json = JSON.parse(buf);
          if (res.statusCode >= 400) reject(new Error(json.error || `HTTP ${res.statusCode}`));
          else resolve(json);
        } catch {
          reject(new Error(`CF 응답 파싱 실패: ${buf.substring(0, 200)}`));
        }
      });
    });
    req.on('error', reject);
    req.setTimeout(60000, () => { req.destroy(); reject(new Error('CF timeout')); });
    req.write(body);
    req.end();
  });
}

// ============================================================
// 네이버 상품명 파싱
// ============================================================
function parseProductInfo(productName) {
  // "[대구] MelON 디즈니 + 지브리 오케스트라 콘서트, S석"
  const regionMatch = productName.match(/^\[([^\]]+)\]/);
  const region = regionMatch ? regionMatch[1] : '기타';

  const seatMatch = productName.match(/,\s*(\S+)석\s*$/);
  const seatGrade = seatMatch ? seatMatch[1] : 'S';

  const isDisney = productName.includes('디즈니');
  const type = isDisney ? '디즈니' : '지브리';
  const perfKey = `${region}_${type}`;

  return { region, seatGrade, perfKey, productName };
}

// ============================================================
// 텔레그램 승인 요청
// ============================================================
const pendingOrders = readJson(CONFIG.pendingFile);

function savePending() {
  writeJson(CONFIG.pendingFile, pendingOrders);
}

async function requestApproval(order) {
  const info = parseProductInfo(order.productName || order.product || '');
  const eventId = CONFIG.firebase.eventMap[info.perfKey];

  const msg =
    `📦 <b>새 주문 — 좌석배정 대기</b>\n\n` +
    `🎫 공연: ${order.productName || order.product}\n` +
    `👤 구매자: ${order.buyerName}\n` +
    `📱 연락처: ${order.phone || '-'}\n` +
    `🎟 등급: <b>${info.seatGrade}석</b> × ${order.qty || 1}매\n` +
    `📋 주문번호: <code>${order.orderId}</code>\n` +
    (eventId ? `\n✅ Firebase 이벤트 매핑됨` : `\n⚠️ eventMap 미설정 (${info.perfKey})`);

  const replyMarkup = {
    inline_keyboard: [[
      { text: '✅ 승인 (좌석배정)', callback_data: `seat_approve_${order.orderId}` },
      { text: '❌ 거부', callback_data: `seat_reject_${order.orderId}` },
    ]],
  };

  await sendMessage(msg, replyMarkup);
  pendingOrders[order.orderId] = { ...order, seatGrade: info.seatGrade, perfKey: info.perfKey };
  savePending();
}

// ============================================================
// 승인 처리 → Firebase 좌석배정
// ============================================================
async function approveOrder(orderId) {
  const order = pendingOrders[orderId];
  if (!order) {
    await sendMessage(`⚠️ 주문 ${orderId} 를 찾을 수 없습니다.`);
    return;
  }

  const info = parseProductInfo(order.productName || order.product || '');
  const eventId = findEventForOrder(order.productName || order.product || '');

  if (!eventId) {
    await sendMessage(
      `❌ <b>매칭 이벤트 없음!</b>\n\n` +
      `상품명: ${order.productName || order.product}\n` +
      `perfKey: <code>${info.perfKey}</code>\n\n` +
      `어드민에서 "네이버 전용" 이벤트를 만들거나,\nbot.js eventMap에 수동 추가하세요.`
    );
    return;
  }

  await sendMessage(`⏳ <b>${order.buyerName}</b> 좌석 배정 중...`);

  try {
    const result = await callFirebaseCF('createNaverOrderHttp', {
      eventId,
      naverOrderId: order.orderId,
      buyerName: order.buyerName,
      buyerPhone: order.phone || '',
      productName: order.productName || order.product || '',
      seatGrade: info.seatGrade,
      quantity: order.qty || 1,
      orderDate: order.orderDate || new Date().toISOString(),
      memo: '네이버 좌석봇 자동배정',
    });

    // 성공
    const tickets = result.tickets || [];
    const ticketInfo = tickets.map((t, i) => {
      const seat = t.seatInfo || '';
      return `  #${i + 1} ${seat} → ${t.url}`;
    }).join('\n');

    await sendMessage(
      `✅ <b>좌석 배정 완료!</b>\n\n` +
      `👤 ${order.buyerName}\n` +
      `🎟 ${info.seatGrade}석 × ${order.qty || 1}매\n\n` +
      `📱 티켓:\n${ticketInfo || '(URL 생성됨)'}` +
      (tickets.length > 0 ? `\n\n🔗 URL:\n${tickets.map(t => t.url).join('\n')}` : '')
    );

    // 처리 완료
    const processed = readJson(CONFIG.processedFile);
    processed.push(orderId);
    writeJson(CONFIG.processedFile, processed);
    delete pendingOrders[orderId];
    savePending();

  } catch (err) {
    await sendMessage(`❌ <b>좌석 배정 실패</b>\n\n오류: ${err.message}\n\n다시 승인하려면 "대기" 명령 입력`);
  }
}

// ============================================================
// 콜백 쿼리 (승인/거부)
// ============================================================
async function handleCallbackQuery(cq) {
  const { data, id: queryId } = cq;

  if (data.startsWith('seat_approve_')) {
    const orderId = data.replace('seat_approve_', '');
    await answerCallbackQuery(queryId, '좌석 배정 시작...');
    await approveOrder(orderId);
  } else if (data.startsWith('seat_reject_')) {
    const orderId = data.replace('seat_reject_', '');
    await answerCallbackQuery(queryId, '보류 처리');
    delete pendingOrders[orderId];
    savePending();
    await sendMessage(`⏸ 주문 ${orderId} 보류 (다음 체크 때 다시 알림)`);
  }
}

// ============================================================
// 메시지 처리 (명령어)
// ============================================================
async function handleMessage(msg) {
  const chatId = String(msg.chat.id);
  if (chatId !== CONFIG.telegramChatId) return;

  const text = (msg.text || '').trim();

  if (text === '/start' || text === '도움말') {
    await sendMessage(
      `🎫 <b>네이버 좌석배정 봇</b>\n\n` +
      `📋 명령어:\n` +
      `• <b>대기</b> — 승인 대기 중인 주문 목록\n` +
      `• <b>상태</b> — 봇 상태 확인\n` +
      `• <b>이벤트</b> — 등록된 eventMap 확인\n` +
      `• <b>도움말</b> — 이 메시지`
    );
  } else if (text === '대기') {
    const keys = Object.keys(pendingOrders);
    if (keys.length === 0) {
      await sendMessage('✅ 승인 대기 중인 주문이 없습니다.');
    } else {
      let msg = `⏳ <b>승인 대기 (${keys.length}건)</b>\n`;
      for (const id of keys) {
        const o = pendingOrders[id];
        msg += `\n• ${o.buyerName} — ${o.productName || o.product} (${id})`;
      }
      await sendMessage(msg);
      // 다시 승인 버튼 보내기
      for (const id of keys) {
        const o = pendingOrders[id];
        await requestApproval({ ...o, orderId: id });
      }
    }
  } else if (text === '상태') {
    const processed = readJson(CONFIG.processedFile);
    const pending = Object.keys(pendingOrders);
    await sendMessage(
      `📊 <b>봇 상태</b>\n\n` +
      `✅ 처리 완료: ${processed.length}건\n` +
      `⏳ 승인 대기: ${pending.length}건\n` +
      `🔄 체크 주기: ${CONFIG.checkInterval / 1000}초`
    );
  } else if (text === '이벤트') {
    const entries = Object.entries(CONFIG.firebase.eventMap);
    if (entries.length === 0) {
      await sendMessage('⚠️ eventMap이 비어있습니다.\nbot.js에서 설정해주세요.');
    } else {
      let msg = `🎯 <b>이벤트 매핑</b>\n`;
      for (const [key, id] of entries) {
        msg += `\n• ${key} → <code>${id}</code>`;
      }
      await sendMessage(msg);
    }
  }
}

// ============================================================
// 네이버 주문 감지 (커머스 API 또는 수동 입력)
// ============================================================

// 방법 1: 네이버 커머스 API (clientId/clientSecret 필요)
let naverAccessToken = null;
let naverTokenExpiry = 0;

async function getNaverToken() {
  if (naverAccessToken && Date.now() < naverTokenExpiry) return naverAccessToken;

  if (!CONFIG.naver.clientId || !CONFIG.naver.clientSecret) return null;

  return new Promise((resolve, reject) => {
    const timestamp = Date.now();
    // BCRYPT client_secret+timestamp
    const body = `client_id=${CONFIG.naver.clientId}&client_secret=${CONFIG.naver.clientSecret}&grant_type=client_credentials&type=SELF&timestamp=${timestamp}`;
    const url = new URL(CONFIG.naver.tokenUrl);
    const options = {
      hostname: url.hostname,
      path: url.pathname,
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    };
    const req = https.request(options, (res) => {
      let buf = '';
      res.on('data', (c) => (buf += c));
      res.on('end', () => {
        try {
          const json = JSON.parse(buf);
          if (json.access_token) {
            naverAccessToken = json.access_token;
            naverTokenExpiry = Date.now() + (json.expires_in || 3600) * 1000 - 60000;
            resolve(naverAccessToken);
          } else {
            reject(new Error(json.message || 'Token 발급 실패'));
          }
        } catch {
          reject(new Error('Token 응답 파싱 실패'));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// 방법 2: 텔레그램에서 수동으로 주문 입력
// 형식: "주문 {주문번호} {구매자명} {연락처} {상품명}"
async function handleManualOrder(text) {
  // "주문 202603010001 홍길동 010-1234-5678 [대구] 디즈니 콘서트, S석 2매"
  const match = text.match(/^주문\s+(\S+)\s+(\S+)\s+([\d-]+)\s+(.+?)(?:\s+(\d+)매)?$/);
  if (!match) {
    await sendMessage(
      `📝 수동 주문 형식:\n<code>주문 {주문번호} {구매자명} {연락처} {상품명} {수량}매</code>\n\n` +
      `예시:\n<code>주문 2026030100123 홍길동 010-1234-5678 [대구] 디즈니 콘서트, S석 2매</code>`
    );
    return;
  }

  const order = {
    orderId: match[1],
    buyerName: match[2],
    phone: match[3],
    productName: match[4],
    qty: parseInt(match[5] || '1', 10),
    orderDate: new Date().toISOString(),
  };

  const processed = readJson(CONFIG.processedFile);
  if (processed.includes(order.orderId)) {
    await sendMessage(`⚠️ 이미 처리된 주문입니다: ${order.orderId}`);
    return;
  }

  await requestApproval(order);
}

// ============================================================
// Firebase 이벤트 자동 동기화 (naverOnly 이벤트만)
// ============================================================
async function syncNaverOnlyEvents() {
  try {
    const events = await callFirebaseCF('listEventsHttp', {});
    const naverOnly = (Array.isArray(events) ? events : events.events || [])
      .filter((e) => e.naverOnly === true);
    CONFIG.firebase._naverOnlyEvents = naverOnly;

    if (naverOnly.length > 0) {
      log(`🎯 네이버 전용 이벤트 ${naverOnly.length}건 동기화`);
      for (const e of naverOnly) {
        log(`   • ${e.title} (${e.id})`);
      }
    }
  } catch (err) {
    log(`⚠️ 이벤트 동기화 실패: ${err.message}`);
  }
}

// 주문 상품명으로 매칭되는 naverOnly 이벤트 찾기
function findEventForOrder(productName) {
  // 1) 수동 eventMap 우선
  const info = parseProductInfo(productName);
  if (CONFIG.firebase.eventMap[info.perfKey]) {
    return CONFIG.firebase.eventMap[info.perfKey];
  }

  // 2) naverOnly 이벤트 자동 매칭 (이벤트 제목이 상품명에 포함)
  for (const ev of CONFIG.firebase._naverOnlyEvents) {
    const title = (ev.title || '').toLowerCase();
    const product = productName.toLowerCase();
    // 이벤트 제목의 핵심 키워드가 상품명에 포함되면 매칭
    if (title && product.includes(title.split(' ')[0])) return ev.id;
    // 또는 이벤트 ID가 상품명에 직접 매핑된 경우
    if (ev.naverProductKeyword && product.includes(ev.naverProductKeyword.toLowerCase())) {
      return ev.id;
    }
  }
  return null;
}

// ============================================================
// 메인 루프
// ============================================================
async function main() {
  log('🎫 네이버 좌석배정 봇 시작');

  if (CONFIG.telegramBotToken === 'YOUR_BOT_TOKEN_HERE') {
    console.error('❌ 텔레그램 봇 토큰을 설정해주세요!');
    console.error('   1. @BotFather에서 새 봇 생성');
    console.error('   2. bot.js의 CONFIG.telegramBotToken에 토큰 입력');
    console.error('   또는 환경변수: NAVER_SEAT_BOT_TOKEN=xxx node bot.js');
    process.exit(1);
  }

  // Firebase에서 naverOnly 이벤트 동기화
  await syncNaverOnlyEvents();

  const evCount = CONFIG.firebase._naverOnlyEvents.length;
  await sendMessage(
    `🎫 <b>네이버 좌석배정 봇 시작!</b>\n\n` +
    `🎯 네이버 전용 이벤트: ${evCount}건\n` +
    `📋 "도움말" 입력으로 명령어 확인\n` +
    `📋 "주문 ..." 입력으로 수동 주문 등록`
  );

  // 텔레그램 폴링 루프
  setInterval(pollUpdates, 3000);

  // 이벤트 동기화 (10분마다)
  setInterval(syncNaverOnlyEvents, 10 * 60 * 1000);

  // 초기 대기 주문 체크
  const pendingKeys = Object.keys(pendingOrders);
  if (pendingKeys.length > 0) {
    await sendMessage(`⏳ 미처리 주문 ${pendingKeys.length}건 — "대기" 입력으로 확인`);
  }

  log('✅ 봇 실행 중 (Ctrl+C 종료)');
}

// 메시지 핸들러에 수동 주문 추가
const originalHandleMessage = handleMessage;
handleMessage = async function (msg) {
  const chatId = String(msg.chat.id);
  if (chatId !== CONFIG.telegramChatId) return;
  const text = (msg.text || '').trim();

  if (text.startsWith('주문 ') || text.startsWith('주문\n')) {
    await handleManualOrder(text);
    return;
  }
  return originalHandleMessage(msg);
};

main().catch((err) => {
  console.error('봇 시작 실패:', err);
  process.exit(1);
});
