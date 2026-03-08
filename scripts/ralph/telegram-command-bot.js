#!/usr/bin/env node

const fs = require('fs');
const https = require('https');
const path = require('path');

const scriptDir = __dirname;
const prdPath = path.join(scriptDir, 'prd.json');
const progressPath = path.join(scriptDir, 'progress.txt');
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

function readPrdStories() {
  const prd = JSON.parse(fs.readFileSync(prdPath, 'utf8'));
  const stories = Array.isArray(prd.userStories) ? prd.userStories : [];
  return stories
    .filter((story) => typeof story.id === 'string' && typeof story.title === 'string')
    .sort((a, b) => compareStoryIds(a.id, b.id));
}

function compareStoryIds(a, b) {
  return extractStoryNumber(a) - extractStoryNumber(b);
}

function extractStoryNumber(storyId) {
  const match = String(storyId).match(/(\d+)/);
  return match ? Number.parseInt(match[1], 10) : 0;
}

function buildCompletedStoriesMessage() {
  const stories = readPrdStories().filter((story) => story.passes === true);
  const today = new Date().toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' });

  if (stories.length === 0) {
    return `📚 ${today} 기준\n완료된 PRD가 아직 없습니다.`;
  }

  const lines = stories.map((story) => `• ${story.id} — ${story.title}`);
  return [
    `📚 ${today} 기준 완료된 PRD 목록 (${stories.length}건)`,
    '',
    ...lines,
  ].join('\n');
}

function buildRemainingStoriesMessage() {
  const stories = readPrdStories().filter((story) => story.passes !== true);
  const today = new Date().toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' });

  if (stories.length === 0) {
    return [
      `🗂 ${today} 기준 앞으로 해야 할 PRD 목록`,
      '',
      '✅ 남아 있는 PRD가 없습니다.',
      '✅ 현재 Ralph PRD는 전부 완료 상태입니다.',
    ].join('\n');
  }

  const lines = stories.map((story) => `• ${story.id} — ${story.title}`);
  return [
    `🗂 ${today} 기준 앞으로 해야 할 PRD 목록 (${stories.length}건)`,
    '',
    ...lines,
  ].join('\n');
}

function parseProgressSections() {
  const lines = fs.readFileSync(progressPath, 'utf8').split(/\r?\n/);
  const sections = [];
  let current = null;

  for (const line of lines) {
    if (line.startsWith('## ')) {
      if (current) sections.push(current);
      current = { heading: line.trim(), lines: [] };
      continue;
    }

    if (current) {
      current.lines.push(line);
    }
  }

  if (current) sections.push(current);
  return sections;
}

function findLatestProgressSection() {
  const sections = parseProgressSections();
  const candidates = [];

  for (const section of sections) {
    const match = section.heading.match(/^##\s+(\d{4}-\d{2}-\d{2})\s+-\s+(MT-\d+)\s+\((.+)\)$/);
    if (!match) continue;

    candidates.push({
      section,
      date: match[1],
      storyId: match[2],
      title: match[3],
      storyNumber: extractStoryNumber(match[2]),
    });
  }

  candidates.sort((a, b) => {
    if (a.date !== b.date) {
      return a.date.localeCompare(b.date);
    }
    return a.storyNumber - b.storyNumber;
  });

  return candidates.at(-1) ?? null;
}

function normalizeProgressBody(lines) {
  const body = [];

  for (const rawLine of lines) {
    const line = rawLine.trimEnd();
    const trimmed = line.trim();

    if (!trimmed || trimmed === '---') continue;
    if (trimmed.startsWith('- Files')) continue;
    if (trimmed.startsWith('- Files referenced')) continue;
    if (trimmed.startsWith('- Verification')) continue;
    if (trimmed.startsWith('- **Learnings')) break;

    body.push(
      trimmed
        .replace(/^\-\s*/, '• ')
        .replace(/^\*\*(.+)\*\*:$/, '$1')
        .replace(/`/g, "'"),
    );
  }

  return body.slice(0, 12);
}

function buildLatestStoryMessage() {
  const latest = findLatestProgressSection();
  const today = new Date().toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' });

  if (!latest) {
    return `🕘 ${today} 기준\n최근 완료한 PRD 기록을 찾지 못했습니다.`;
  }

  const body = normalizeProgressBody(latest.section.lines);

  return [
    `🕘 ${latest.date} 기준 방금한 PRD`,
    '',
    `${latest.storyId} — ${latest.title}`,
    '',
    ...body,
  ].join('\n');
}

function buildHelpMessage() {
  const today = new Date().toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' });

  return [
    `🤖 ${today} 기준 Ralph PRD 명령`,
    '',
    '• 지금까지한 PRD 목록확인',
    '• 앞으로 해야할 PRD 목록 확인',
    '• 방금한 PRD 확인',
    '',
    '영문 슬래시 명령도 가능:',
    '• /done',
    '• /remaining',
    '• /latest',
    '• /help',
  ].join('\n');
}

function normalizeCommand(text) {
  return String(text || '')
    .trim()
    .toLowerCase()
    .replace(/@ralphprd_bot/g, '')
    .replace(/\s+/g, '');
}

function resolveCommand(text) {
  const normalized = normalizeCommand(text);

  if (!normalized) return null;

  const helpCommands = new Set(['/start', '/help', '도움말']);
  const doneCommands = new Set([
    '/done',
    '/completed',
    '지금까지한prd목록확인',
    '지금까지한prd목록',
    '완료목록',
  ]);
  const remainingCommands = new Set([
    '/remaining',
    '/todo',
    '앞으로해야할prd목록확인',
    '앞으로해야할prd목록',
    '남은prd목록',
  ]);
  const latestCommands = new Set([
    '/latest',
    '/recent',
    '방금한prd확인',
    '최근prd확인',
    '방금한prd',
  ]);

  if (helpCommands.has(normalized)) return 'help';
  if (doneCommands.has(normalized)) return 'done';
  if (remainingCommands.has(normalized)) return 'remaining';
  if (latestCommands.has(normalized)) return 'latest';
  return null;
}

async function handleMessage(message) {
  const chatId = String(message?.chat?.id ?? '');
  if (chatId !== CONFIG.chatId) {
    return;
  }

  const command = resolveCommand(message.text);
  if (!command) {
    await sendMessage(
      [
        '알 수 없는 명령입니다.',
        '',
        '사용 가능한 명령:',
        '• 지금까지한 PRD 목록확인',
        '• 앞으로 해야할 PRD 목록 확인',
        '• 방금한 PRD 확인',
        '• /help',
      ].join('\n'),
    );
    return;
  }

  if (command === 'help') {
    await sendMessage(buildHelpMessage());
    return;
  }

  if (command === 'done') {
    await sendMessage(buildCompletedStoriesMessage());
    return;
  }

  if (command === 'remaining') {
    await sendMessage(buildRemainingStoriesMessage());
    return;
  }

  if (command === 'latest') {
    await sendMessage(buildLatestStoryMessage());
  }
}

async function registerCommands() {
  await telegramRequest('setMyCommands', {
    commands: [
      { command: 'done', description: '완료된 PRD 목록 확인' },
      { command: 'remaining', description: '앞으로 할 PRD 목록 확인' },
      { command: 'latest', description: '방금한 PRD 확인' },
      { command: 'help', description: '명령어 보기' },
    ],
  });
}

async function pollLoop() {
  const state = readState();

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
      log(`텔레그램 명령 폴링 오류: ${error.message}`);
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
  log('Ralph 텔레그램 명령 봇 시작');
  await sendMessage(buildHelpMessage());
  await pollLoop();
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
