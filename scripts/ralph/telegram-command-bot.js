#!/usr/bin/env node

const fs = require('fs');
const https = require('https');
const path = require('path');

const scriptDir = __dirname;
const stateDir = path.join(scriptDir, 'state');
const statePath = path.join(stateDir, 'telegram-command-bot-state.json');

loadEnvFile(path.join(scriptDir, '.env.local'));

const CONFIG = {
  botToken:
    process.env.RALPH_TELEGRAM_BOT_TOKEN ||
    process.env.NAVER_SEAT_BOT_TOKEN ||
    process.env.TELEGRAM_BOT_TOKEN ||
    '',
  chatId:
    process.env.RALPH_TELEGRAM_CHAT_ID ||
    process.env.NAVER_SEAT_CHAT_ID ||
    process.env.TELEGRAM_CHAT_ID ||
    '',
  pollTimeoutSeconds: 20,
  retryDelayMs: 3000,
  // 멜론티켓 Firebase Cloud Functions
  cfBaseUrl: 'https://us-central1-melon-ticket-mvp-2026.cloudfunctions.net',
  botApiKey: process.env.BOT_API_KEY || 'melon-bot-secret-2026',
};

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;

  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;

    const eqIndex = line.indexOf('=');
    if (eqIndex <= 0) continue;

    const key = line.slice(0, eqIndex).trim();
    let value = line.slice(eqIndex + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (!process.env[key]) {
      process.env[key] = value;
    }
  }
}

function ensureStateDir() {
  if (!fs.existsSync(stateDir)) {
    fs.mkdirSync(stateDir, { recursive: true });
  }
}

function readState() {
  ensureStateDir();
  if (!fs.existsSync(statePath)) {
    return { lastUpdateId: 0 };
  }

  try {
    return JSON.parse(fs.readFileSync(statePath, 'utf8'));
  } catch {
    return { lastUpdateId: 0 };
  }
}

function writeState(state) {
  ensureStateDir();
  fs.writeFileSync(statePath, JSON.stringify(state, null, 2));
}

function log(message) {
  const timestamp = new Date().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' });
  console.log(`[${timestamp}] ${message}`);
}

function telegramRequest(method, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = https.request(
      {
        hostname: 'api.telegram.org',
        path: `/bot${CONFIG.botToken}/${method}`,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
        },
      },
      (res) => {
        let buffer = '';
        res.on('data', (chunk) => {
          buffer += chunk;
        });
        res.on('end', () => {
          try {
            const parsed = JSON.parse(buffer);
            if (res.statusCode >= 400 || parsed.ok === false) {
              reject(
                new Error(parsed.description || `Telegram HTTP ${res.statusCode}`),
              );
              return;
            }
            resolve(parsed.result ?? parsed);
          } catch (error) {
            reject(error);
          }
        });
      },
    );

    req.on('error', reject);
    req.setTimeout(30000, () => {
      req.destroy(new Error('Telegram timeout'));
    });
    req.write(data);
    req.end();
  });
}

async function sendMessage(text) {
  const chunks = splitMessage(text);

  for (const chunk of chunks) {
    await telegramRequest('sendMessage', {
      chat_id: CONFIG.chatId,
      text: chunk,
    });
  }
}

function splitMessage(message, limit = 3500) {
  if (message.length <= limit) return [message];

  const chunks = [];
  let remaining = message;

  while (remaining.length > limit) {
    let index = remaining.lastIndexOf('\n', limit);
    if (index < 0) index = limit;
    chunks.push(remaining.slice(0, index).trim());
    remaining = remaining.slice(index).trim();
  }

  if (remaining) chunks.push(remaining);
  return chunks;
}

// ============================================================
// 멜론티켓 Firebase Cloud Functions 통신
// ============================================================

function cfRequest(endpoint, body) {
  const url = new URL(`${CONFIG.cfBaseUrl}/${endpoint}`);
  const data = body ? JSON.stringify(body) : null;
  const options = {
    hostname: url.hostname,
    path: url.pathname,
    method: body ? 'POST' : 'GET',
    headers: {
      'Authorization': `Bearer ${CONFIG.botApiKey}`,
      'Content-Type': 'application/json',
    },
  };
  if (data) {
    options.headers['Content-Length'] = Buffer.byteLength(data);
  }

  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let buffer = '';
      res.on('data', (chunk) => { buffer += chunk; });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(buffer);
          if (res.statusCode >= 400) {
            reject(new Error(parsed.error || `HTTP ${res.statusCode}`));
            return;
          }
          resolve(parsed);
        } catch (error) {
          reject(new Error(`JSON parse error: ${buffer.slice(0, 200)}`));
        }
      });
    });
    req.on('error', reject);
    req.setTimeout(30000, () => { req.destroy(new Error('CF timeout')); });
    if (data) req.write(data);
    req.end();
  });
}

// ============================================================
// 네이버 주문 자동 발권 파이프라인
// ============================================================

/**
 * 텔레그램 주문 알림 메시지 파싱
 * 반환: { productName, seatGrade, quantity, buyerName, buyerPhone, naverOrderId }
 */
function parseNaverOrderMessage(text) {
  if (!text) return null;

  // 📦 새 주문! 또는 📦 로 시작하는 메시지인지 확인
  if (!text.includes('📦') && !text.includes('새 주문')) return null;

  const result = {};

  // 공연 정보: 🎫 공연: [내용], 등급석 (N매)
  const perfMatch = text.match(/🎫\s*공연:\s*(.+)/);
  if (perfMatch) {
    const perfLine = perfMatch[1].trim();
    // "상품명, VIP석 (3매)" 패턴
    const gradeMatch = perfLine.match(/,\s*(VIP|R|S|A)석\s*\((\d+)매\)\s*$/i);
    if (gradeMatch) {
      result.productName = perfLine.slice(0, gradeMatch.index).trim();
      result.seatGrade = gradeMatch[1].toUpperCase();
      result.quantity = Number.parseInt(gradeMatch[2], 10);
    } else {
      // 등급이 없는 경우 (비지정석 등)
      const qtyMatch = perfLine.match(/\((\d+)매\)\s*$/);
      result.productName = qtyMatch
        ? perfLine.slice(0, qtyMatch.index).trim()
        : perfLine;
      result.quantity = qtyMatch ? Number.parseInt(qtyMatch[1], 10) : 1;
      result.seatGrade = 'A'; // 기본값
    }
  }

  // 구매자: 👤 구매자: 이름
  const buyerMatch = text.match(/👤\s*구매자:\s*(.+)/);
  if (buyerMatch) {
    result.buyerName = buyerMatch[1].trim();
  }

  // 연락처: 📱 연락처: 010-xxxx-xxxx
  const phoneMatch = text.match(/📱\s*연락처:\s*([\d\-]+)/);
  if (phoneMatch) {
    result.buyerPhone = phoneMatch[1].trim();
  }

  // 주문번호 (숫자 또는 TEST로 시작하는 테스트 번호)
  const orderMatch = text.match(/주문번호:\s*(\S+)/);
  if (orderMatch) {
    result.naverOrderId = orderMatch[1].trim();
  }

  // 필수 필드 확인
  if (!result.buyerName || !result.buyerPhone || !result.naverOrderId) {
    return null;
  }

  return result;
}

/**
 * listEventsHttp에서 이벤트 목록 가져오기
 */
async function fetchEvents() {
  const data = await cfRequest('listEventsHttp');
  return data.events || [];
}

/**
 * 파싱된 공연명으로 이벤트 매칭
 * naverProductKeyword 또는 title로 매칭
 */
function matchEvent(events, productName) {
  if (!productName || events.length === 0) return null;

  const name = productName.toLowerCase();

  // 1차: naverProductKeyword가 있는 이벤트에서 키워드 매칭
  let bestMatch = null;
  let bestScore = 0;

  for (const event of events) {
    const keyword = (event.naverProductKeyword || '').toLowerCase();
    if (!keyword) continue;

    // 키워드를 쉼표나 공백으로 분리
    const keywords = keyword.split(/[,\s]+/).filter(Boolean);
    let score = 0;
    for (const kw of keywords) {
      if (name.includes(kw)) score++;
    }

    if (score > bestScore) {
      bestScore = score;
      bestMatch = event;
    }
  }

  if (bestMatch && bestScore > 0) return bestMatch;

  // 2차: title로 부분 매칭
  for (const event of events) {
    const title = (event.title || '').toLowerCase();
    if (!title) continue;

    // 제목의 주요 단어가 공연명에 포함되는지
    const titleWords = title.split(/\s+/).filter((w) => w.length >= 2);
    let matched = 0;
    for (const word of titleWords) {
      if (name.includes(word)) matched++;
    }
    const ratio = titleWords.length > 0 ? matched / titleWords.length : 0;

    if (ratio > 0.5 && matched > bestScore) {
      bestScore = matched;
      bestMatch = event;
    }
  }

  return bestMatch;
}

/**
 * createNaverOrderHttp 호출하여 티켓 생성
 */
async function createTickets(parsed, eventId) {
  return cfRequest('createNaverOrderHttp', {
    eventId,
    naverOrderId: parsed.naverOrderId,
    buyerName: parsed.buyerName,
    buyerPhone: parsed.buyerPhone,
    productName: parsed.productName || '',
    seatGrade: parsed.seatGrade,
    quantity: parsed.quantity,
  });
}

/**
 * 📦 주문 메시지 자동 감지 → 발권 처리
 */
async function handleOrderMessage(text) {
  const parsed = parseNaverOrderMessage(text);
  if (!parsed) {
    await sendMessage('⚠️ 주문 메시지 파싱 실패 — 형식을 확인해주세요.');
    return;
  }

  await sendMessage([
    '🔄 주문 파싱 완료, 발권 처리 중...',
    '',
    `👤 ${parsed.buyerName} (${parsed.buyerPhone})`,
    `🎫 ${parsed.seatGrade}석 ${parsed.quantity}매`,
    `📋 주문번호: ${parsed.naverOrderId}`,
    parsed.productName ? `📦 상품: ${parsed.productName}` : '',
  ].filter(Boolean).join('\n'));

  // 이벤트 매칭
  let events;
  try {
    events = await fetchEvents();
  } catch (err) {
    await sendMessage(`❌ 이벤트 목록 조회 실패: ${err.message}`);
    return;
  }

  const matchedEvent = matchEvent(events, parsed.productName);
  if (!matchedEvent) {
    await sendMessage([
      '❌ 매칭되는 이벤트를 찾지 못했습니다.',
      '',
      `검색어: ${parsed.productName}`,
      '',
      '등록된 이벤트:',
      ...events.slice(0, 10).map((e) => `• ${e.title} (${e.naverProductKeyword || '키워드 없음'})`),
    ].join('\n'));
    return;
  }

  await sendMessage(`🎯 이벤트 매칭: ${matchedEvent.title} (${matchedEvent.venueName})`);

  // 발권 API 호출
  let result;
  try {
    result = await createTickets(parsed, matchedEvent.id);
  } catch (err) {
    await sendMessage(`❌ 발권 실패: ${err.message}`);
    return;
  }

  // 성공 회신
  const ticketLines = (result.tickets || []).map(
    (t, i) => `${i + 1}️⃣ ${t.url}`,
  );

  await sendMessage([
    '✅ 발권 완료!',
    '',
    `📋 주문번호: ${parsed.naverOrderId}`,
    `👤 ${parsed.buyerName} (${parsed.seatGrade}석 ${parsed.quantity}매)`,
    `🎫 ${matchedEvent.title}`,
    '',
    '티켓 링크:',
    ...ticketLines,
    '',
    '📱 뿌리오 SMS 자동 발송 예정 (2건: 주문확인 + 모바일티켓)',
  ].join('\n'));
}

/**
 * /testorder — 테스트 주문 메시지로 파이프라인 검증
 */
async function handleTestOrder(args) {
  const testMessage = [
    '📦 새 주문!',
    '',
    '🎫 공연: [테스트] 멜론티켓 테스트 공연, A석 (1매)',
    '👤 구매자: 테스트유저',
    '📱 연락처: 010-0000-0000',
    '',
    `주문번호: TEST${Date.now()}`,
  ].join('\n');

  const parsed = parseNaverOrderMessage(testMessage);
  if (!parsed) {
    await sendMessage('❌ 테스트 메시지 파싱 실패 (내부 오류)');
    return;
  }

  await sendMessage([
    '🧪 테스트 주문 파싱 결과:',
    '',
    `👤 구매자: ${parsed.buyerName}`,
    `📱 연락처: ${parsed.buyerPhone}`,
    `🎫 등급: ${parsed.seatGrade}석`,
    `📦 수량: ${parsed.quantity}매`,
    `📋 주문번호: ${parsed.naverOrderId}`,
    `📦 상품명: ${parsed.productName}`,
  ].join('\n'));

  // 이벤트 매칭 테스트
  try {
    const events = await fetchEvents();
    const matched = matchEvent(events, parsed.productName);

    if (matched) {
      await sendMessage(`🎯 매칭된 이벤트: ${matched.title}`);
    } else {
      await sendMessage([
        '⚠️ 매칭 이벤트 없음 (테스트 상품이므로 정상)',
        '',
        '등록된 이벤트:',
        ...events.slice(0, 10).map((e) => `• ${e.title} (keyword: ${e.naverProductKeyword || '없음'})`),
      ].join('\n'));
    }
  } catch (err) {
    await sendMessage(`⚠️ 이벤트 조회 실패: ${err.message}`);
  }

  if (args === 'real') {
    await sendMessage('⚠️ real 모드는 실제 이벤트가 매칭되어야 동작합니다. 실제 주문 메시지를 전달해주세요.');
  }
}

// ============================================================
// 봇 명령어 처리
// ============================================================

function buildHelpMessage() {
  return [
    '🎫 멜론티켓 발권 봇',
    '',
    '사용 방법:',
    '• 📦 주문 메시지를 그대로 전달하면 자동 발권',
    '• /testorder — 테스트 주문으로 파이프라인 검증',
    '• /help — 이 도움말 보기',
  ].join('\n');
}

async function handleMessage(message) {
  const chatId = String(message?.chat?.id ?? '');
  if (chatId !== CONFIG.chatId) {
    return;
  }

  const rawText = message.text || '';

  // /testorder 명령어
  if (rawText.trim().startsWith('/testorder')) {
    const args = rawText.trim().replace(/^\/testorder\s*/, '').trim();
    await handleTestOrder(args);
    return;
  }

  // /help 또는 /start
  if (rawText.trim() === '/help' || rawText.trim() === '/start') {
    await sendMessage(buildHelpMessage());
    return;
  }

  // 📦 주문 메시지 자동 감지
  if (rawText.includes('📦') && rawText.includes('주문번호:')) {
    await handleOrderMessage(rawText);
    return;
  }

  // 알 수 없는 메시지
  await sendMessage([
    '알 수 없는 명령입니다.',
    '',
    '사용 방법:',
    '• 📦 주문 메시지를 그대로 전달하면 자동 발권',
    '• /testorder — 테스트 주문 검증',
    '• /help — 도움말',
  ].join('\n'));
}

async function registerCommands() {
  await telegramRequest('setMyCommands', {
    commands: [
      { command: 'testorder', description: '테스트 주문으로 발권 파이프라인 검증' },
      { command: 'help', description: '명령어 보기' },
    ],
  });
}

// ============================================================
// 메인 폴링 루프
// ============================================================

async function pollLoop() {
  const state = readState();

  // 첫 시작 시 기존 메시지 건너뛰기
  if (state.lastUpdateId === 0) {
    try {
      const pending = await telegramRequest('getUpdates', { offset: -1, limit: 1 });
      if (Array.isArray(pending) && pending.length > 0) {
        state.lastUpdateId = pending[pending.length - 1].update_id;
        writeState(state);
        log('기존 메시지 건너뛰기 완료 (offset: ' + state.lastUpdateId + ')');
      }
    } catch (e) {
      log('기존 메시지 건너뛰기 실패: ' + e.message);
    }
  }

  while (true) {
    try {
      const updates = await telegramRequest('getUpdates', {
        offset: state.lastUpdateId + 1,
        timeout: CONFIG.pollTimeoutSeconds,
        allowed_updates: ['message'],
      });

      if (Array.isArray(updates)) {
        for (const update of updates) {
          state.lastUpdateId = Math.max(state.lastUpdateId, update.update_id);
          if (update.message) {
            await handleMessage(update.message);
          }
        }
        writeState(state);
      }
    } catch (error) {
      log(`텔레그램 폴링 오류: ${error.message}`);
      await delay(CONFIG.retryDelayMs);
    }
  }
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  if (!CONFIG.botToken) {
    throw new Error('RALPH_TELEGRAM_BOT_TOKEN 이 설정되지 않았습니다');
  }
  if (!CONFIG.chatId) {
    throw new Error('RALPH_TELEGRAM_CHAT_ID 가 설정되지 않았습니다');
  }

  await registerCommands();
  log('멜론티켓 발권 봇 시작');
  await sendMessage(buildHelpMessage());
  await pollLoop();
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
