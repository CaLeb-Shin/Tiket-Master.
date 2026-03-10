#!/usr/bin/env node
/**
 * 좌석배치도 엑셀 → 상품별좌석현황 변환 파서
 *
 * Usage: node scripts/seat-parser.js <input.xlsx> [output.xlsx]
 */

const XLSX = require("xlsx");
const path = require("path");

// ─────────────────────────────────────────────────
// 색상 유틸
// ─────────────────────────────────────────────────

function hexToHSL(hex) {
  const r = parseInt(hex.substring(0, 2), 16) / 255;
  const g = parseInt(hex.substring(2, 4), 16) / 255;
  const b = parseInt(hex.substring(4, 6), 16) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h, s, l = (max + min) / 2;
  if (max === min) {
    h = s = 0;
  } else {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
      case g: h = ((b - r) / d + 2) / 6; break;
      case b: h = ((r - g) / d + 4) / 6; break;
    }
  }
  return { h: h * 360, s: s * 100, l: l * 100 };
}

// ─────────────────────────────────────────────────
// 범례에서 색상 → 등급 매핑 추출
// ─────────────────────────────────────────────────

function extractLegend(ws, maxRow, maxCol) {
  const legend = {}; // rgb → gradeName (e.g., "VIP석")

  // 범례는 보통 오른쪽 끝 열에 "VIP석", "R석" 등으로 표시됨
  for (let r = 0; r <= maxRow; r++) {
    for (let c = maxCol - 5; c <= maxCol; c++) {
      const addr = XLSX.utils.encode_cell({ r, c });
      const cell = ws[addr];
      if (!cell || !cell.v) continue;
      const val = String(cell.v).trim();

      // 등급명 패턴: "VIP석", "R석", "S석", "A석", "시야방해R석", "시야방해S석"
      const gradeMatch = val.match(/^(VIP|시야방해[RS]|[RSAB])석$/);
      if (!gradeMatch) continue;

      // 이 셀의 배경색 가져오기
      const fg = cell.s?.fgColor;
      if (fg?.rgb) {
        legend[fg.rgb] = val;
        console.log(`   범례: #${fg.rgb} → ${val}`);
      }
    }
  }

  return legend;
}

// ─────────────────────────────────────────────────
// 그리드 구조 파싱
// ─────────────────────────────────────────────────

function getCell(ws, r, c) {
  const addr = XLSX.utils.encode_cell({ r, c });
  return ws[addr] || null;
}

function getVal(ws, r, c) {
  const cell = getCell(ws, r, c);
  if (!cell || cell.v == null) return null;
  return String(cell.v).trim();
}

function getRGB(ws, r, c) {
  const cell = getCell(ws, r, c);
  if (!cell || !cell.s) return null;
  return cell.s.fgColor?.rgb || null;
}

function findBlockHeaders(ws, maxRow, maxCol) {
  // 블록 헤더를 찾아서 층별로 그룹핑
  const floors = [];

  for (let r = 0; r <= maxRow; r++) {
    const blocks = [];
    for (let c = 0; c <= maxCol; c++) {
      const val = getVal(ws, r, c);
      if (!val) continue;
      const m = val.replace(/\s+/g, "").match(/([A-Z])블록\((\d+)\)/);
      if (m) {
        blocks.push({
          name: m[1] + "블록",
          capacity: parseInt(m[2]),
          headerCol: c,
          headerRow: r,
        });
      }
    }
    if (blocks.length >= 3) {
      // 이 행이 블록 헤더 행
      // 층 이름 찾기 — 같은 행 또는 근처 행에서 "1층", "2층" 등
      let floorName = null;
      // 첫 번째 데이터 행에서 층 텍스트 찾기
      for (let c2 = maxCol - 5; c2 <= maxCol; c2++) {
        for (let r2 = r; r2 <= Math.min(r + 3, maxRow); r2++) {
          const v = getVal(ws, r2, c2);
          if (v && /^\d층$/.test(v)) {
            floorName = v;
            break;
          }
        }
        if (floorName) break;
      }
      // 위쪽에서도 찾기 (Row 0 등)
      if (!floorName) {
        for (let c2 = 0; c2 <= maxCol; c2++) {
          const v = getVal(ws, 0, c2);
          if (v && v.includes("층")) {
            // 이전 floor이 있으면 다음 층
            floorName = floors.length === 0 ? "1층" : `${floors.length + 1}층`;
            break;
          }
        }
      }
      if (!floorName) floorName = `${floors.length + 1}층`;

      floors.push({ name: floorName, blocks, headerRow: r });
    }
  }

  return floors;
}

function determineBlockColumns(ws, floor, maxCol, maxRow) {
  const headerRow = floor.headerRow;
  const blocks = floor.blocks;

  // 1. 헤더 행에서 "열" 열 위치 모두 찾기
  const rowNumCols = [];
  for (let c = 0; c <= maxCol; c++) {
    const hdr = getVal(ws, headerRow, c);
    if (hdr === "열") rowNumCols.push(c);
  }

  // 2. 각 블록의 열 번호 열 할당
  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i];

    // "열" 헤더가 블록 바로 앞에 있는지 확인
    let rowNumCol = -1;
    for (const rc of rowNumCols) {
      if (rc < block.headerCol && rc >= (blocks[i - 1]?.headerCol ?? 0)) {
        rowNumCol = rc;
      }
    }

    // "열" 헤더 없으면 데이터에서 열번호 열 찾기 (앞쪽 확인)
    if (rowNumCol < 0) {
      for (let c = block.headerCol - 1; c >= Math.max(0, block.headerCol - 3); c--) {
        const v1 = getVal(ws, headerRow + 1, c);
        const v2 = getVal(ws, headerRow + 2, c);
        if (v1 === "1" && v2 === "2") {
          rowNumCol = c;
          break;
        }
      }
    }

    // 앞쪽에서 못 찾으면 블록 헤더 뒤쪽 확인 (2층 패턴: 헤더 뒤에 열번호)
    if (rowNumCol < 0) {
      const nextBlock = blocks[i + 1];
      const maxSearch = nextBlock ? nextBlock.headerCol : Math.min(block.headerCol + 15, maxCol);
      for (let c = block.headerCol + 1; c < maxSearch; c++) {
        const v1 = getVal(ws, headerRow + 1, c);
        const v2 = getVal(ws, headerRow + 2, c);
        const rgb1 = getRGB(ws, headerRow + 1, c);
        // 열번호 열은 배경색이 없고 1,2,3 순차 증가
        if (v1 === "1" && v2 === "2" && !rgb1) {
          rowNumCol = c;
          break;
        }
      }
    }

    // 첫 블록이면 B열
    if (rowNumCol < 0 && i === 0) rowNumCol = 1;

    block.rowNumCol = rowNumCol;
  }

  // 3. 좌석 시작/끝 열 결정
  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i];
    const nextBlock = blocks[i + 1];

    // 좌석 시작: rowNumCol + 1 (열번호 열 다음이 좌석 시작)
    let seatStart;
    if (block.rowNumCol >= 0) {
      seatStart = block.rowNumCol + 1;
    } else {
      seatStart = block.headerCol;
    }

    // 좌석 끝: 다음 블록의 열번호 열 - 1, 또는 없으면 데이터가 있는 마지막 열
    let seatEnd;
    if (nextBlock && nextBlock.rowNumCol >= 0) {
      seatEnd = nextBlock.rowNumCol - 1;
    } else if (nextBlock) {
      seatEnd = nextBlock.headerCol - 2;
    } else {
      // 마지막 블록 — 좌석 데이터 마지막 열 찾기
      // "열" 열이 아닌 좌석 데이터 열만
      seatEnd = seatStart;
      for (let c = seatStart; c <= maxCol; c++) {
        // 이 열이 행 번호 열인지 확인 (모든 값이 순차적이면 행 번호)
        let isSeatCol = false;
        let maxSeatVal = 0;
        for (let r = headerRow + 1; r <= Math.min(headerRow + 25, maxRow); r++) {
          const val = getVal(ws, r, c);
          const rgb = getRGB(ws, r, c);
          if (val && /^\d+$/.test(val) && rgb) {
            isSeatCol = true;
            maxSeatVal = Math.max(maxSeatVal, parseInt(val));
          }
        }
        if (isSeatCol && maxSeatVal > 1) seatEnd = c;
        else if (!isSeatCol && c > seatStart + 2) break;
      }
    }

    block.seatStartCol = seatStart;
    block.seatEndCol = seatEnd;

    console.log(`     ${block.name}: 좌석 col ${XLSX.utils.encode_col(seatStart)}-${XLSX.utils.encode_col(seatEnd)}, 열번호 col ${XLSX.utils.encode_col(block.rowNumCol)}`);
  }
}

// ─────────────────────────────────────────────────
// 좌석 추출
// ─────────────────────────────────────────────────

function extractSeats(ws, floors, legend, maxRow) {
  const allSeats = [];

  for (let fi = 0; fi < floors.length; fi++) {
    const floor = floors[fi];
    const nextFloor = floors[fi + 1];
    const dataStart = floor.headerRow + 1;
    const dataEnd = nextFloor ? nextFloor.headerRow - 2 : maxRow;

    for (const block of floor.blocks) {
      for (let r = dataStart; r <= dataEnd; r++) {
        // 열 번호 가져오기
        const rowNum = getVal(ws, r, block.rowNumCol);
        if (!rowNum || !/^\d+$/.test(rowNum)) continue;

        for (let c = block.seatStartCol; c <= block.seatEndCol; c++) {
          // 열번호 열은 건너뛰기
          if (c === block.rowNumCol) continue;
          const seatNum = getVal(ws, r, c);
          if (!seatNum || !/^\d+$/.test(seatNum)) continue;

          const rgb = getRGB(ws, r, c);
          let grade = null;

          // 1순위: 범례에서 매칭
          if (rgb && legend[rgb]) {
            grade = legend[rgb];
          }

          // 2순위: HSL 색조 기반 추정
          if (!grade && rgb) {
            grade = classifyByHSL(rgb);
          }

          if (!grade) continue; // 색상 없는 셀은 무시

          allSeats.push({
            floor: floor.name,
            block: block.name,
            row: parseInt(rowNum),
            seatNum: parseInt(seatNum),
            grade,
            rgb,
          });
        }
      }
    }
  }

  return allSeats;
}

function classifyByHSL(hex) {
  if (!hex || hex.length !== 6) return null;
  const { h, s, l } = hexToHSL(hex);

  if (l < 20) return null; // 미판매 (검정)
  if (s < 10 && l < 60) return null; // 회색
  if (l > 90) return null; // 흰색
  if (s < 10 && l > 70) return null; // 연한 회색

  // HSL 색조 분류 (fallback)
  // 빨강/핑크/살몬: VIP석
  if ((h >= 345 || h < 40) && s > 15) return "VIP석";
  // 노랑: A석
  if (h >= 40 && h < 70 && s > 15) return "A석";
  // 초록: S석
  if (h >= 70 && h < 170 && s > 15) return "S석";
  // 파랑: R석
  if (h >= 170 && h < 260 && s > 15) return "R석";
  // 보라: 시야방해R석
  if (h >= 260 && h < 345 && s > 15) return "시야방해R석";

  return null;
}

/**
 * 색상 분포 분석 후 자동 매핑 생성
 * 좌석 색상들을 수집해서 범례와 매칭
 */
function buildColorMapping(ws, floors, maxRow) {
  // 모든 좌석 셀의 RGB 수집
  const colorCounts = {};
  for (const floor of floors) {
    const nextFloor = floors[floors.indexOf(floor) + 1];
    const dataEnd = nextFloor ? nextFloor.headerRow - 2 : maxRow;
    for (const block of floor.blocks) {
      for (let r = block.headerRow + 1; r <= dataEnd; r++) {
        for (let c = block.seatStartCol; c <= block.seatEndCol; c++) {
          const val = getVal(ws, r, c);
          if (!val || !/^\d+$/.test(val)) continue;
          const rgb = getRGB(ws, r, c);
          if (!rgb) continue;
          const { h, s, l } = hexToHSL(rgb);
          if (l < 20 || l > 90 || (s < 10 && l > 70) || (s < 10 && l < 60)) continue;
          if (!colorCounts[rgb]) colorCounts[rgb] = { count: 0, h, s, l, floor: floor.name };
          colorCounts[rgb].count++;
        }
      }
    }
  }

  // 색상별 HSL 분류 후 범례 순서에 따라 매핑
  const mapping = {};
  for (const [rgb, info] of Object.entries(colorCounts)) {
    const grade = classifyByHSL(rgb);
    if (grade) mapping[rgb] = grade;
  }

  // 밝은 초록(#00B050 같은) 은 시야방해S석으로 매핑
  // — 일반 S석(연한 초록)과 구별
  const greenColors = Object.entries(colorCounts)
    .filter(([_, info]) => info.h >= 70 && info.h < 170 && info.s > 15)
    .sort((a, b) => b[1].count - a[1].count);

  if (greenColors.length >= 2) {
    // 가장 많은 게 S석, 적은 게 시야방해S석
    for (let i = 0; i < greenColors.length; i++) {
      const [rgb, info] = greenColors[i];
      if (i === 0) mapping[rgb] = "S석";
      else mapping[rgb] = "시야방해S석";
    }
  }

  return mapping;
}

// ─────────────────────────────────────────────────
// 출력 생성
// ─────────────────────────────────────────────────

function generateOutput(seats, outputPath) {
  const gradeOrder = ["VIP석", "R석", "시야방해R석", "S석", "시야방해S석", "A석"];
  const blockOrder = "ABCDEFGHIJ".split("");

  // 블록+열 기준 그룹핑
  const groups = {};
  for (const seat of seats) {
    const key = `${seat.grade}|${seat.floor}|${seat.block}${seat.row}열`;
    if (!groups[key]) {
      groups[key] = {
        grade: seat.grade,
        floor: seat.floor,
        block: seat.block,
        row: seat.row,
        rowLabel: `${seat.block}${seat.row}열`,
        seatNums: [],
      };
    }
    groups[key].seatNums.push(seat.seatNum);
  }

  for (const g of Object.values(groups)) {
    g.seatNums.sort((a, b) => a - b);
  }

  // 정렬: 등급 → 층 → 블록 → 열
  const sorted = Object.values(groups).sort((a, b) => {
    const gi = gradeOrder.indexOf(a.grade) - gradeOrder.indexOf(b.grade);
    if (gi !== 0) return gi;
    const fi = a.floor.localeCompare(b.floor);
    if (fi !== 0) return fi;
    const bi = blockOrder.indexOf(a.block[0]) - blockOrder.indexOf(b.block[0]);
    if (bi !== 0) return bi;
    return a.row - b.row;
  });

  // 엑셀 생성
  const rows = [["No", "이용(관람)일", "회차", "좌석등급", "층", "열", "좌석수", "좌석번호"]];
  let no = 1;
  let totalSeats = 0;
  for (const g of sorted) {
    rows.push([
      no++,
      "",
      "",
      g.grade,
      g.floor,
      g.rowLabel,
      g.seatNums.length,
      g.seatNums.join(" "),
    ]);
    totalSeats += g.seatNums.length;
  }
  rows.push(["", "", "", "", "", "합계", totalSeats, ""]);

  const newWs = XLSX.utils.aoa_to_sheet(rows);
  const newWb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(newWb, newWs, "상품별좌석현황");

  newWs["!cols"] = [
    { wch: 5 }, { wch: 12 }, { wch: 12 }, { wch: 12 },
    { wch: 5 }, { wch: 12 }, { wch: 7 }, { wch: 50 },
  ];

  XLSX.writeFile(newWb, outputPath);

  // 통계
  console.log(`\n✅ 출력: ${path.basename(outputPath)}`);
  console.log(`   ${sorted.length}행, ${totalSeats}석`);
  console.log("\n📋 등급별:");
  const stats = {};
  for (const g of sorted) {
    if (!stats[g.grade]) stats[g.grade] = 0;
    stats[g.grade] += g.seatNums.length;
  }
  for (const grade of gradeOrder) {
    if (stats[grade]) console.log(`   ${grade}: ${stats[grade]}석`);
  }
  // 범례에 없는 등급도 표시
  for (const [grade, count] of Object.entries(stats)) {
    if (!gradeOrder.includes(grade)) console.log(`   ${grade}: ${count}석 (미분류)`);
  }
}

// ─────────────────────────────────────────────────
// "열" 기반 형식 파싱 (대전/광주 등)
// ─────────────────────────────────────────────────

function parseRowFormat(ws, maxRow, maxCol, legend) {
  // "X열" 라벨 행을 찾아서 열 그룹 구성
  // 층 구분은 오른쪽 끝 열에 "1층", "2층", "3층" 텍스트로 판단
  const allSeats = [];

  // 1단계: 층 마커 찾기
  // 방법1: 오른쪽 열(col 40+)에 "N층" 텍스트 → 해당 층의 END 마커
  // 방법2: 데이터 영역에서 "N층 NNN석" → 해당 층의 START 마커
  const floorEndMarkers = []; // {row, floorNum}
  const floorStartMarkers = []; // {row, floorNum}
  for (let r = 0; r <= maxRow; r++) {
    for (let c = 0; c <= maxCol; c++) {
      const val = getVal(ws, r, c);
      if (!val) continue;
      const fm = val.match(/^(\d)층$/);
      if (fm && c >= 40) {
        // 오른쪽 영역의 "N층" = END 마커
        floorEndMarkers.push({ row: r, floorNum: parseInt(fm[1]) });
      }
      const fm2 = val.match(/^(\d)층\s+\d+석$/);
      if (fm2 && c >= 40) {
        // "N층 NNN석" = 요약 정보 (무시)
      }
    }
  }
  floorEndMarkers.sort((a, b) => a.row - b.row);

  // END 마커에서 층 범위 결정: "N층" 마커 이후는 (N+1)층
  // 기본: 1층
  const floorRanges = []; // {startRow, endRow, name}
  let prevEnd = 0;
  for (const marker of floorEndMarkers) {
    floorRanges.push({
      startRow: prevEnd,
      endRow: marker.row,
      name: marker.floorNum + "층",
    });
    prevEnd = marker.row + 1;
  }
  // 마지막 마커 이후 남은 행이 있으면 추가
  if (prevEnd <= maxRow && floorEndMarkers.length > 0) {
    const lastFloor = floorEndMarkers[floorEndMarkers.length - 1].floorNum + 1;
    // 실제로 더 이상 없을 수 있으므로 남은 행 무시
  }
  // 마커가 없으면 전체를 1층으로
  if (floorRanges.length === 0) {
    floorRanges.push({ startRow: 0, endRow: maxRow, name: "1층" });
  }

  console.log(`   층 범위: ${floorRanges.map(f => f.name + " (row " + f.startRow + "-" + f.endRow + ")").join(", ")}`);

  // 2단계: "X열" 라벨 찾기
  const rowGroups = []; // {name, labelRow, labelCol, floor}
  for (let r = 0; r <= maxRow; r++) {
    for (let c = 0; c <= maxCol; c++) {
      const val = getVal(ws, r, c);
      if (!val) continue;
      // "O열", "A열", "B열" 등
      const m = val.match(/^([A-Z])열$/);
      if (m) {
        // 이 열 그룹이 어느 층에 속하는지 (층 범위에서 확인)
        let floorName = "1층";
        for (const fr of floorRanges) {
          if (r >= fr.startRow && r <= fr.endRow) {
            floorName = fr.name;
            break;
          }
        }
        rowGroups.push({
          name: m[1] + "열",
          labelRow: r,
          labelCol: c,
          floor: floorName,
        });
      }
    }
  }

  if (rowGroups.length === 0) return [];

  console.log(`   열 그룹 ${rowGroups.length}개: ${rowGroups.map(g => g.floor + " " + g.name).join(", ")}`);

  // 3단계: 같은 라벨 행에 있는 열 그룹끼리 묶기
  const labelRows = {};
  for (const rg of rowGroups) {
    const key = rg.labelRow;
    if (!labelRows[key]) labelRows[key] = [];
    labelRows[key].push(rg);
  }

  // 4단계: 각 열 그룹의 좌석 범위 결정
  for (const [labelRowStr, groups] of Object.entries(labelRows)) {
    const labelRow = parseInt(labelRowStr);
    groups.sort((a, b) => a.labelCol - b.labelCol);

    // 좌석 데이터가 시작되는 행 (라벨 행 + 1~3 아래)
    let dataStartRow = labelRow + 1;
    for (let r = labelRow + 1; r <= Math.min(labelRow + 5, maxRow); r++) {
      let hasSeats = false;
      for (let c = 0; c <= maxCol; c++) {
        const val = getVal(ws, r, c);
        const rgb = getRGB(ws, r, c);
        if (val && /^\d+$/.test(val) && rgb) {
          hasSeats = true;
          break;
        }
      }
      if (hasSeats) { dataStartRow = r; break; }
    }

    // 좌석 데이터 끝 행 (다음 라벨 행 전, 또는 빈 행)
    const allLabelRows = Object.keys(labelRows).map(Number).sort((a, b) => a - b);
    const nextLabelIdx = allLabelRows.indexOf(labelRow) + 1;
    const dataEndRow = nextLabelIdx < allLabelRows.length
      ? allLabelRows[nextLabelIdx] - 2
      : maxRow;

    for (let gi = 0; gi < groups.length; gi++) {
      const group = groups[gi];
      const nextGroup = groups[gi + 1];

      // 좌석 열 범위: 라벨 열부터 다음 그룹 라벨 전까지
      // 여러 데이터 행에서 좌석이 있는 가장 넓은 범위 찾기
      let minSeatCol = maxCol;
      let maxSeatCol = 0;

      const endSearchCol = nextGroup ? nextGroup.labelCol - 1 : maxCol;

      for (let r = dataStartRow; r <= dataEndRow; r++) {
        for (let c = group.labelCol; c <= endSearchCol; c++) {
          const val = getVal(ws, r, c);
          const rgb = getRGB(ws, r, c);
          if (val && /^\d+$/.test(val) && rgb) {
            if (c < minSeatCol) minSeatCol = c;
            if (c > maxSeatCol) maxSeatCol = c;
          }
        }
      }

      if (minSeatCol > maxSeatCol) continue;

      // 좌석 추출
      for (let r = dataStartRow; r <= dataEndRow; r++) {
        const rowSeats = [];
        for (let c = minSeatCol; c <= maxSeatCol; c++) {
          const val = getVal(ws, r, c);
          if (!val || !/^\d+$/.test(val)) continue;
          const rgb = getRGB(ws, r, c);
          let grade = null;
          if (rgb && legend[rgb]) grade = legend[rgb];
          if (!grade && rgb) grade = classifyByHSL(rgb);
          if (!grade) continue;

          // 유보석은 건너뛰기
          if (grade === "유보석" || grade === "장애인석") continue;

          rowSeats.push({
            floor: group.floor,
            block: group.name, // "열" 이름을 block으로 사용
            row: 0, // 열 형식에서는 별도 행 번호 없음
            seatNum: parseInt(val),
            grade,
            rgb,
          });
        }

        // 행이 있으면 추가 (row 번호는 좌석 번호 범위로 구분)
        allSeats.push(...rowSeats);
      }
    }
  }

  return allSeats;
}

// ─────────────────────────────────────────────────
// "열" 형식 출력 — 좌석을 블록(열)+등급별로 그룹핑
// ─────────────────────────────────────────────────

function generateRowFormatOutput(seats, outputPath) {
  const gradeOrder = ["VIP석", "R석", "S석", "A석"];

  // 등급 + 층 + 열 기준 그룹핑
  const groups = {};
  for (const seat of seats) {
    const key = `${seat.grade}|${seat.floor}|${seat.block}`;
    if (!groups[key]) {
      groups[key] = {
        grade: seat.grade,
        floor: seat.floor,
        rowLabel: seat.block,
        seatNums: new Set(),
      };
    }
    groups[key].seatNums.add(seat.seatNum);
  }

  // Set → sorted Array
  for (const g of Object.values(groups)) {
    g.seatNums = [...g.seatNums].sort((a, b) => a - b);
  }

  const rowLetterOrder = "OABCDEFGHIJKLMN".split("");
  const sorted = Object.values(groups).sort((a, b) => {
    const gi = gradeOrder.indexOf(a.grade) - gradeOrder.indexOf(b.grade);
    if (gi !== 0) return gi;
    const fi = a.floor.localeCompare(b.floor);
    if (fi !== 0) return fi;
    const aIdx = rowLetterOrder.indexOf(a.rowLabel[0]);
    const bIdx = rowLetterOrder.indexOf(b.rowLabel[0]);
    return aIdx - bIdx;
  });

  const rows = [["No", "이용(관람)일", "회차", "좌석등급", "층", "열", "좌석수", "좌석번호"]];
  let no = 1;
  let totalSeats = 0;
  for (const g of sorted) {
    rows.push([
      no++, "", "", g.grade, g.floor, g.rowLabel,
      g.seatNums.length, g.seatNums.join(" "),
    ]);
    totalSeats += g.seatNums.length;
  }
  rows.push(["", "", "", "", "", "합계", totalSeats, ""]);

  const newWs = XLSX.utils.aoa_to_sheet(rows);
  const newWb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(newWb, newWs, "상품별좌석현황");
  newWs["!cols"] = [
    { wch: 5 }, { wch: 12 }, { wch: 12 }, { wch: 12 },
    { wch: 5 }, { wch: 8 }, { wch: 7 }, { wch: 80 },
  ];
  XLSX.writeFile(newWb, outputPath);

  console.log(`\n✅ 출력: ${path.basename(outputPath)}`);
  console.log(`   ${sorted.length}행, ${totalSeats}석`);
  console.log("\n📋 등급별:");
  const stats = {};
  for (const g of sorted) {
    if (!stats[g.grade]) stats[g.grade] = 0;
    stats[g.grade] += g.seatNums.length;
  }
  for (const grade of gradeOrder) {
    if (stats[grade]) console.log(`   ${grade}: ${stats[grade]}석`);
  }
  for (const [grade, count] of Object.entries(stats)) {
    if (!gradeOrder.includes(grade)) console.log(`   ${grade}: ${count}석 (미분류)`);
  }
}

// ─────────────────────────────────────────────────
// 메인
// ─────────────────────────────────────────────────

function main() {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    console.log("Usage: node seat-parser.js <input.xlsx> [output.xlsx]");
    process.exit(1);
  }

  const inputPath = args[0];
  const outputPath = args[1] || inputPath.replace(/\.(xlsx?|xls)$/i, "_좌석현황.xlsx");

  const wb = XLSX.readFile(inputPath, { cellStyles: true });
  const ws = wb.Sheets[wb.SheetNames[0]];
  const range = XLSX.utils.decode_range(ws["!ref"]);
  const maxRow = range.e.r;
  const maxCol = range.e.c;

  console.log(`📊 ${path.basename(inputPath)}: ${maxRow + 1}행 × ${maxCol + 1}열\n`);

  // 1. 범례 추출
  console.log("🎨 범례:");
  const legend = extractLegend(ws, maxRow, maxCol);
  if (Object.keys(legend).length === 0) {
    console.log("   (범례 없음 — HSL 색조 기반 분류 사용)");
  }

  // 2. 블록 구조 파싱 시도
  console.log("\n🏢 구조 감지:");
  const floors = findBlockHeaders(ws, maxRow, maxCol);

  if (floors.length > 0) {
    // ── 블록 형식 (부산 등) ──
    console.log("   형식: 블록 기반");
    for (const floor of floors) {
      console.log(`   ${floor.name}: ${floor.blocks.map(b => b.name).join(", ")}`);
      determineBlockColumns(ws, floor, maxCol, maxRow);
    }

    const colorMapping = buildColorMapping(ws, floors, maxRow);
    console.log("\n🎨 색상 매핑:");
    for (const [rgb, grade] of Object.entries(colorMapping)) {
      console.log(`   #${rgb} → ${grade}`);
    }

    const effectiveLegend = Object.keys(legend).length > 0 ? legend : colorMapping;
    const seats = extractSeats(ws, floors, effectiveLegend, maxRow);
    if (seats.length === 0) {
      console.error("❌ 좌석을 찾을 수 없습니다.");
      process.exit(1);
    }
    generateOutput(seats, outputPath);
  } else {
    // ── 열 형식 (대전/광주 등) ──
    console.log("   형식: 열 기반");

    // 범례 + HSL 분류 합치기
    const effectiveLegend = { ...legend };

    // 유보석, 장애인석 색상 추가 (제외용)
    for (let r = 0; r <= maxRow; r++) {
      for (let c = 0; c <= maxCol; c++) {
        const val = getVal(ws, r, c);
        if (!val) continue;
        if (val.includes("유보석")) {
          // 이 셀의 색상을 유보석으로 등록
          const rgb = getRGB(ws, r, c);
          if (rgb) effectiveLegend[rgb] = "유보석";
        }
        if (val.includes("장애인")) {
          const rgb = getRGB(ws, r, c);
          if (rgb) effectiveLegend[rgb] = "장애인석";
        }
      }
    }

    const seats = parseRowFormat(ws, maxRow, maxCol, effectiveLegend);
    if (seats.length === 0) {
      console.error("❌ 좌석을 찾을 수 없습니다.");
      process.exit(1);
    }
    generateRowFormatOutput(seats, outputPath);
  }
}

main();
