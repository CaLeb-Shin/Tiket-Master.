#!/usr/bin/env node

const fs = require('fs');
const https = require('https');
const path = require('path');

const progressPath = path.join(__dirname, 'progress.txt');

function parseArgs(argv) {
  const options = {
    dryRun: false,
    filePath: null,
    storyId: null,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];

    if (arg === '--dry-run') {
      options.dryRun = true;
      continue;
    }

    if (arg === '--file') {
      const next = argv[i + 1];
      if (!next) {
        throw new Error('--file 다음에 전송할 파일 경로를 넣어야 합니다');
      }
      options.filePath = next;
      i += 1;
      continue;
    }

    if (!options.storyId) {
      options.storyId = arg;
      continue;
    }

    throw new Error(`알 수 없는 인자: ${arg}`);
  }

  return options;
}

function readProgress() {
  return fs.readFileSync(progressPath, 'utf8');
}

function readCustomFile(filePath) {
  const resolved = path.isAbsolute(filePath)
    ? filePath
    : path.resolve(process.cwd(), filePath);

  if (!fs.existsSync(resolved)) {
    throw new Error(`전송할 파일을 찾지 못했습니다: ${resolved}`);
  }

  return {
    resolved,
    body: fs.readFileSync(resolved, 'utf8'),
  };
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

function parseSections(markdown) {
  const lines = markdown.split(/\r?\n/);
  const sections = [];
  let current = null;

  for (const line of lines) {
    if (line.startsWith('## ')) {
      if (current) sections.push(current);
      current = { heading: line.trim(), lines: [] };
      continue;
    }

    if (!current) continue;
    current.lines.push(line);
  }

  if (current) sections.push(current);
  return sections;
}

function findSection(sections, storyId) {
  if (!storyId) {
    return sections.at(-1) ?? null;
  }

  for (let i = sections.length - 1; i >= 0; i -= 1) {
    if (sections[i].heading.includes(storyId)) {
      return sections[i];
    }
  }

  return null;
}

function normalizeBody(lines) {
  const body = [];

  for (const rawLine of lines) {
    const line = rawLine.trimEnd();
    if (line === '---') break;
    if (!line.trim()) continue;

    body.push(
      line
        .replace(/^\s*-\s*/, '• ')
        .replace(/^\s+\-\s*/, '  - ')
        .replace(/\*\*/g, '')
        .replace(/`/g, "'"),
    );
  }

  return body.join('\n').trim();
}

function buildMessage(section) {
  const heading = section.heading.replace(/^##\s*/, '').trim();
  const body = normalizeBody(section.lines);

  return [
    '[Codex Ralph Summary]',
    heading,
    '',
    body,
  ].join('\n').trim();
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

function buildFileMessage(filePath, body) {
  const heading = extractDocumentTitle(filePath, body);
  const normalized = normalizeMarkdownDocument(body);

  return [
    '[Codex Ralph Summary]',
    heading,
    '',
    normalized,
  ].join('\n').trim();
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

function telegramRequest(botToken, method, body) {
  const data = JSON.stringify(body);

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'api.telegram.org',
        path: `/bot${botToken}/${method}`,
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
    req.write(data);
    req.end();
  });
}

async function main() {
  const { storyId, dryRun, filePath } = parseArgs(process.argv);

  const botToken =
    process.env.RALPH_TELEGRAM_BOT_TOKEN ||
    process.env.NAVER_SEAT_BOT_TOKEN ||
    process.env.TELEGRAM_BOT_TOKEN;
  const chatId =
    process.env.RALPH_TELEGRAM_CHAT_ID ||
    process.env.NAVER_SEAT_CHAT_ID ||
    process.env.TELEGRAM_CHAT_ID;

  let chunks;

  if (filePath) {
    const customFile = readCustomFile(filePath);
    if (!customFile.body.trim()) {
      throw new Error(`전송할 파일이 비어 있습니다: ${customFile.resolved}`);
    }
    chunks = splitMessage(buildFileMessage(customFile.resolved, customFile.body));
  } else {
    const progress = readProgress();
    const section = findSection(parseSections(progress), storyId);

    if (!section) {
      throw new Error(
        storyId
          ? `progress.txt에서 ${storyId} 섹션을 찾지 못했습니다`
          : 'progress.txt에서 전송할 섹션을 찾지 못했습니다',
      );
    }

    chunks = splitMessage(buildMessage(section));
  }

  if (dryRun) {
    process.stdout.write(chunks.join('\n\n--- chunk ---\n\n'));
    return;
  }

  if (!botToken || !chatId) {
    process.stdout.write(
      'SKIP: Telegram env vars not configured (need bot token and chat id)\n',
    );
    return;
  }

  for (const chunk of chunks) {
    await telegramRequest(botToken, 'sendMessage', {
      chat_id: chatId,
      text: chunk,
    });
  }

  process.stdout.write(
    `SENT: Telegram summary delivered${storyId ? ` for ${storyId}` : ''}\n`,
  );
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
