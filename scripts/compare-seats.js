const XLSX = require("xlsx");

const args = process.argv.slice(2);
const file1 = args[0] || "좌석파싱/1_결과.xlsx";
const file2 = args[1] || "좌석파싱/2.xlsx";

function loadSheet(filePath) {
  const wb = XLSX.readFile(filePath);
  const ws = wb.Sheets["상품별좌석현황"] || wb.Sheets[wb.SheetNames[0]];
  const rows = XLSX.utils.sheet_to_json(ws);
  // Carry forward 좌석등급 from merged cells
  let lastGrade = "";
  for (const row of rows) {
    if (row["좌석등급"]) lastGrade = row["좌석등급"];
    else row["좌석등급"] = lastGrade;
  }
  return rows;
}

const d1 = loadSheet(file1);
const d2 = loadSheet(file2);

console.log("비교:", file1, "vs", file2);

const map1 = {};
for (const row of d1) {
  if (!row["열"] || row["열"] === "합계") continue;
  const key = row["좌석등급"] + "|" + row["층"] + "|" + row["열"];
  map1[key] = { seats: String(row["좌석번호"]), count: row["좌석수"] };
}

const map2 = {};
for (const row of d2) {
  if (!row["열"] || row["열"] === "합계") continue;
  const key = row["좌석등급"] + "|" + row["층"] + "|" + row["열"];
  map2[key] = { seats: String(row["좌석번호"]), count: row["좌석수"] };
}

console.log("=== 2.xlsx에만 있는 행 (누락) ===");
for (const [key, v] of Object.entries(map2)) {
  if (!map1[key]) {
    console.log("MISSING:", key, "좌석수:", v.count, "좌석:", v.seats.substring(0, 40));
  }
}

console.log("\n=== 좌석번호 다른 행 (상위 15개) ===");
let diffCount = 0;
for (const [key, v2] of Object.entries(map2)) {
  if (map1[key] && map1[key].seats !== v2.seats) {
    console.log("DIFF:", key);
    console.log("  결과:", map1[key].seats.substring(0, 60));
    console.log("  목표:", v2.seats.substring(0, 60));
    diffCount++;
    if (diffCount >= 15) break;
  }
}

console.log("\n=== 결과에만 있는 행 (잉여) ===");
for (const [key, v] of Object.entries(map1)) {
  if (!map2[key]) {
    console.log("EXTRA:", key, "좌석수:", v.count);
  }
}
