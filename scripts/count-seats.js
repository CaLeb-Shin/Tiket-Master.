const XLSX = require("xlsx");
const wb = XLSX.readFile("좌석파싱/2.xlsx");
const ws = wb.Sheets["상품별좌석현황"];
const data = XLSX.utils.sheet_to_json(ws);
let total = 0;
const stats = {};
for (const row of data) {
  const grade = row["좌석등급"];
  const rowLabel = row["열"];
  if (!grade || rowLabel === "합계") continue;
  const n = row["좌석수"] || 0;
  total += n;
  stats[grade] = (stats[grade] || 0) + n;
}
console.log("2.xlsx 총 좌석:", total);
console.log(stats);
