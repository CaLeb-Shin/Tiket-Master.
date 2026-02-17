import 'dart:typed_data';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:melon_core/data/models/venue.dart';

/// 엑셀에서 파싱된 좌석 데이터
class ParsedSeatData {
  final String venueName;
  final List<ParsedFloor> floors;
  final int totalSeats;
  final List<SeatGrade> grades;

  ParsedSeatData({
    required this.venueName,
    required this.floors,
    required this.totalSeats,
    required this.grades,
  });
}

class ParsedFloor {
  final String name;
  final List<ParsedBlock> blocks;
  final int totalSeats;

  ParsedFloor({required this.name, required this.blocks, required this.totalSeats});
}

class ParsedBlock {
  final String name;
  final String floor;
  final int rows;
  final int seatsPerRow;
  final int totalSeats;
  final String? grade;
  final String layoutDirection;
  final List<VenueBlockCustomRow> customRows;

  ParsedBlock({
    required this.name,
    required this.floor,
    required this.rows,
    required this.seatsPerRow,
    required this.totalSeats,
    this.grade,
    this.layoutDirection = 'horizontal',
    this.customRows = const [],
  });
}

/// 좌석 배치 파서 유틸리티
class SeatMapParser {
  /// 엑셀 바이트에서 좌석 데이터 파싱
  /// 시트명 = 층 이름, 행: 구역명 | 열 수 | 좌석 수 | 등급(선택)
  static ParsedSeatData? parseExcel(Uint8List bytes, String fileName) {
    try {
      final excelFile = excel_pkg.Excel.decodeBytes(bytes);
      final floors = <ParsedFloor>[];
      var totalSeats = 0;
      final gradesSet = <String>{};

      for (var table in excelFile.tables.keys) {
        final sheet = excelFile.tables[table]!;
        final blocks = <ParsedBlock>[];
        var floorSeats = 0;

        for (var i = 1; i < sheet.maxRows; i++) {
          final row = sheet.row(i);
          if (row.isEmpty || row[0]?.value == null) continue;

          final blockName = row[0]?.value?.toString() ?? '';
          final rowCount = int.tryParse(row[1]?.value?.toString() ?? '') ?? 0;
          final seatsPerRow = int.tryParse(row[2]?.value?.toString() ?? '') ?? 0;
          final grade = row.length > 3 ? row[3]?.value?.toString() : null;

          if (blockName.isNotEmpty && rowCount > 0 && seatsPerRow > 0) {
            final blockSeats = rowCount * seatsPerRow;
            blocks.add(ParsedBlock(
              name: blockName,
              floor: table,
              rows: rowCount,
              seatsPerRow: seatsPerRow,
              totalSeats: blockSeats,
              grade: grade,
            ));
            floorSeats += blockSeats;
            if (grade != null) gradesSet.add(grade);
          }
        }

        if (blocks.isNotEmpty) {
          floors.add(ParsedFloor(name: table, blocks: blocks, totalSeats: floorSeats));
          totalSeats += floorSeats;
        }
      }

      if (floors.isEmpty) return null;

      final grades = gradesSet.map((g) => SeatGrade(
        name: g,
        price: getDefaultPrice(g),
        colorHex: getDefaultColor(g),
      )).toList();

      return ParsedSeatData(
        venueName: fileName.replaceAll(RegExp(r'\.(xlsx|xls)$'), ''),
        floors: floors,
        totalSeats: totalSeats,
        grades: grades,
      );
    } catch (_) {
      return null;
    }
  }

  /// 프리셋 공연장 데이터 생성
  static ParsedSeatData createPresetData(Venue preset, List<SeatGrade> grades) {
    return ParsedSeatData(
      venueName: preset.name,
      floors: preset.floors.map((f) => ParsedFloor(
        name: f.name,
        blocks: f.blocks.map((b) => ParsedBlock(
          name: b.name,
          floor: f.name,
          rows: b.rows,
          seatsPerRow: b.seatsPerRow,
          totalSeats: b.totalSeats,
          grade: b.grade,
          layoutDirection: b.layoutDirection,
          customRows: b.customRows,
        )).toList(),
        totalSeats: f.totalSeats,
      )).toList(),
      totalSeats: preset.totalSeats,
      grades: grades,
    );
  }

  /// 등급별 기본 가격
  static int getDefaultPrice(String grade) {
    switch (grade.toUpperCase()) {
      case 'VIP': return 150000;
      case 'R': return 110000;
      case 'S': return 88000;
      case 'A': return 66000;
      default: return 55000;
    }
  }

  /// 등급별 기본 컬러 (다크 테마용)
  static String getDefaultColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'VIP': return '#C9A84C';
      case 'R': return '#30D158';
      case 'S': return '#0A84FF';
      case 'A': return '#FF9F0A';
      default: return '#8E8E93';
    }
  }
}
