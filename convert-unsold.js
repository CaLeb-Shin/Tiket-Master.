const XLSX = require('xlsx');
const path = require('path');

const base = path.join(__dirname, '좌석파싱');
const inputFile = process.argv[2] || path.join(base, '잔여석_고양_20260419.xls');

const wb = XLSX.readFile(inputFile);
const sheet = wb.Sheets[wb.SheetNames[0]];
const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '' });

const data = rows.slice(1).filter(r => r.some(c => c !== ''));

// 열 컬럼 파싱: "A10열" → block=A, row=10 / "합창F1열" → block=합창F, row=1
function parseSectionRow(raw) {
  const m = raw.match(/^([A-Za-z가-힣]+?)(\d+)열$/);
  if (m) return { block: m[1], row: m[2] };
  const m2 = raw.match(/^([A-Za-z가-힣]+)열$/);
  if (m2) return { block: m2[1], row: '1' };
  const m3 = raw.match(/^(.+?구역)\s*(\d+)열?$/);
  if (m3) return { block: m3[1], row: m3[2] };
  return null;
}

function normalizeGrade(g) {
  return g.replace(/석$/, '').trim();
}

const expandedSeats = [];
let lastGrade = '';
let lastFloor = '';

for (const row of data) {
  const gradeRaw = String(row[3] || '').trim();
  if (gradeRaw && gradeRaw.includes('석')) lastGrade = gradeRaw;
  if (!lastGrade) continue;

  const floorRaw = String(row[4] || '').trim();
  if (floorRaw) lastFloor = floorRaw;

  const sectionRowRaw = String(row[5] || '').trim();
  if (!sectionRowRaw) continue;

  const parsed = parseSectionRow(sectionRowRaw);
  if (!parsed) {
    console.warn('파싱 실패:', sectionRowRaw);
    continue;
  }

  const seatsRaw = String(row[7] || '').trim();
  if (!seatsRaw) continue;

  const seatNums = seatsRaw.split(/[\s,]+/).filter(s => s.trim() !== '' && !isNaN(parseInt(s.trim())));

  for (const num of seatNums) {
    expandedSeats.push({
      block: parsed.block,
      floor: lastFloor,
      row: parsed.row,
      number: parseInt(num),
      grade: normalizeGrade(lastGrade),
    });
  }
}

// 등급별 통계
const grades = {};
for (const s of expandedSeats) {
  grades[s.grade] = (grades[s.grade] || 0) + 1;
}

console.log('총 좌석:', expandedSeats.length);
console.log('등급별:', grades);

// 어드민 파서가 이해하는 리스트 형식으로 출력
const header = ['구역', '층', '열', '번호', '등급'];
const outRows = expandedSeats.map(s => [s.block, s.floor, s.row, s.number, s.grade]);

const newWb = XLSX.utils.book_new();
const newSheet = XLSX.utils.aoa_to_sheet([header, ...outRows]);
XLSX.utils.book_append_sheet(newWb, newSheet, 'Sheet1');

const ext = path.extname(inputFile);
const baseName = path.basename(inputFile, ext);
const outPath = path.join(path.dirname(inputFile), `${baseName}_변환.xlsx`);
XLSX.writeFile(newWb, outPath);
console.log('저장:', outPath);

// 샘플 출력
console.log('\n=== 샘플 (seatKey 형식) ===');
expandedSeats.slice(0, 5).forEach(s => {
  console.log(`  ${s.block}-${s.floor}-${s.row}-${s.number} (${s.grade})`);
});
