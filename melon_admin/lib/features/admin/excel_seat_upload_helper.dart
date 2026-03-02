import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:melon_core/data/models/venue.dart';
import 'package:xml/xml.dart' as xml;

import 'dart:html' if (dart.library.io) 'excel_seat_upload_stub.dart' as html;

import '../../app/admin_theme.dart';

// ─────────────────────────────────────────────────
// Excel Seat Upload Helper
// Guide, Template Downloads, Enhanced Parsing, Validation Preview
// ─────────────────────────────────────────────────

/// Detected Excel format type
enum ExcelFormat {
  visual,      // 셀 위치 = 좌석 위치, 셀 값 = 등급
  colorCoded,  // 셀 배경색 = 등급, 셀 값 = 좌석번호 (좌석배치도)
  list,        // 컬럼: 구역, 층, 열, 번호, 등급
  rowCol,      // 행 = 좌석열, 열 = 좌석번호, 셀 값 = 등급
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
    // Resolve theme colors from raw xlsx ZIP (dart excel package can't do this)
    final colorResolver = _ThemeColorResolver(bytes);
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
      final format = _detectFormat(sheet, sheetName, colorResolver);
      detectedFormat ??= format;

      final floor =
          sheetName.contains('층') ? sheetName : '1층';

      switch (format) {
        case ExcelFormat.list:
          _parseListFormat(sheet, sheetName, floor, allSeats, allWarnings, allErrors);
          break;
        case ExcelFormat.colorCoded:
          _parseColorCodedFormat(sheet, sheetName, floor, allSeats, allWarnings, allErrors, colorResolver);
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
  static ExcelFormat _detectFormat(Sheet sheet, String sheetName, _ThemeColorResolver colorResolver) {
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

    // Check for color-coded layout: numeric cells with colored backgrounds
    // (좌석배치도: 셀 값 = 좌석번호, 배경색 = 등급)
    // Uses ThemeColorResolver to properly resolve Office theme colors
    int coloredNumericCells = 0;
    int totalNumericCells = 0;
    final scanRowsColor = math.min(sheet.maxRows, 15);
    final scanColsColor = math.min(sheet.maxColumns, 20);
    for (int r = 1; r < scanRowsColor; r++) {
      for (int c = 0; c < scanColsColor; c++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final val = cell.value?.toString().trim() ?? '';
        if (val.isEmpty) continue;
        if (int.tryParse(val) == null) continue;
        totalNumericCells++;
        // Try theme-resolved color first, then fall back to excel package
        final resolvedHex = colorResolver.getBackgroundColor(sheetName, r, c);
        final bgHex = resolvedHex != null ? 'FF$resolvedHex' : (cell.cellStyle?.backgroundColor.colorHex ?? 'none');
        if (bgHex != 'none' && bgHex != 'FF000000' && bgHex != 'FFFFFFFF') {
          coloredNumericCells++;
        }
      }
    }
    if (totalNumericCells > 5 && coloredNumericCells / totalNumericCells > 0.3) {
      return ExcelFormat.colorCoded;
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

    // Detect 좌석수 column (네이버 format: total seats per row)
    final seatCountIdx = _findCol(header, ['좌석수', 'count', '수량']);

    int skippedRows = 0;
    for (int r = 1; r < sheet.maxRows; r++) {
      String cellVal(int? idx) {
        if (idx == null || idx < 0) return '';
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: idx, rowIndex: r));
        return cell.value?.toString().trim() ?? '';
      }

      var zone = cellVal(zoneIdx);
      final floor = cellVal(floorIdx);
      final grade = cellVal(gradeIdx);
      if (grade.isEmpty) {
        skippedRows++;
        continue;
      }

      final normalizedGrade = _normalizeGrade(grade);
      if (!_isValidGrade(normalizedGrade)) {
        skippedRows++;
        continue;
      }

      var rowName = cellVal(rowIdx);
      final numStr = cellVal(numIdx);
      final xStr = cellVal(xIdx);
      final yStr = cellVal(yIdx);
      final typeStr = cellVal(typeIdx);

      // Parse "B블록1열" format from 열 column → zone="B블록", row="1"
      if (rowName.isNotEmpty && zone.isEmpty) {
        final blockRowMatch =
            RegExp(r'^([A-Za-z가-힣]+블록?)(\d+)열?$').firstMatch(rowName);
        if (blockRowMatch != null) {
          zone = blockRowMatch.group(1)!;
          rowName = blockRowMatch.group(2)!;
        } else {
          // Try extracting just the number (e.g. "3열" → "3")
          final rowNumMatch = RegExp(r'(\d+)').firstMatch(rowName);
          if (rowNumMatch != null) {
            rowName = rowNumMatch.group(1)!;
          }
        }
      }

      // Expand space-separated seat numbers (네이버 format: "1 2 3 4 5 6 7 8 9 10")
      final seatNumbers = numStr.split(RegExp(r'[\s,]+'))
          .where((s) => s.isNotEmpty && int.tryParse(s) != null)
          .map((s) => int.parse(s))
          .toList();

      if (seatNumbers.length > 1) {
        // Multiple seats in one row → expand each
        final gy = int.tryParse(yStr) ??
            int.tryParse(rowName) ?? r;
        for (final seatNum in seatNumbers) {
          seats.add(LayoutSeat.fromGrid(
            gridX: seatNum,
            gridY: gy,
            zone: zone.isNotEmpty ? zone : sheetName,
            floor: floor.isNotEmpty ? floor : defaultFloor,
            row: rowName,
            number: seatNum,
            grade: normalizedGrade,
            seatType: typeStr.isNotEmpty
                ? SeatType.fromString(typeStr)
                : SeatType.normal,
          ));
        }
      } else {
        // Single seat or non-numeric → original logic
        int gx = int.tryParse(xStr) ?? -1;
        int gy = int.tryParse(yStr) ?? -1;

        if (gx < 0 || gy < 0) {
          gy = int.tryParse(rowName) ?? r;
          gx = seatNumbers.isNotEmpty
              ? seatNumbers.first
              : (seats.length % 60);
        }

        seats.add(LayoutSeat.fromGrid(
          gridX: gx,
          gridY: gy,
          zone: zone.isNotEmpty ? zone : sheetName,
          floor: floor.isNotEmpty ? floor : defaultFloor,
          row: rowName,
          number: seatNumbers.isNotEmpty ? seatNumbers.first : 0,
          grade: normalizedGrade,
          seatType: typeStr.isNotEmpty
              ? SeatType.fromString(typeStr)
              : SeatType.normal,
        ));
      }
    }

    if (skippedRows > 0) {
      warnings.add('시트 "$sheetName": 등급 없는 $skippedRows개 행 건너뜀.');
    }
  }

  /// Parse color-coded layout (셀 배경색 = 등급, 셀 값 = 좌석번호)
  /// 좌석배치도 엑셀: 빨강=VIP, 파랑=R, 초록=S, 노랑=A, 검정=미판매
  static void _parseColorCodedFormat(
    Sheet sheet,
    String sheetName,
    String defaultFloor,
    List<LayoutSeat> seats,
    List<String> warnings,
    List<String> errors,
    _ThemeColorResolver colorResolver,
  ) {
    // 1) Detect block headers (cells containing "블록")
    // Maps column ranges to block names
    final blockRanges = <_BlockRange>[];
    final rowLabelCols = <int>{}; // columns that contain row labels (열)

    for (int r = 0; r < math.min(sheet.maxRows, 5); r++) {
      for (int c = 0; c < sheet.maxColumns; c++) {
        final val = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .value?.toString().trim() ?? '';
        if (val.contains('블록')) {
          // Extract block name: "A블록(157)" → "A블록"
          final name = RegExp(r'([A-Za-z가-힣]*블록)')
              .firstMatch(val)?.group(1) ?? val;
          blockRanges.add(_BlockRange(name: name, startCol: c, headerRow: r));
        }
        if (val == '열') {
          rowLabelCols.add(c);
        }
      }
    }

    // Sort blocks by column position and assign end columns
    blockRanges.sort((a, b) => a.startCol.compareTo(b.startCol));
    for (int i = 0; i < blockRanges.length; i++) {
      if (i + 1 < blockRanges.length) {
        blockRanges[i].endCol = blockRanges[i + 1].startCol - 1;
      } else {
        blockRanges[i].endCol = sheet.maxColumns - 1;
      }
    }

    // 2) Detect floor from sheet content
    String floor = defaultFloor;
    for (int r = 0; r < math.min(sheet.maxRows, 5); r++) {
      for (int c = 0; c < sheet.maxColumns; c++) {
        final val = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .value?.toString().trim() ?? '';
        final floorMatch = RegExp(r'(\d)층').firstMatch(val);
        if (floorMatch != null) {
          floor = '${floorMatch.group(1)}층';
          break;
        }
      }
    }

    // 3) Scan all cells: numeric value + colored background → seat
    int parsed = 0;
    int skipped = 0;
    int noColorSkipped = 0;

    // Debug: track color → grade classification
    final colorGradeMap = <String, String>{}; // hex → grade
    final colorCountMap = <String, int>{}; // hex → count
    final skippedColors = <String, int>{}; // hex → count (skipped)

    // Track row numbers per row-index using row label columns
    final rowLabels = <int, String>{}; // row index → row number string
    for (final labelCol in rowLabelCols) {
      for (int r = 0; r < sheet.maxRows; r++) {
        final val = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: labelCol, rowIndex: r))
            .value?.toString().trim() ?? '';
        if (val.isNotEmpty && int.tryParse(val) != null) {
          rowLabels[r] = val;
        }
      }
    }

    for (int r = 0; r < sheet.maxRows; r++) {
      for (int c = 0; c < sheet.maxColumns; c++) {
        // Skip row label columns
        if (rowLabelCols.contains(c)) continue;

        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final val = cell.value?.toString().trim() ?? '';
        if (val.isEmpty) continue;

        // Must be numeric (seat number)
        final seatNum = int.tryParse(val);
        if (seatNum == null) continue;

        // Get background color — use theme resolver first, then excel package fallback
        final resolvedHex = colorResolver.getBackgroundColor(sheetName, r, c);
        final excelHex = cell.cellStyle?.backgroundColor.colorHex ?? 'none';
        final bgHex = resolvedHex ?? excelHex;
        final grade = _colorHexToGrade(bgHex);
        if (grade == null) {
          noColorSkipped++;
          skippedColors[bgHex] = (skippedColors[bgHex] ?? 0) + 1;
          continue;
        }

        // Track color→grade for debug
        colorGradeMap[bgHex] = grade;
        colorCountMap[bgHex] = (colorCountMap[bgHex] ?? 0) + 1;

        // Find which block this column belongs to
        String zone = sheetName;
        for (final block in blockRanges) {
          if (c >= block.startCol && c <= block.endCol) {
            zone = block.name;
            break;
          }
        }

        // Row number from label columns
        final rowName = rowLabels[r] ?? '${r + 1}';

        seats.add(LayoutSeat.fromGrid(
          gridX: seatNum,
          gridY: int.tryParse(rowName) ?? r,
          zone: zone,
          floor: floor,
          row: rowName,
          number: seatNum,
          grade: grade,
        ));
        parsed++;
      }
    }

    if (parsed == 0) {
      errors.add('시트 "$sheetName": 색상 코딩된 좌석을 찾을 수 없습니다.');
    }
    if (noColorSkipped > 0) {
      warnings.add(
          '시트 "$sheetName": 배경색 없는 $noColorSkipped개 숫자 셀 건너뜀.');
    }
    if (blockRanges.isNotEmpty) {
      final blockNames = blockRanges.map((b) => b.name).join(', ');
      warnings.add('시트 "$sheetName": 감지된 블록: $blockNames');
    }

    // Debug: color resolution summary
    if (colorGradeMap.isNotEmpty) {
      final colorSummary = colorGradeMap.entries
          .map((e) => '#${e.key}→${e.value}(${colorCountMap[e.key]}석)')
          .join(', ');
      warnings.add('[디버그] 색상→등급: $colorSummary');
    }
    if (skippedColors.isNotEmpty) {
      final skipSummary = skippedColors.entries
          .map((e) => '#${e.key}(${e.value}개)')
          .join(', ');
      warnings.add('[디버그] 건너뛴 색상: $skipSummary');
    }
    // Resolver debug
    for (final info in colorResolver.debugInfo) {
      warnings.add('[디버그] $info');
    }
    if (colorResolver.parseError != null) {
      errors.add('[디버그] 색상 해석기 오류: ${colorResolver.parseError}');
    }
  }

  /// Map Excel background color hex to grade using HSL hue.
  /// Hue-based classification works correctly even with tinted/shaded theme colors.
  /// 빨강/핑크/보라 → VIP, 파랑/시안 → R, 초록 → S, 노랑/오렌지 → A
  /// 검정/흰색/회색 → null (skip)
  static String? _colorHexToGrade(String hex) {
    if (hex == 'none' || hex.isEmpty) return null;

    // Remove FF prefix if present (ARGB → RGB)
    String rgb = hex.toUpperCase();
    if (rgb.length == 8) rgb = rgb.substring(2);
    if (rgb.length != 6) return null;

    final r = int.tryParse(rgb.substring(0, 2), radix: 16) ?? 0;
    final g = int.tryParse(rgb.substring(2, 4), radix: 16) ?? 0;
    final b = int.tryParse(rgb.substring(4, 6), radix: 16) ?? 0;

    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    final chroma = maxC - minC;

    // Skip achromatic colors (black, white, gray)
    if (maxC < 30) return null;         // black (미판매)
    if (minC > 230) return null;        // white (배경)
    if (chroma < 25) return null;       // gray (no distinguishable color)

    // Calculate hue (0-360 degrees)
    double hue;
    if (chroma == 0) {
      return null; // achromatic
    } else if (maxC == r) {
      hue = 60.0 * (((g - b) / chroma) % 6);
    } else if (maxC == g) {
      hue = 60.0 * ((b - r) / chroma + 2);
    } else {
      hue = 60.0 * ((r - g) / chroma + 4);
    }
    if (hue < 0) hue += 360;

    // Classify by hue range:
    //   0-20, 340-360: Red/Pink       → VIP
    //   20-70:         Orange/Yellow   → A
    //   70-165:        Green           → S
    //   165-260:       Blue/Cyan       → R
    //   260-340:       Purple/Violet   → VIP
    if (hue < 20 || hue >= 340) return 'VIP';
    if (hue >= 20 && hue < 70) return 'A';
    if (hue >= 70 && hue < 165) return 'S';
    if (hue >= 165 && hue < 260) return 'R';
    if (hue >= 260 && hue < 340) return 'VIP';

    return null;
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

        seats.add(LayoutSeat.fromGrid(
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

        seats.add(LayoutSeat.fromGrid(
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
    // Strip 석/등급 suffix (네이버 format: VIP석, R석, S석, A석)
    final cleaned = raw.toUpperCase().trim()
        .replaceAll(RegExp(r'석$'), '')
        .replaceAll(RegExp(r'등급$'), '')
        .replaceAll(RegExp(r'좌석$'), '')
        .trim();
    if (cleaned == 'VIP' || cleaned == 'V') return 'VIP';
    if (cleaned == 'R' || cleaned == 'ROYAL') return 'R';
    if (cleaned == 'S' || cleaned == 'STANDARD') return 'S';
    if (cleaned == 'A' || cleaned == 'ECONOMY') return 'A';
    // Handle prefixed grades (시야방해R석 → R)
    if (cleaned.contains('VIP')) return 'VIP';
    if (RegExp(r'\bR\b').hasMatch(cleaned)) return 'R';
    if (RegExp(r'\bS\b').hasMatch(cleaned)) return 'S';
    if (RegExp(r'\bA\b').hasMatch(cleaned)) return 'A';
    return cleaned;
  }

  static bool _isValidGrade(String grade) {
    return {'VIP', 'R', 'S', 'A'}.contains(grade);
  }
}

/// Helper: block column range for color-coded format
class _BlockRange {
  final String name;
  final int startCol;
  final int headerRow;
  int endCol;

  _BlockRange({
    required this.name,
    required this.startCol,
    required this.headerRow,
    this.endCol = 0,
  });
}

/// Resolves Excel theme colors from raw xlsx ZIP data.
/// The Dart `excel` package does NOT resolve theme colors — it returns 'none'
/// for any cell colored with Office theme palette colors.
/// This class manually parses theme1.xml + styles.xml + sheet XMLs to build
/// a (sheetName, row, col) → RGB hex color map.
class _ThemeColorResolver {
  // fillId → resolved RGB hex (6 chars, uppercase, no alpha prefix)
  final Map<int, String> _fillColors = {};

  // styleIndex → fillId
  final Map<int, int> _styleFillMap = {};

  // sheetName → { rowIndex → { colIndex → styleIndex } }
  final Map<String, Map<int, Map<int, int>>> _cellStyles = {};

  // Debug info
  final List<String> debugInfo = [];
  String? parseError;

  _ThemeColorResolver(List<int> xlsxBytes) {
    try {
      final arch = archive.ZipDecoder().decodeBytes(xlsxBytes);
      final themeColors = _parseTheme(arch);
      debugInfo.add('테마색상 ${themeColors.length}개 파싱');
      _parseFills(arch, themeColors);
      debugInfo.add('채우기 ${_fillColors.length}개 해석 → ${_fillColors.entries.map((e) => 'fill${e.key}=#${e.value}').join(', ')}');
      _parseStyleXfs(arch);
      debugInfo.add('스타일→채우기 매핑 ${_styleFillMap.length}개');
      _parseSheets(arch);
      debugInfo.add('시트 ${_cellStyles.length}개: ${_cellStyles.keys.join(', ')}');
    } catch (e) {
      parseError = e.toString();
      debugInfo.add('⚠️ 파싱 실패: $e');
    }
  }

  /// Get resolved background RGB hex for a cell, or null if none/white/black.
  String? getBackgroundColor(String sheetName, int row, int col) {
    final sheetStyles = _cellStyles[sheetName];
    if (sheetStyles == null) return null;

    final rowStyles = sheetStyles[row];
    if (rowStyles == null) return null;

    final styleIdx = rowStyles[col];
    if (styleIdx == null) return null;

    final fillId = _styleFillMap[styleIdx];
    if (fillId == null) return null;

    return _fillColors[fillId];
  }

  /// Parse xl/theme/theme1.xml → theme index → RGB hex
  Map<int, String> _parseTheme(archive.Archive arch) {
    final themeColors = <int, String>{};
    final themeFile = arch.findFile('xl/theme/theme1.xml');
    if (themeFile == null) return themeColors;

    final content = utf8.decode(themeFile.content as List<int>);
    final doc = xml.XmlDocument.parse(content);

    // Find <a:clrScheme> — may have namespace prefix or not
    xml.XmlElement? clrScheme;
    for (final elem in doc.descendants.whereType<xml.XmlElement>()) {
      if (elem.localName == 'clrScheme') {
        clrScheme = elem;
        break;
      }
    }
    if (clrScheme == null) return themeColors;

    // Theme color order: dk1, lt1, dk2, lt2, accent1..accent6, hlink, folHlink
    final colorNames = [
      'dk1', 'lt1', 'dk2', 'lt2',
      'accent1', 'accent2', 'accent3', 'accent4',
      'accent5', 'accent6', 'hlink', 'folHlink',
    ];

    for (int i = 0; i < colorNames.length; i++) {
      for (final child in clrScheme.children.whereType<xml.XmlElement>()) {
        if (child.localName == colorNames[i]) {
          // Look for <a:srgbClr val="4F81BD"/> or <a:sysClr lastClr="000000"/>
          for (final sub in child.children.whereType<xml.XmlElement>()) {
            if (sub.localName == 'srgbClr') {
              final val = sub.getAttribute('val');
              if (val != null && val.isNotEmpty) themeColors[i] = val.toUpperCase();
              break;
            } else if (sub.localName == 'sysClr') {
              final lastClr = sub.getAttribute('lastClr');
              if (lastClr != null && lastClr.isNotEmpty) themeColors[i] = lastClr.toUpperCase();
              break;
            }
          }
          break;
        }
      }
    }
    return themeColors;
  }

  /// Parse xl/styles.xml → fill patterns (resolve theme → RGB)
  void _parseFills(archive.Archive arch, Map<int, String> themeColors) {
    final stylesFile = arch.findFile('xl/styles.xml');
    if (stylesFile == null) return;

    final content = utf8.decode(stylesFile.content as List<int>);
    final doc = xml.XmlDocument.parse(content);

    // Collect all <fill> elements under <fills>
    final fillsList = <xml.XmlElement>[];
    for (final elem in doc.descendants.whereType<xml.XmlElement>()) {
      if (elem.localName == 'fills') {
        for (final fill in elem.children.whereType<xml.XmlElement>()) {
          if (fill.localName == 'fill') fillsList.add(fill);
        }
        break;
      }
    }

    for (int i = 0; i < fillsList.length; i++) {
      xml.XmlElement? patternFill;
      for (final child in fillsList[i].children.whereType<xml.XmlElement>()) {
        if (child.localName == 'patternFill') {
          patternFill = child;
          break;
        }
      }
      if (patternFill == null) continue;

      xml.XmlElement? fgColor;
      for (final child in patternFill.children.whereType<xml.XmlElement>()) {
        if (child.localName == 'fgColor') {
          fgColor = child;
          break;
        }
      }
      if (fgColor == null) continue;

      // Direct RGB: <fgColor rgb="FFC0504D"/>
      final rgbAttr = fgColor.getAttribute('rgb');
      if (rgbAttr != null && rgbAttr.isNotEmpty) {
        // Strip alpha prefix (ARGB → RGB)
        final hex = rgbAttr.length == 8
            ? rgbAttr.substring(2).toUpperCase()
            : rgbAttr.toUpperCase();
        _fillColors[i] = hex;
        continue;
      }

      // Theme reference: <fgColor theme="5" tint="0.39997"/>
      final themeStr = fgColor.getAttribute('theme');
      if (themeStr != null) {
        final themeIdx = int.tryParse(themeStr);
        if (themeIdx != null && themeColors.containsKey(themeIdx)) {
          String resolved = themeColors[themeIdx]!;

          // Apply tint if present
          final tintStr = fgColor.getAttribute('tint');
          if (tintStr != null) {
            final tint = double.tryParse(tintStr);
            if (tint != null) resolved = _applyTint(resolved, tint);
          }
          _fillColors[i] = resolved;
        }
      }
    }
  }

  /// Parse xl/styles.xml → cellXfs: style index → fill index
  void _parseStyleXfs(archive.Archive arch) {
    final stylesFile = arch.findFile('xl/styles.xml');
    if (stylesFile == null) return;

    final content = utf8.decode(stylesFile.content as List<int>);
    final doc = xml.XmlDocument.parse(content);

    // Find <cellXfs> element
    for (final elem in doc.descendants.whereType<xml.XmlElement>()) {
      if (elem.localName == 'cellXfs') {
        int idx = 0;
        for (final xf in elem.children.whereType<xml.XmlElement>()) {
          if (xf.localName == 'xf') {
            final fillIdStr = xf.getAttribute('fillId');
            if (fillIdStr != null) {
              _styleFillMap[idx] = int.tryParse(fillIdStr) ?? 0;
            }
            idx++;
          }
        }
        break;
      }
    }
  }

  /// Parse xl/worksheets/sheetN.xml → cell (row, col) → style index
  void _parseSheets(archive.Archive arch) {
    // Get ordered sheet names from workbook.xml
    final sheetNames = <int, String>{};
    final wbFile = arch.findFile('xl/workbook.xml');
    if (wbFile != null) {
      final content = utf8.decode(wbFile.content as List<int>);
      final doc = xml.XmlDocument.parse(content);

      int idx = 1;
      for (final elem in doc.descendants.whereType<xml.XmlElement>()) {
        if (elem.localName == 'sheet') {
          sheetNames[idx] = elem.getAttribute('name') ?? 'Sheet$idx';
          idx++;
        }
      }
    }

    // Parse each sheet file
    for (final file in arch.files) {
      if (!file.name.startsWith('xl/worksheets/sheet') ||
          !file.name.endsWith('.xml')) continue;

      final sheetNumStr = file.name
          .replaceAll('xl/worksheets/sheet', '')
          .replaceAll('.xml', '');
      final sheetNum = int.tryParse(sheetNumStr) ?? 0;
      final name = sheetNames[sheetNum] ?? 'Sheet$sheetNum';

      final content = utf8.decode(file.content as List<int>);
      final doc = xml.XmlDocument.parse(content);

      final cellStyleMap = <int, Map<int, int>>{};

      for (final elem in doc.descendants.whereType<xml.XmlElement>()) {
        if (elem.localName != 'c') continue;

        final ref = elem.getAttribute('r') ?? '';
        final styleStr = elem.getAttribute('s');
        if (styleStr == null) continue;

        final styleIdx = int.tryParse(styleStr);
        if (styleIdx == null) continue;

        final pos = _parseRef(ref);
        if (pos == null) continue;

        cellStyleMap.putIfAbsent(pos.$2, () => {})[pos.$1] = styleIdx;
      }

      _cellStyles[name] = cellStyleMap;
    }
  }

  /// Parse cell reference like "A1" → (col, row) 0-indexed, or null
  static (int, int)? _parseRef(String ref) {
    if (ref.isEmpty) return null;

    int col = 0;
    int i = 0;
    // Parse column letters (A=1, B=2, ..., Z=26, AA=27, etc.)
    while (i < ref.length) {
      final code = ref.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        col = col * 26 + (code - 64);
        i++;
      } else {
        break;
      }
    }
    if (i == 0) return null;
    col -= 1; // 0-indexed

    final row = int.tryParse(ref.substring(i));
    if (row == null || row < 1) return null;

    return (col, row - 1); // 0-indexed
  }

  /// Apply Excel tint to a hex color
  static String _applyTint(String hexColor, double tint) {
    if (hexColor.length < 6) return hexColor;
    final hex = hexColor.length == 6
        ? hexColor
        : hexColor.substring(hexColor.length - 6);

    int r = int.tryParse(hex.substring(0, 2), radix: 16) ?? 0;
    int g = int.tryParse(hex.substring(2, 4), radix: 16) ?? 0;
    int b = int.tryParse(hex.substring(4, 6), radix: 16) ?? 0;

    if (tint < 0) {
      // Darken
      r = (r * (1 + tint)).round();
      g = (g * (1 + tint)).round();
      b = (b * (1 + tint)).round();
    } else {
      // Lighten
      r = (r + (255 - r) * tint).round();
      g = (g + (255 - g) * tint).round();
      b = (b + (255 - b) * tint).round();
    }

    return '${r.clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${g.clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${b.clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase()}';
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
