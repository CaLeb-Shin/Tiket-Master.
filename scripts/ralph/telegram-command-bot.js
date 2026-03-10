#!/usr/bin/env node

const childProcess = require('child_process');
const fs = require('fs');
const https = require('https');
const path = require('path');

const scriptDir = __dirname;
const projectRoot = path.resolve(scriptDir, '../..');
const prdPath = path.join(scriptDir, 'prd.json');
const progressPath = path.join(scriptDir, 'progress.txt');
const stateDir = path.join(scriptDir, 'state');
const statePath = path.join(stateDir, 'telegram-command-bot-state.json');
const runnerStatePath = path.join(stateDir, 'ralph-runner-state.json');
const monitorStatePath = path.join(stateDir, 'ralph-runner-monitor-state.json');
const runnerLogPath = path.join(stateDir, 'ralph-runner.log');
const summaryFilePath = path.join(scriptDir, 'telegram-summary-latest.md');

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
  runIterations: Number.parseInt(
    process.env.RALPH_RUN_MAX_ITERATIONS || '10',
    10,
  ),
  heartbeatSeconds: Number.parseInt(
    process.env.RALPH_RUN_HEARTBEAT_SECONDS || '300',
    10,
  ),
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

function readRunnerState() {
  ensureStateDir();
  if (!fs.existsSync(runnerStatePath)) {
    return {};
  }

  try {
    return JSON.parse(fs.readFileSync(runnerStatePath, 'utf8'));
  } catch {
    return {};
  }
}

function writeRunnerState(state) {
  ensureStateDir();
  fs.writeFileSync(runnerStatePath, JSON.stringify(state, null, 2));
}

function readMonitorState() {
  ensureStateDir();
  if (!fs.existsSync(monitorStatePath)) {
    return {};
  }

  try {
    return JSON.parse(fs.readFileSync(monitorStatePath, 'utf8'));
  } catch {
    return {};
  }
}

function writeMonitorState(state) {
  ensureStateDir();
  fs.writeFileSync(monitorStatePath, JSON.stringify(state, null, 2));
}

function isProcessAlive(pid) {
  if (!pid || !Number.isInteger(pid)) return false;

  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
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

function readTextFile(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`파일을 찾을 수 없습니다: ${filePath}`);
  }
  return fs.readFileSync(filePath, 'utf8');
}

function extractDocumentTitle(filePath, body) {
  const lines = body.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (/^#{1,3}\s+/.test(trimmed)) {
      return trimmed.replace(/^#{1,3}\s+/, '').trim();
    }
  }
  return path.basename(filePath);
}

function normalizeMarkdownDocument(body) {
  const lines = body.split(/\r?\n/);
  const normalized = [];
  let titleSkipped = false;

  for (const rawLine of lines) {
    const trimmed = rawLine.trim();
    if (!trimmed) {
      if (normalized.at(-1) !== '') {
        normalized.push('');
      }
      continue;
    }

    if (!titleSkipped && /^#\s+/.test(trimmed)) {
      titleSkipped = true;
      continue;
    }

    if (/^###\s+/.test(trimmed)) {
      normalized.push(`■ ${trimmed.replace(/^###\s+/, '').trim()}`);
      normalized.push('');
      continue;
    }

    if (/^##\s+/.test(trimmed)) {
      normalized.push(`● ${trimmed.replace(/^##\s+/, '').trim()}`);
      normalized.push('');
      continue;
    }

    if (/^#\s+/.test(trimmed)) {
      normalized.push(trimmed.replace(/^#\s+/, '').trim());
      normalized.push('');
      continue;
    }

    if (/^\*\*(.+)\*\*$/.test(trimmed)) {
      normalized.push(trimmed.replace(/^\*\*(.+)\*\*$/, '$1'));
      continue;
    }

    normalized.push(
      trimmed
        .replace(/^- \[x\]\s*/i, '✅ ')
        .replace(/^- \[\]\s*/i, '⬜ ')
        .replace(/^- ✅\s*/u, '✅ ')
        .replace(/^- ❌\s*/u, '❌ ')
        .replace(/^- /, '• ')
        .replace(/\*\*/g, '')
        .replace(/`/g, "'"),
    );
  }

  while (normalized.at(-1) === '') {
    normalized.pop();
  }

  return normalized.join('\n');
}

function findLatestDesignAuditFile() {
  const files = fs
    .readdirSync(projectRoot)
    .filter((name) => /^멜론티켓 디자인 감사 \d{4}-\d{2}-\d{2}\.md$/.test(name))
    .sort();

  if (files.length === 0) {
    throw new Error('디자인 감사 파일을 찾지 못했습니다');
  }

  return path.join(projectRoot, files.at(-1));
}

function buildDocumentMessage(filePath, label) {
  const body = readTextFile(filePath);
  const title = extractDocumentTitle(filePath, body);
  const normalized = normalizeMarkdownDocument(body);

  return [
    label,
    title,
    '',
    normalized,
  ].join('\n').trim();
}

function readPrdStories() {
  const prd = JSON.parse(fs.readFileSync(prdPath, 'utf8'));
  const stories = Array.isArray(prd.userStories) ? prd.userStories : [];
  return stories
    .filter((story) => typeof story.id === 'string' && typeof story.title === 'string')
    .sort((a, b) => compareStoryIds(a.id, b.id));
}

function readPendingStories() {
  return readPrdStories().filter((story) => story.passes !== true);
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

function buildRunStatusMessage() {
  const runnerState = readRunnerState();
  const pid = Number.isInteger(runnerState.pid) ? runnerState.pid : null;
  const isRunning = pid != null && isProcessAlive(pid);
  const pendingStories = readPendingStories();
  const latest = findLatestProgressSection();
  const latestLabel = latest
    ? `${latest.storyId} — ${latest.title}`
    : '기록 없음';
  const nextLabel = pendingStories.length > 0
    ? `${pendingStories[0].id} — ${pendingStories[0].title}`
    : '모든 PRD가 완료 상태입니다.';

  if (!isRunning) {
    return [
      '🛠 Ralph 실행 상태',
      '',
      '현재 실행 중인 워커가 없습니다.',
      `최근 완료: ${latestLabel}`,
      pendingStories.length > 0
          ? `남은 PRD: ${pendingStories.length}건`
          : '남은 PRD: 0건',
      `다음 대상: ${nextLabel}`,
    ].join('\n');
  }

  const startedAt = runnerState.startedAt || '기록 없음';
  const iterations = runnerState.iterations || CONFIG.runIterations;

  return [
    '🛠 Ralph 실행 상태',
    '',
    `실행 중: 예`,
    `PID: ${pid}`,
    `시작 시각: ${startedAt}`,
    `최근 완료: ${latestLabel}`,
    `다음 대상: ${nextLabel}`,
    `남은 PRD: ${pendingStories.length}건`,
    `최대 반복: ${iterations}`,
    `로그: ${runnerLogPath}`,
  ].join('\n');
}

function startRalphRunner() {
  const pendingStories = readPendingStories();
  if (pendingStories.length === 0) {
    return {
      started: false,
      reason: '모든 Ralph PRD가 이미 완료 상태입니다.',
    };
  }

  const existing = readRunnerState();
  if (Number.isInteger(existing.pid) && isProcessAlive(existing.pid)) {
    return {
      started: false,
      reason: `이미 실행 중입니다. PID ${existing.pid}`,
    };
  }

  ensureStateDir();
  const logFd = fs.openSync(runnerLogPath, 'a');
  const child = childProcess.spawn(
    'zsh',
    [
      '-lc',
      `cd "${projectRoot}" && exec ./scripts/ralph/ralph.sh ${CONFIG.runIterations}`,
    ],
    {
      detached: true,
      stdio: ['ignore', logFd, logFd],
    },
  );

  child.unref();
  fs.closeSync(logFd);

  const runnerState = {
    pid: child.pid,
    startedAt: new Date().toLocaleString('ko-KR', {
      timeZone: 'Asia/Seoul',
    }),
    iterations: CONFIG.runIterations,
    stoppedAt: null,
    stoppedBy: null,
  };
  writeRunnerState(runnerState);
  writeMonitorState(createMonitorStateForRunner(child.pid));

  return {
    started: true,
    pid: child.pid,
    nextStory: pendingStories[0],
    count: pendingStories.length,
  };
}

function stopRalphRunner() {
  const runnerState = readRunnerState();
  const pid = Number.isInteger(runnerState.pid) ? runnerState.pid : null;

  if (pid == null || !isProcessAlive(pid)) {
    return {
      stopped: false,
      reason: '현재 실행 중인 Ralph 워커가 없습니다.',
    };
  }

  try {
    process.kill(pid, 'SIGTERM');
    writeRunnerState({
      ...runnerState,
      stoppedAt: new Date().toLocaleString('ko-KR', {
        timeZone: 'Asia/Seoul',
      }),
      stoppedBy: 'telegram-command-bot',
    });
    const monitorState = readMonitorState();
    writeMonitorState({
      ...monitorState,
      runnerPid: pid,
      lastStopNotifiedPid: pid,
      lastHeartbeatAt: Date.now(),
    });
    return {
      stopped: true,
      pid,
    };
  } catch (error) {
    return {
      stopped: false,
      reason: error.message || '중지 실패',
    };
  }
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

function buildProgressKey(latest) {
  if (!latest) return '';
  return `${latest.date}:${latest.storyId}`;
}

function buildStoryLabel(story) {
  if (!story) return '기록 없음';
  return `${story.id} — ${story.title}`;
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

function extractVerificationLines(lines) {
  const output = [];
  let inVerification = false;

  for (const rawLine of lines) {
    const trimmed = rawLine.trim();
    if (!trimmed || trimmed === '---') {
      if (inVerification) break;
      continue;
    }

    if (trimmed.startsWith('- Verification:')) {
      inVerification = true;
      const rest = trimmed.replace(/^\-\s*Verification:\s*/, '').trim();
      if (rest) {
        output.push(`• ${rest.replace(/`/g, "'")}`);
      }
      continue;
    }

    if (!inVerification) continue;

    if (trimmed.startsWith('- **Learnings')) break;
    if (trimmed.startsWith('- Files')) break;
    if (trimmed.startsWith('- Files referenced')) break;
    if (/^\-\s+\*\*/.test(trimmed)) break;

    output.push(
      trimmed
        .replace(/^\-\s*/, '• ')
        .replace(/`/g, "'"),
    );
  }

  return output.slice(0, 6);
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

function buildHeartbeatMessage(runnerState, pendingStories, latest) {
  const nextStory = pendingStories[0] ?? null;
  const latestLabel = latest
    ? `${latest.storyId} — ${latest.title}`
    : '아직 완료 기록 없음';

  return [
    '⏱ Ralph 진행 중',
    '',
    `시작 시각: ${runnerState.startedAt || '기록 없음'}`,
    `최근 완료: ${latestLabel}`,
    `다음 대상: ${buildStoryLabel(nextStory)}`,
    `남은 PRD: ${pendingStories.length}건`,
  ].join('\n');
}

function buildProgressUpdateMessage(latest, pendingStories) {
  const nextStory = pendingStories[0] ?? null;
  const highlights = normalizeProgressBody(latest.section.lines).slice(0, 6);
  const verification = extractVerificationLines(latest.section.lines);

  const lines = [
    '📋 Ralph 완료 리포트',
    '',
    `완료 일자: ${latest.date}`,
    `완료 PRD: ${latest.storyId} — ${latest.title}`,
    '',
    '핵심 작업',
    ...highlights,
  ];

  if (verification.length > 0) {
    lines.push('', '검증', ...verification);
  }

  lines.push(
    '',
    `다음 대상: ${buildStoryLabel(nextStory)}`,
    `남은 PRD: ${pendingStories.length}건`,
  );

  return lines.join('\n');
}

function readRunnerLogTail(maxLines = 60) {
  if (!fs.existsSync(runnerLogPath)) return '';
  const lines = fs.readFileSync(runnerLogPath, 'utf8').split(/\r?\n/);
  return lines.slice(-maxLines).join('\n');
}

function buildRunnerStoppedMessage(runnerState, pendingStories, latest) {
  const logTail = readRunnerLogTail();
  const wasStoppedByBot = runnerState.stoppedBy === 'telegram-command-bot';
  const allCompleted = pendingStories.length === 0;
  const maxedOut = logTail.includes('Ralph reached max iterations');
  const completedAll = logTail.includes('Ralph completed all tasks!');

  let title = '⏹ Ralph 실행 종료';
  let detail = '워커가 종료되었습니다.';

  if (wasStoppedByBot) {
    title = '🛑 Ralph 실행 중지';
    detail = '텔레그램 명령으로 워커를 중지했습니다.';
  } else if (allCompleted || completedAll) {
    title = '🎉 Ralph 실행 완료';
    detail = '남아 있던 PRD를 모두 처리했습니다.';
  } else if (maxedOut) {
    title = '⚠️ Ralph 실행 일시 중지';
    detail = '최대 반복 수에 도달해 워커가 멈췄습니다.';
  }

  return [
    title,
    '',
    detail,
    latest ? `최근 완료: ${latest.storyId} — ${latest.title}` : '최근 완료: 기록 없음',
    pendingStories.length > 0
      ? `남은 PRD: ${pendingStories.length}건`
      : '남은 PRD: 0건',
  ].join('\n');
}

function createMonitorStateForRunner(pid) {
  const latest = findLatestProgressSection();

  return {
    runnerPid: pid,
    lastProgressKey: buildProgressKey(latest),
    lastHeartbeatAt: Date.now(),
    lastStopNotifiedPid: null,
  };
}

async function maybeNotifyRunnerUpdates() {
  const runnerState = readRunnerState();
  const monitorState = readMonitorState();
  const pid = Number.isInteger(runnerState.pid) ? runnerState.pid : null;
  const isRunning = pid != null && isProcessAlive(pid);
  const pendingStories = readPendingStories();
  const latest = findLatestProgressSection();
  const latestKey = buildProgressKey(latest);
  let changed = false;

  if (isRunning) {
    if (monitorState.runnerPid !== pid) {
      writeMonitorState(createMonitorStateForRunner(pid));
      return;
    }

    if (latestKey && latestKey !== monitorState.lastProgressKey) {
      await sendMessage(buildProgressUpdateMessage(latest, pendingStories));
      monitorState.lastProgressKey = latestKey;
      monitorState.lastHeartbeatAt = Date.now();
      changed = true;
    } else if (
      !monitorState.lastHeartbeatAt ||
      Date.now() - monitorState.lastHeartbeatAt >=
        CONFIG.heartbeatSeconds * 1000
    ) {
      await sendMessage(buildHeartbeatMessage(runnerState, pendingStories, latest));
      monitorState.lastHeartbeatAt = Date.now();
      changed = true;
    }
  } else if (
    pid != null &&
    monitorState.runnerPid === pid &&
    monitorState.lastStopNotifiedPid !== pid
  ) {
    await sendMessage(buildRunnerStoppedMessage(runnerState, pendingStories, latest));
    monitorState.lastStopNotifiedPid = pid;
    monitorState.lastHeartbeatAt = Date.now();
    changed = true;
  }

  if (changed) {
    writeMonitorState(monitorState);
  }
}

function buildHelpMessage() {
  const today = new Date().toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' });

  return [
    `🤖 ${today} 기준 Ralph PRD 명령`,
    '',
    '• 지금까지한 PRD 목록확인',
    '• 앞으로 해야할 PRD 목록 확인',
    '• 방금한 PRD 확인',
    '• 최신 요약 받기',
    '• 디자인 감사 받기',
    '• 계획 실행',
    '• 실행 상태 확인',
    '• 실행 중지',
    '',
    '자동 발권:',
    '• 📦 주문 메시지를 그대로 전달하면 자동 발권',
    '• /testorder — 테스트 주문으로 파이프라인 검증',
    '',
    '영문 슬래시 명령도 가능:',
    '• /done',
    '• /remaining',
    '• /latest',
    '• /summary',
    '• /design',
    '• /run',
    '• /runstatus',
    '• /stop',
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
  const summaryCommands = new Set([
    '/summary',
    '최신요약받기',
    '최신요약',
    '요약',
  ]);
  const designCommands = new Set([
    '/design',
    '디자인감사받기',
    '디자인감사',
    '디자인',
  ]);
  const runCommands = new Set([
    '/run',
    '/execute',
    '계획실행',
    '계획실행해줘',
    '실행해줘',
    '이계획실행해줘',
    '이계획받고실행해줘',
    '계획받고실행해줘',
  ]);
  const runStatusCommands = new Set([
    '/runstatus',
    '/status',
    '실행상태',
    '실행상태확인',
    '작업상태',
  ]);
  const stopCommands = new Set([
    '/stop',
    '실행중지',
    '중지',
    '멈춰',
  ]);

  if (helpCommands.has(normalized)) return 'help';
  if (doneCommands.has(normalized)) return 'done';
  if (remainingCommands.has(normalized)) return 'remaining';
  if (latestCommands.has(normalized)) return 'latest';
  if (summaryCommands.has(normalized)) return 'summary';
  if (designCommands.has(normalized)) return 'design';
  if (runCommands.has(normalized)) return 'run';
  if (runStatusCommands.has(normalized)) return 'runstatus';
  if (stopCommands.has(normalized)) return 'stop';
  return null;
}

async function handleMessage(message) {
  const chatId = String(message?.chat?.id ?? '');
  if (chatId !== CONFIG.chatId) {
    return;
  }

  const rawText = message.text || '';

  // 📦 주문 메시지 자동 감지
  if (rawText.includes('📦') && rawText.includes('주문번호:')) {
    await handleOrderMessage(rawText);
    return;
  }

  // /testorder 명령어
  if (rawText.trim().startsWith('/testorder')) {
    const args = rawText.trim().replace(/^\/testorder\s*/, '').trim();
    await handleTestOrder(args);
    return;
  }

  const command = resolveCommand(rawText);
  if (!command) {
    await sendMessage(
      [
        '알 수 없는 명령입니다.',
        '',
        '사용 가능한 명령:',
        '• 지금까지한 PRD 목록확인',
        '• 앞으로 해야할 PRD 목록 확인',
        '• 방금한 PRD 확인',
        '• 최신 요약 받기',
        '• 디자인 감사 받기',
        '• 계획 실행',
        '• 실행 상태 확인',
        '• 실행 중지',
        '• /testorder',
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
    return;
  }

  if (command === 'summary') {
    await sendMessage(
      buildDocumentMessage(summaryFilePath, '📌 최신 요약'),
    );
    return;
  }

  if (command === 'design') {
    await sendMessage(
      buildDocumentMessage(findLatestDesignAuditFile(), '🎨 디자인 감사'),
    );
    return;
  }

  if (command === 'run') {
    const result = startRalphRunner();
    if (!result.started) {
      await sendMessage(
        [
          '⚠️ Ralph 실행을 시작하지 못했습니다.',
          '',
          result.reason,
        ].join('\n'),
      );
      return;
    }

    await sendMessage(
      [
        '🚀 Ralph 실행 시작',
        '',
        `PID: ${result.pid}`,
        `남은 PRD: ${result.count}건`,
        `다음 대상: ${result.nextStory.id} — ${result.nextStory.title}`,
        `최대 반복: ${CONFIG.runIterations}`,
      ].join('\n'),
    );
    return;
  }

  if (command === 'runstatus') {
    await sendMessage(buildRunStatusMessage());
    return;
  }

  if (command === 'stop') {
    const result = stopRalphRunner();
    if (!result.stopped) {
      await sendMessage(
        [
          '⚠️ Ralph 실행 중지 실패',
          '',
          result.reason,
        ].join('\n'),
      );
      return;
    }

    await sendMessage(
      [
        '🛑 Ralph 실행 중지',
        '',
        `중지한 PID: ${result.pid}`,
      ].join('\n'),
    );
  }
}

async function registerCommands() {
  await telegramRequest('setMyCommands', {
    commands: [
      { command: 'done', description: '완료된 PRD 목록 확인' },
      { command: 'remaining', description: '앞으로 할 PRD 목록 확인' },
      { command: 'latest', description: '방금한 PRD 확인' },
      { command: 'summary', description: '최신 요약 받기' },
      { command: 'design', description: '디자인 감사 받기' },
      { command: 'run', description: '현재 계획 실행' },
      { command: 'runstatus', description: '실행 상태 확인' },
      { command: 'stop', description: '실행 중지' },
      { command: 'testorder', description: '테스트 주문으로 발권 파이프라인 검증' },
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
      await maybeNotifyRunnerUpdates();
    } catch (error) {
      log(`텔레그램 명령 폴링 오류: ${error.message}`);
      await delay(CONFIG.retryDelayMs);
    }
  }
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ============================================================
// 네이버 주문 자동 발권 파이프라인
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

  // 주문번호
  const orderMatch = text.match(/주문번호:\s*(\d+)/);
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
