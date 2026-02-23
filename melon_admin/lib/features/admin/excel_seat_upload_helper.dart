import 'dart:convert';
import 'dart:math' as math;

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:melon_core/data/models/venue.dart';

import 'dart:html' if (dart.library.io) 'excel_seat_upload_stub.dart' as html;

import '../../app/admin_theme.dart';

// ─────────────────────────────────────────────────
// Excel Seat Upload Helper
// Guide, Template Downloads, Enhanced Parsing, Validation Preview
// ─────────────────────────────────────────────────

/// Detected Excel format type
enum ExcelFormat {
  visual,   // 셀 위치 = 좌석 위치, 셀 값 = 등급
  list,     // 컬럼: 구역, 층, 열, 번호, 등급
  rowCol,   // 행 = 좌석열, 열 = 좌석번호, 셀 값 = 등급
}

/// Result from parsing an Excel file
class ExcelParseResult {
  final List<LayoutSeat> seats;
  final ExcelFormat detectedFormat;
  final List<String> warnings;
  final List<String> errors;
  final Map<String, int> gradeCounts;
  final Set<String> duplicateKeys;

  const ExcelParseResult({
    required this.seats,
    required this.detectedFormat,
    this.warnings = const [],
    this.errors = const [],
    this.gradeCounts = const {},
    this.duplicateKeys = const {},
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  int get totalSeats => seats.length;
}

// ═══════════════════════════════════════════════════
// 1) Excel Upload Guide Panel (collapsible)
// ═══════════════════════════════════════════════════

class ExcelUploadGuidePanel extends StatefulWidget {
  final VoidCallback? onDownloadVisual;
  final VoidCallback? onDownloadList;
  final VoidCallback? onDownloadRowCol;

  const ExcelUploadGuidePanel({
    super.key,
    this.onDownloadVisual,
    this.onDownloadList,
    this.onDownloadRowCol,
  });

  @override
  State<ExcelUploadGuidePanel> createState() => _ExcelUploadGuidePanelState();
}

class _ExcelUploadGuidePanelState extends State<ExcelUploadGuidePanel> {
  bool _expanded = false;

  static const Map<String, Color> _gradeColorMap = {
    'VIP': Color(0xFFC9A84C),
    'R': Color(0xFFE53935),
    'S': Color(0xFF1E88E5),
    'A': Color(0xFF43A047),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _expanded
              ? AdminTheme.gold.withValues(alpha: 0.3)
              : AdminTheme.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header (toggle)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    size: 18,
                    color: AdminTheme.gold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '엑셀 좌석배치도 작성 가이드',
                      style: AdminTheme.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AdminTheme.gold,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AdminTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Expandable content
          if (_expanded) ...[
            const Divider(
                color: AdminTheme.border, height: 0.5, thickness: 0.5),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Color legend
                  _buildColorLegend(),
                  const SizedBox(height: 16),

                  // Format 1: Visual Layout (recommended)
                  _buildFormatSection(
                    index: 1,
                    title: '시각적 배치',
                    recommended: true,
                    description:
                        '엑셀 셀 = 좌석 위치. 셀 값에 등급코드 입력 (VIP, R, S, A). 빈 셀 = 통로.',
                    asciiExample: '''
  |  1  |  2  |  3  |  4  |  5  |  6  |
--+-----+-----+-----+-----+-----+-----+
1 | VIP | VIP | VIP | VIP | VIP | VIP |
2 | VIP | VIP |     |     | VIP | VIP |
3 |  R  |  R  |  R  |  R  |  R  |  R  |
4 |  S  |  S  |  S  |  S  |  S  |  S  |
5 |  A  |  A  |  A  |  A  |  A  |  A  |''',
                    onDownload: widget.onDownloadVisual,
                    downloadLabel: '시각적 배치 예시',
                  ),

                  const SizedBox(height: 14),

                  // Format 2: List Format
                  _buildFormatSection(
                    index: 2,
                    title: '목록 형식',
                    recommended: false,
                    description:
                        '컬럼: 구역, 층, 열, 번호, 등급. 한 행에 좌석 하나.',
                    asciiExample: '''
  | 구역 |  층  |  열  | 번호 | 등급 |
--+------+------+------+------+------+
1 |  A   | 1층  |   1  |   1  | VIP  |
2 |  A   | 1층  |   1  |   2  | VIP  |
3 |  B   | 1층  |   2  |   1  |  R   |
4 |  B   | 1층  |   2  |   2  |  R   |''',
                    onDownload: widget.onDownloadList,
                    downloadLabel: '목록 형식 예시',
                  ),

                  const SizedBox(height: 14),

                  // Format 3: Row/Column Format
                  _buildFormatSection(
                    index: 3,
                    title: '행/열 기반',
                    recommended: false,
                    description:
                        '행 = 좌석열, 열 = 좌석번호, 셀 값 = 등급코드',
                    asciiExample: '''
  | 좌석1 | 좌석2 | 좌석3 | 좌석4 |
--+-------+-------+-------+-------+
1열|  VIP  |  VIP  |  VIP  |  VIP  |
2열|   R   |   R   |   R   |   R   |
3열|   S   |   S   |   S   |   S   |''',
                    onDownload: widget.onDownloadRowCol,
                    downloadLabel: '행/열 기반 예시',
                  ),

                  const SizedBox(height: 16),

                  // Tips
                  _buildTips(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColorLegend() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text('등급 색상:',
              style: AdminTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AdminTheme.textSecondary)),
          const SizedBox(width: 12),
          ..._gradeColorMap.entries.map((e) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: e.value,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(e.key,
                        style: AdminTheme.sans(
                            fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildFormatSection({
    required int index,
    required String title,
    required bool recommended,
    required String description,
    required String asciiExample,
    required VoidCallback? onDownload,
    required String downloadLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(4),
        border: recommended
            ? Border.all(
                color: AdminTheme.gold.withValues(alpha: 0.25), width: 0.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: recommended
                      ? AdminTheme.gold.withValues(alpha: 0.2)
                      : AdminTheme.cardElevated,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$index',
                  style: AdminTheme.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: recommended
                        ? AdminTheme.gold
                        : AdminTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: AdminTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (recommended) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AdminTheme.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '추천',
                    style: AdminTheme.sans(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.gold,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (onDownload != null)
                _downloadButton(downloadLabel, onDownload),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: AdminTheme.sans(
                fontSize: 11, color: AdminTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF16161C),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              asciiExample.trimLeft(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: AdminTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _downloadButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: AdminTheme.border),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download_rounded,
                size: 12, color: AdminTheme.textSecondary),
            const SizedBox(width: 4),
            Text(label,
                style: AdminTheme.sans(
                    fontSize: 10, color: AdminTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildTips() {
    final tips = [
      '빈 셀은 통로로 인식됩니다.',
      "첫 행이 'zone' 또는 '구역'이면 목록 형식으로 자동 인식합니다.",
      '시트 이름에 "층"이 포함되면 해당 층으로 자동 설정됩니다.',
      '등급코드: VIP, V, ROYAL(=R), STANDARD(=S), ECONOMY(=A) 지원',
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminTheme.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border:
            Border.all(color: AdminTheme.info.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  size: 14, color: AdminTheme.info),
              const SizedBox(width: 6),
              Text('TIP',
                  style: AdminTheme.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.info)),
            ],
          ),
          const SizedBox(height: 6),
          ...tips.map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('  \u2022 ',
                        style: AdminTheme.sans(
                            fontSize: 10, color: AdminTheme.textSecondary)),
                    Expanded(
                      child: Text(tip,
                          style: AdminTheme.sans(
                              fontSize: 10, color: AdminTheme.textSecondary)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 2) CSV Template Generator & Downloader
// ═══════════════════════════════════════════════════

class ExcelTemplateDownloader {
  /// Download CSV for visual layout format
  static void downloadVisualTemplate() {
    final rows = <List<String>>[
      ['', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10'],
      ['1', 'VIP', 'VIP', 'VIP', 'VIP', 'VIP', 'VIP', 'VIP', 'VIP', 'VIP', 'VIP'],
      ['2', 'VIP', 'VIP', 'VIP', '', '', '', '', 'VIP', 'VIP', 'VIP'],
      ['3', 'R', 'R', 'R', 'R', 'R', 'R', 'R', 'R', 'R', 'R'],
      ['4', 'R', 'R', 'R', 'R', 'R', 'R', 'R', 'R', 'R', 'R'],
      ['5', '', '', '', '', '', '', '', '', '', ''],
      ['6', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S'],
      ['7', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S'],
      ['8', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S'],
      ['9', '', '', '', '', '', '', '', '', '', ''],
      ['10', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A'],
      ['11', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A'],
    ];
    _downloadCsv(rows, '좌석배치_시각적_예시.csv');
  }

  /// Download CSV for list format
  static void downloadListTemplate() {
    final rows = <List<String>>[
      ['구역', '층', '열', '번호', '등급', '유형'],
      ['A', '1층', '1', '1', 'VIP', 'normal'],
      ['A', '1층', '1', '2', 'VIP', 'normal'],
      ['A', '1층', '1', '3', 'VIP', 'normal'],
      ['A', '1층', '2', '1', 'R', 'normal'],
      ['A', '1층', '2', '2', 'R', 'normal'],
      ['A', '1층', '2', '3', 'R', 'normal'],
      ['B', '1층', '3', '1', 'S', 'normal'],
      ['B', '1층', '3', '2', 'S', 'normal'],
      ['B', '1층', '3', '3', 'S', 'wheelchair'],
      ['B', '1층', '4', '1', 'A', 'normal'],
      ['B', '1층', '4', '2', 'A', 'normal'],
      ['B', '1층', '4', '3', 'A', 'normal'],
    ];
    _downloadCsv(rows, '좌석배치_목록_예시.csv');
  }

  /// Download CSV for row/column format
  static void downloadRowColTemplate() {
    final rows = <List<String>>[
      ['', '좌석1', '좌석2', '좌석3', '좌석4', '좌석5', '좌석6'],
      ['1열', 'VIP', 'VIP', 'VIP', 'VIP', 'VIP', 'VIP'],
      ['2열', 'R', 'R', 'R', 'R', 'R', 'R'],
      ['3열', 'R', 'R', 'R', 'R', 'R', 'R'],
      ['4열', 'S', 'S', 'S', 'S', 'S', 'S'],
      ['5열', 'S', 'S', 'S', 'S', 'S', 'S'],
      ['6열', 'A', 'A', 'A', 'A', 'A', 'A'],
    ];
    _downloadCsv(rows, '좌석배치_행열_예시.csv');
  }

  static void _downloadCsv(List<List<String>> rows, String fileName) {
    if (!kIsWeb) return;
    // Add BOM for Excel UTF-8 compatibility
    const bom = '\uFEFF';
    final csv = bom + rows.map((row) => row.join(',')).join('\n');
    final bytes = utf8.encode(csv);
    final base64Data = base64Encode(bytes);
    html.AnchorElement(
      href: 'data:text/csv;base64,$base64Data',
    )
      ..setAttribute('download', fileName)
      ..click();
  }
}

// ═══════════════════════════════════════════════════
// 3) Enhanced Excel Parser
// ═══════════════════════════════════════════════════

class EnhancedExcelParser {
  /// Auto-detect format and parse Excel bytes
  static ExcelParseResult parse(List<int> bytes, {int gridCols = 60}) {
    final excel = Excel.decodeBytes(bytes);
    final allSeats = <LayoutSeat>[];
    final allWarnings = <String>[];
    final allErrors = <String>[];
    ExcelFormat? detectedFormat;

    for (final sheetName in excel.tables.keys) {
      final sheet = excel.tables[sheetName]!;
      if (sheet.maxRows < 2) {
        allWarnings.add('시트 "$sheetName": 데이터가 부족합니다 (2행 미만).');
        continue;
      }

      // Detect format from first row
      final format = _detectFormat(sheet);
      detectedFormat ??= format;

      final floor =
          sheetName.contains('층') ? sheetName : '1층';

      switch (format) {
        case ExcelFormat.list:
          _parseListFormat(sheet, sheetName, floor, allSeats, allWarnings, allErrors);
          break;
        case ExcelFormat.visual:
          _parseVisualFormat(sheet, sheetName, floor, allSeats, allWarnings, allErrors);
          break;
        case ExcelFormat.rowCol:
          _parseRowColFormat(sheet, sheetName, floor, allSeats, allWarnings, allErrors);
          break;
      }
    }

    // Calculate grade counts
    final gradeCounts = <String, int>{};
    for (final seat in allSeats) {
      gradeCounts[seat.grade] = (gradeCounts[seat.grade] ?? 0) + 1;
    }

    // Find duplicates
    final seenKeys = <String>{};
    final duplicateKeys = <String>{};
    for (final seat in allSeats) {
      if (!seenKeys.add(seat.key)) {
        duplicateKeys.add(seat.key);
      }
    }
    if (duplicateKeys.isNotEmpty) {
      allWarnings.add('중복 위치 ${duplicateKeys.length}개 발견 (마지막 데이터로 적용).');
    }

    return ExcelParseResult(
      seats: allSeats,
      detectedFormat: detectedFormat ?? ExcelFormat.visual,
      warnings: allWarnings,
      errors: allErrors,
      gradeCounts: gradeCounts,
      duplicateKeys: duplicateKeys,
    );
  }

  /// Detect format by analyzing first row headers
  static ExcelFormat _detectFormat(Sheet sheet) {
    final firstRow = <String>[];
    for (int c = 0; c < sheet.maxColumns; c++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      firstRow.add(cell.value?.toString().trim().toLowerCase() ?? '');
    }

    // Check for list format indicators
    final listKeywords = [
      'zone', '구역', 'block', 'section',
      'grade', '등급', 'class',
      'row', '열', '행',
      'number', '번호', 'seat', '좌석',
    ];
    int listMatches = 0;
    for (final kw in listKeywords) {
      if (firstRow.any((h) => h.contains(kw))) listMatches++;
    }
    if (listMatches >= 2) return ExcelFormat.list;

    // Check for visual layout: scan some cells for grade codes only
    final gradeCodes = {'vip', 'v', 'r', 's', 'a', 'royal', 'standard', 'economy'};
    int gradeCellCount = 0;
    int totalNonEmptyCells = 0;

    final scanRows = math.min(sheet.maxRows, 8);
    final scanCols = math.min(sheet.maxColumns, 12);
    for (int r = 1; r < scanRows; r++) {
      for (int c = 0; c < scanCols; c++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final val = cell.value?.toString().trim().toLowerCase() ?? '';
        if (val.isNotEmpty) {
          totalNonEmptyCells++;
          if (gradeCodes.contains(val)) gradeCellCount++;
        }
      }
    }

    // If most non-empty cells contain grade codes, it's visual layout
    if (totalNonEmptyCells > 0 &&
        gradeCellCount / totalNonEmptyCells > 0.6) {
      return ExcelFormat.visual;
    }

    // Default to row/col
    return ExcelFormat.rowCol;
  }

  /// Parse list format (column-based: zone, floor, row, number, grade)
  static void _parseListFormat(
    Sheet sheet,
    String sheetName,
    String defaultFloor,
    List<LayoutSeat> seats,
    List<String> warnings,
    List<String> errors,
  ) {
    final header = <String>[];
    for (int c = 0; c < sheet.maxColumns; c++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      header.add(cell.value?.toString().trim().toLowerCase() ?? '');
    }

    final zoneIdx = _findCol(header, ['zone', '구역', 'block', 'section']);
    final floorIdx = _findCol(header, ['floor', '층']);
    final gradeIdx = _findCol(header, ['grade', '등급', 'class']);
    final rowIdx = _findCol(header, ['row', '열', '행']);
    final numIdx = _findCol(header, ['number', '번호', 'seat', 'num', '좌석']);
    final xIdx = _findCol(header, ['x', 'col', '열위치']);
    final yIdx = _findCol(header, ['y', 'row_pos', '행위치']);
    final typeIdx = _findCol(header, ['type', '유형', 'seat_type']);

    if (gradeIdx < 0) {
      errors.add('시트 "$sheetName": 등급(grade) 컬럼을 찾을 수 없습니다.');
      return;
    }

    int skippedRows = 0;
    for (int r = 1; r < sheet.maxRows; r++) {
      String cellVal(int? idx) {
        if (idx == null || idx < 0) return '';
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: idx, rowIndex: r));
        return cell.value?.toString().trim() ?? '';
      }

      final zone = cellVal(zoneIdx);
      final floor = cellVal(floorIdx);
      final grade = cellVal(gradeIdx);
      if (grade.isEmpty) {
        skippedRows++;
        continue;
      }

      final rowName = cellVal(rowIdx);
      final numStr = cellVal(numIdx);
      final xStr = cellVal(xIdx);
      final yStr = cellVal(yIdx);
      final typeStr = cellVal(typeIdx);

      int gx = int.tryParse(xStr) ?? -1;
      int gy = int.tryParse(yStr) ?? -1;

      if (gx < 0 || gy < 0) {
        gy = int.tryParse(rowName) ?? r;
        gx = int.tryParse(numStr) ?? (seats.length % 60);
      }

      seats.add(LayoutSeat(
        gridX: gx,
        gridY: gy,
        zone: zone.isNotEmpty ? zone : sheetName,
        floor: floor.isNotEmpty ? floor : defaultFloor,
        row: rowName,
        number: int.tryParse(numStr) ?? 0,
        grade: _normalizeGrade(grade),
        seatType: typeStr.isNotEmpty
            ? SeatType.fromString(typeStr)
            : SeatType.normal,
      ));
    }

    if (skippedRows > 0) {
      warnings.add('시트 "$sheetName": 등급 없는 $skippedRows개 행 건너뜀.');
    }
  }

  /// Parse visual layout (cell position = seat position)
  static void _parseVisualFormat(
    Sheet sheet,
    String sheetName,
    String defaultFloor,
    List<LayoutSeat> seats,
    List<String> warnings,
    List<String> errors,
  ) {
    int parsed = 0;
    int skipped = 0;

    // Start from row 1 (skip header row if exists), col 1 (skip row labels)
    // Detect whether row 0 and col 0 are labels or data
    final firstCellVal =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
            .value?.toString().trim() ?? '';
    final hasRowHeader = firstCellVal.isEmpty ||
        int.tryParse(firstCellVal) != null; // empty or numeric
    final startRow = hasRowHeader ? 1 : 0;
    final startCol = hasRowHeader ? 1 : 0;

    for (int r = startRow; r < sheet.maxRows; r++) {
      for (int c = startCol; c < sheet.maxColumns; c++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final val = cell.value?.toString().trim() ?? '';
        if (val.isEmpty) continue;

        final grade = _normalizeGrade(val);
        if (grade.isEmpty || !_isValidGrade(grade)) {
          skipped++;
          continue;
        }

        // Grid position: use 0-based position (offset by headers)
        final gx = c - startCol;
        final gy = r - startRow;

        seats.add(LayoutSeat(
          gridX: gx,
          gridY: gy,
          zone: sheetName,
          floor: defaultFloor,
          row: '${gy + 1}',
          number: gx + 1,
          grade: grade,
        ));
        parsed++;
      }
    }

    if (skipped > 0) {
      warnings.add(
          '시트 "$sheetName": 인식할 수 없는 $skipped개 셀 건너뜀.');
    }
  }

  /// Parse row/column format (row = seat row, col = seat number)
  static void _parseRowColFormat(
    Sheet sheet,
    String sheetName,
    String defaultFloor,
    List<LayoutSeat> seats,
    List<String> warnings,
    List<String> errors,
  ) {
    int skipped = 0;

    for (int r = 1; r < sheet.maxRows; r++) {
      // Row label from column 0
      final rowLabel = sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
              .value
              ?.toString()
              .trim() ??
          '$r';
      // Extract number from row label (e.g. "3열" -> 3)
      final rowNum = int.tryParse(
              rowLabel.replaceAll(RegExp(r'[^0-9]'), '')) ??
          r;

      for (int c = 1; c < sheet.maxColumns; c++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final val = cell.value?.toString().trim() ?? '';
        if (val.isEmpty) continue;

        final grade = _normalizeGrade(val);
        if (grade.isEmpty || !_isValidGrade(grade)) {
          skipped++;
          continue;
        }

        seats.add(LayoutSeat(
          gridX: c - 1,
          gridY: rowNum - 1,
          zone: sheetName,
          floor: defaultFloor,
          row: '$rowNum',
          number: c,
          grade: grade,
        ));
      }
    }

    if (skipped > 0) {
      warnings.add(
          '시트 "$sheetName": 인식할 수 없는 $skipped개 셀 건너뜀.');
    }
  }

  static int _findCol(List<String> headers, List<String> candidates) {
    for (final c in candidates) {
      final idx = headers.indexWhere((h) => h.contains(c));
      if (idx >= 0) return idx;
    }
    return -1;
  }

  static String _normalizeGrade(String raw) {
    final upper = raw.toUpperCase().trim();
    if (upper == 'VIP' || upper == 'V') return 'VIP';
    if (upper == 'R' || upper == 'ROYAL') return 'R';
    if (upper == 'S' || upper == 'STANDARD') return 'S';
    if (upper == 'A' || upper == 'ECONOMY') return 'A';
    return upper;
  }

  static bool _isValidGrade(String grade) {
    return {'VIP', 'R', 'S', 'A'}.contains(grade);
  }
}

// ═══════════════════════════════════════════════════
// 4) Validation Preview Dialog
// ═══════════════════════════════════════════════════

class ExcelValidationPreviewDialog extends StatelessWidget {
  final ExcelParseResult result;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const ExcelValidationPreviewDialog({
    super.key,
    required this.result,
    required this.onConfirm,
    required this.onCancel,
  });

  static const Map<String, Color> _gradeColors = {
    'VIP': Color(0xFFC9A84C),
    'R': Color(0xFFE53935),
    'S': Color(0xFF1E88E5),
    'A': Color(0xFF43A047),
  };

  static const _formatNames = {
    ExcelFormat.visual: '시각적 배치',
    ExcelFormat.list: '목록 형식',
    ExcelFormat.rowCol: '행/열 기반',
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AdminTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(context),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Format detected
                    _buildInfoRow(
                      icon: Icons.auto_fix_high_rounded,
                      label: '인식 형식',
                      value: _formatNames[result.detectedFormat] ?? '알 수 없음',
                    ),
                    const SizedBox(height: 12),

                    // Total seats
                    _buildInfoRow(
                      icon: Icons.event_seat_rounded,
                      label: '총 좌석 수',
                      value: '${result.totalSeats}석',
                      valueColor: AdminTheme.gold,
                    ),
                    const SizedBox(height: 16),

                    // Grade breakdown
                    _buildGradeBreakdown(),

                    // Warnings
                    if (result.hasWarnings) ...[
                      const SizedBox(height: 16),
                      _buildMessageSection(
                        icon: Icons.warning_amber_rounded,
                        title: '경고 (${result.warnings.length})',
                        messages: result.warnings,
                        color: AdminTheme.warning,
                      ),
                    ],

                    // Errors
                    if (result.hasErrors) ...[
                      const SizedBox(height: 16),
                      _buildMessageSection(
                        icon: Icons.error_outline_rounded,
                        title: '오류 (${result.errors.length})',
                        messages: result.errors,
                        color: AdminTheme.error,
                      ),
                    ],

                    // Duplicates
                    if (result.duplicateKeys.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDuplicatesSection(),
                    ],

                    // Missing number warnings
                    ..._buildMissingNumberWarnings(),
                  ],
                ),
              ),
            ),

            // Footer buttons
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final bool hasIssues = result.hasErrors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: hasIssues
            ? AdminTheme.error.withValues(alpha: 0.08)
            : AdminTheme.gold.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(
            hasIssues
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 24,
            color: hasIssues ? AdminTheme.error : AdminTheme.success,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasIssues ? '파싱 결과 (오류 있음)' : '파싱 결과 확인',
                  style: AdminTheme.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '아래 내용을 확인하고 적용 여부를 결정하세요.',
                  style: AdminTheme.sans(
                      fontSize: 12, color: AdminTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AdminTheme.textSecondary),
        const SizedBox(width: 8),
        Text(label,
            style: AdminTheme.sans(
                fontSize: 12, color: AdminTheme.textSecondary)),
        const Spacer(),
        Text(value,
            style: AdminTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AdminTheme.textPrimary,
            )),
      ],
    );
  }

  Widget _buildGradeBreakdown() {
    // Sort in VIP > R > S > A order
    const gradeOrder = ['VIP', 'R', 'S', 'A'];
    final sortedGrades = result.gradeCounts.entries.toList()
      ..sort((a, b) {
        final ai = gradeOrder.indexOf(a.key);
        final bi = gradeOrder.indexOf(b.key);
        return (ai < 0 ? 99 : ai).compareTo(bi < 0 ? 99 : bi);
      });

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('등급별 좌석 수',
              style: AdminTheme.label(fontSize: 10)),
          const SizedBox(height: 10),
          ...sortedGrades.map((entry) {
            final color =
                _gradeColors[entry.key] ?? AdminTheme.textSecondary;
            final ratio =
                result.totalSeats > 0 ? entry.value / result.totalSeats : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(entry.key,
                        style: AdminTheme.sans(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: AdminTheme.cardElevated,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: ratio,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${entry.value}석',
                      textAlign: TextAlign.right,
                      style: AdminTheme.sans(fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMessageSection({
    required IconData icon,
    required String title,
    required List<String> messages,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(title,
                  style: AdminTheme.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ],
          ),
          const SizedBox(height: 6),
          ...messages.map((msg) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('  \u2022 ',
                        style: AdminTheme.sans(
                            fontSize: 10, color: AdminTheme.textSecondary)),
                    Expanded(
                      child: Text(msg,
                          style: AdminTheme.sans(
                              fontSize: 10, color: AdminTheme.textSecondary)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildDuplicatesSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: AdminTheme.warning.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.copy_rounded,
                  size: 14, color: AdminTheme.warning),
              const SizedBox(width: 6),
              Text('중복 좌석 위치 (${result.duplicateKeys.length}건)',
                  style: AdminTheme.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.warning)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '중복 위치: ${result.duplicateKeys.take(10).join(', ')}${result.duplicateKeys.length > 10 ? ' ...' : ''}',
            style:
                AdminTheme.sans(fontSize: 10, color: AdminTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            '마지막으로 읽힌 데이터가 적용됩니다.',
            style: AdminTheme.sans(
                fontSize: 10,
                color: AdminTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMissingNumberWarnings() {
    // Check for rows with gaps in seat numbers
    final rowGroups = <String, List<int>>{};
    for (final seat in result.seats) {
      final key = '${seat.zone}_${seat.floor}_${seat.row}';
      rowGroups.putIfAbsent(key, () => []).add(seat.number);
    }

    final missingWarnings = <String>[];
    for (final entry in rowGroups.entries) {
      if (entry.value.isEmpty) continue;
      final numbers = entry.value..sort();
      if (numbers.first > 0 && numbers.last > 0) {
        final expected =
            List.generate(numbers.last, (i) => i + 1).toSet();
        final actual = numbers.toSet();
        final missing = expected.difference(actual);
        if (missing.isNotEmpty && missing.length <= 5) {
          missingWarnings.add(
              '${entry.key}: 빠진 번호 ${missing.join(', ')}');
        }
      }
    }

    if (missingWarnings.isEmpty) return [];
    return [
      const SizedBox(height: 16),
      _buildMessageSection(
        icon: Icons.numbers_rounded,
        title: '빠진 좌석 번호 (${missingWarnings.length}건)',
        messages: missingWarnings.take(8).toList(),
        color: AdminTheme.info,
      ),
    ];
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border:
            Border(top: BorderSide(color: AdminTheme.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Cancel
          SizedBox(
            height: 36,
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                minimumSize: Size.zero,
                side: const BorderSide(color: AdminTheme.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              child: Text('취소',
                  style: AdminTheme.sans(
                      fontSize: 12, color: AdminTheme.textSecondary)),
            ),
          ),
          const SizedBox(width: 8),
          // Confirm
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: result.hasErrors ? null : onConfirm,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: Text('확인 (${result.totalSeats}석 적용)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                minimumSize: Size.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
