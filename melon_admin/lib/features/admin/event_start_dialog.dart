import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'excel_seat_upload_helper.dart';

/// "공연 시작" 원클릭 다이얼로그
/// Step 1: 좌석 확인 (없으면 좌석 관리로 이동)
/// Step 2: 좌석 배정 (등급별 자동)
/// Step 3: QR 즉시 공개
/// → 체크인 대시보드 이동
class EventStartDialog extends StatefulWidget {
  final Event event;

  const EventStartDialog({super.key, required this.event});

  static Future<void> show(BuildContext context, Event event) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => EventStartDialog(event: event),
    );
  }

  @override
  State<EventStartDialog> createState() => _EventStartDialogState();
}

enum _Step { check, assign, reveal, done }

class _EventStartDialogState extends State<EventStartDialog> {
  _Step _currentStep = _Step.check;
  bool _isProcessing = false;
  String _statusText = '';
  final List<String> _logs = [];
  bool _hasSeats = false;
  int _seatCount = 0;
  int _availableCount = 0;
  int _unassignedCount = 0;

  static const _gradeOrder = ['VIP', 'R', 'S', 'A'];

  List<String> get _eventGrades {
    final grades = widget.event.priceByGrade?.keys.toList() ?? [];
    grades.sort((a, b) {
      final ai = _gradeOrder.indexOf(a);
      final bi = _gradeOrder.indexOf(b);
      return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
    });
    return grades;
  }

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isProcessing = true;
      _statusText = '공연 상태 확인 중...';
    });

    try {
      // 좌석 수 확인 (최상위 seats 컬렉션)
      final seatSnap = await FirebaseFirestore.instance
          .collection('seats')
          .where('eventId', isEqualTo: widget.event.id)
          .get();
      _seatCount = seatSnap.docs.length;
      _availableCount = seatSnap.docs
          .where((d) => (d.data()['status'] ?? '') == 'available')
          .length;
      _hasSeats = _seatCount > 0;

      if (_hasSeats) {
        _addLog('✓ 좌석 ${_seatCount}석 등록됨 (빈자리 ${_availableCount}석)');
      } else {
        _addLog('⚠ 좌석 데이터 없음 — 좌석 관리에서 먼저 등록하세요');
      }

      // 미확정 티켓 수 확인
      final unassignedSnap = await FirebaseFirestore.instance
          .collection('mobileTickets')
          .where('eventId', isEqualTo: widget.event.id)
          .where('status', isEqualTo: 'active')
          .where('seatId', isEqualTo: null)
          .get();
      _unassignedCount = unassignedSnap.docs.length;

      if (_unassignedCount > 0) {
        _addLog('📋 미확정 티켓 ${_unassignedCount}매 — 배정 필요');
      } else {
        _addLog('— 미확정 티켓 없음 (이미 배정 완료이거나 티켓 미발행)');
      }

      // revealAt 확인
      final eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .get();
      final revealAt = eventDoc.data()?['revealAt'];
      if (revealAt != null) {
        final revealTime = (revealAt as Timestamp).toDate();
        if (revealTime.isBefore(DateTime.now())) {
          _addLog('✓ QR 이미 공개됨');
        } else {
          _addLog('🔒 QR 공개 예정: ${_formatTime(revealTime)}');
        }
      }
    } catch (e) {
      _addLog('✗ 상태 확인 오류: $e');
    }

    setState(() {
      _isProcessing = false;
      _currentStep = _Step.check;
    });
  }

  String _formatTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _addLog(String msg) {
    setState(() => _logs.add(msg));
  }

  // ── 좌석 배정 ──
  Future<void> _assignSeats() async {
    setState(() {
      _isProcessing = true;
      _currentStep = _Step.assign;
      _statusText = '좌석 배정 시작...';
    });

    final grades = _eventGrades;
    if (grades.isEmpty) {
      _addLog('⚠ 등급 정보 없음 — 배정 스킵');
      setState(() {
        _isProcessing = false;
        _currentStep = _Step.reveal;
      });
      return;
    }

    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    int totalAssigned = 0;

    for (final grade in grades) {
      setState(() => _statusText = '$grade석 배정 중...');

      try {
        final result = await functions
            .httpsCallable('assignDeferredSeats')
            .call({'eventId': widget.event.id, 'seatGrade': grade});

        final assigned = result.data['assigned'] as int? ?? 0;
        totalAssigned += assigned;
        if (assigned > 0) {
          _addLog('✓ $grade석 ${assigned}매 배정');
        } else {
          _addLog('— $grade석 배정 대상 없음');
        }
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('미확정') || msg.contains('없습니다') || msg.contains('no-unassigned')) {
          _addLog('— $grade석 미확정 티켓 없음');
        } else {
          _addLog('⚠ $grade석 오류: ${_shortenError(e)}');
        }
      }
    }

    _addLog(totalAssigned > 0 ? '📋 총 ${totalAssigned}매 배정 완료' : '📋 배정 대상 없음');
    setState(() {
      _isProcessing = false;
      _currentStep = _Step.reveal;
    });
  }

  String _shortenError(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}...' : s;
  }

  // ── QR 공개 ──
  Future<void> _revealQR() async {
    setState(() {
      _isProcessing = true;
      _currentStep = _Step.reveal;
      _statusText = 'QR 코드 공개 중...';
    });

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      await functions
          .httpsCallable('revealSeatsNow')
          .call({'eventId': widget.event.id});

      _addLog('✓ QR 코드 + 좌석정보 즉시 공개');
      setState(() {
        _isProcessing = false;
        _currentStep = _Step.done;
      });
    } catch (e) {
      _addLog('✗ QR 공개 실패: ${_shortenError(e)}');
      setState(() => _isProcessing = false);
    }
  }

  // ── 전체 자동 실행 ──
  Future<void> _runAll() async {
    await _assignSeats();
    if (mounted && _currentStep == _Step.reveal) {
      await _revealQR();
    }
  }

  void _goToCheckin() {
    Navigator.of(context).pop();
    context.go('/checkin?eventId=${widget.event.id}');
  }

  void _goToSeatManager() {
    Navigator.of(context).pop();
    context.go('/events/${widget.event.id}/seats');
  }

  // ── TADMIN 잔여석 Excel 파서 (telegram-bot.js parseUnsoldSeats 포팅) ──
  // 반환: Set<seatKey> (예: "G구역-1층-3-12")
  Set<String>? _parseTadminUnsoldExcel(List<int> bytes) {
    Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      _addLog('⚠ TADMIN 파서: Excel 디코딩 실패 (${e.toString().length > 50 ? e.toString().substring(0, 50) : e})');
      return null;
    }
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];
    if (sheet == null) return null;

    // 헤더 행 찾기 (더 유연한 매칭)
    int headerIdx = -1;
    for (int r = 0; r < sheet.maxRows && r < 10; r++) {
      final row = sheet.row(r);
      final cells = row.map((c) => (c?.value?.toString().trim() ?? '')).toList();
      if (cells.any((c) =>
          c.contains('좌석등급') || c.contains('등급') ||
          c.contains('좌석번호') || c == '열')) {
        headerIdx = r;
        break;
      }
    }
    if (headerIdx < 0) {
      _addLog('⚠ TADMIN 파서: 헤더 행 없음');
      return null;
    }

    // 컬럼 인덱스 자동 감지
    final headerRow = sheet.row(headerIdx)
        .map((c) => (c?.value?.toString().trim() ?? ''))
        .toList();
    _addLog('📋 TADMIN 헤더: ${headerRow.where((h) => h.isNotEmpty).join(", ")}');

    int findCol(bool Function(String) test) {
      for (int i = 0; i < headerRow.length; i++) {
        if (test(headerRow[i])) return i;
      }
      return -1;
    }

    final gradeIdx = findCol((c) => c.contains('좌석등급') || c == '등급');
    final floorIdx = findCol((c) => c == '층' || c.contains('층'));
    final sectionRowIdx = findCol((c) => c == '열' || c.contains('열'));
    final seatsIdx = findCol((c) => c.contains('좌석번호') || c.contains('번호'));

    // TADMIN 형식 검증: 좌석번호 컬럼이 없으면 TADMIN이 아님
    if (seatsIdx < 0) {
      _addLog('⚠ TADMIN 파서: 좌석번호 컬럼 없음');
      return null;
    }

    final colGrade = gradeIdx >= 0 ? gradeIdx : 3;
    final colFloor = floorIdx >= 0 ? floorIdx : 4;
    final colSR = sectionRowIdx >= 0 ? sectionRowIdx : 5;
    final colSeats = seatsIdx >= 0 ? seatsIdx : 7;

    final seatKeys = <String>{};
    String lastGrade = '';
    String lastFloor = '';
    final gradeCounts = <String, int>{};

    // 열 컬럼 패턴들:
    // 1. "G구역 3열", "BL5구역 1열" → section=G구역, row=3
    // 2. "A10열", "B9열" → block=A, row=10
    // 3. "합창F1열" → block=합창F, row=1
    // 4. "합창H열" → block=합창H, row=1 (행번호 없음)
    final srPatternSection = RegExp(r'^(.+?구역)\s*(\d+)(?:열|행)?$');
    final srPatternBlock = RegExp(r'^([A-Za-z가-힣]+?)(\d+)열$');
    final srPatternNoRow = RegExp(r'^([A-Za-z가-힣]+)열$');

    for (int r = headerIdx + 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      if (row.length < 3) continue;

      String cell(int idx) =>
          idx < row.length ? (row[idx]?.value?.toString().trim() ?? '') : '';

      // 등급 (병합셀 → 이전 값 유지)
      final gradeRaw = cell(colGrade);
      if (gradeRaw.isNotEmpty && gradeRaw.contains('석')) lastGrade = gradeRaw;
      if (lastGrade.isEmpty) continue;

      // 층 (병합셀 → 이전 값 유지)
      final floorRaw = cell(colFloor);
      if (floorRaw.isNotEmpty) lastFloor = floorRaw;

      // 열 컬럼 파싱
      final sectionRowRaw = cell(colSR);
      if (sectionRowRaw.isEmpty) continue;

      String? section;
      int? rowNum;

      // 패턴1: "G구역 3열" (구역 포함)
      var srMatch = srPatternSection.firstMatch(sectionRowRaw);
      if (srMatch != null) {
        section = srMatch.group(1)!;
        rowNum = int.tryParse(srMatch.group(2)!);
      }
      // 패턴2: "A10열" (블록+숫자+열)
      if (section == null) {
        srMatch = srPatternBlock.firstMatch(sectionRowRaw);
        if (srMatch != null) {
          section = srMatch.group(1)!;
          rowNum = int.tryParse(srMatch.group(2)!);
        }
      }
      // 패턴3: "합창H열" (행번호 없음)
      if (section == null) {
        srMatch = srPatternNoRow.firstMatch(sectionRowRaw);
        if (srMatch != null) {
          section = srMatch.group(1)!;
          rowNum = 1;
        }
      }
      if (section == null || rowNum == null) continue;

      // 층 정규화: "1층", "2층" 등
      final floorMatch = RegExp(r'(\d+)층').firstMatch(lastFloor);
      final floor = floorMatch != null ? '${floorMatch.group(1)}층' : lastFloor;

      // 좌석번호 파싱: "1 2 3 4" or "1,2,3,4"
      final seatsRaw = cell(colSeats);
      if (seatsRaw.isEmpty) continue;

      final seatNums = seatsRaw.split(RegExp(r'[\s,]+'))
          .map((s) => int.tryParse(s.trim()))
          .where((n) => n != null && n > 0)
          .cast<int>()
          .toList();

      for (final num in seatNums) {
        // seatKey: {section}-{floor}-{row}-{number}
        // 예: G구역-1층-3-12
        seatKeys.add('$section-$floor-$rowNum-$num');
      }
      gradeCounts[lastGrade] = (gradeCounts[lastGrade] ?? 0) + seatNums.length;
    }

    if (seatKeys.isNotEmpty) {
      final summary = gradeCounts.entries
          .map((e) => '${e.key} ${e.value}석')
          .join(', ');
      _addLog('📋 TADMIN 파싱: ${seatKeys.length}석 ($summary)');
    }

    return seatKeys.isEmpty ? null : seatKeys;
  }

  // ── 빈자리 엑셀 업로드 ──
  // TADMIN 잔여석 Excel 감지 → 전용 파서 사용
  // 일반 Excel → EnhancedExcelParser 사용
  Future<void> _uploadSeatsInline() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) {
      _addLog('✗ 파일을 읽을 수 없습니다');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusText = '엑셀 파싱 중...';
    });

    try {
      final byteList = bytes.toList();

      // 1. TADMIN 형식 시도
      final tadminKeys = _parseTadminUnsoldExcel(byteList);

      // 2. 업로드된 seatKey 세트 결정
      Set<String> uploadedKeys;

      if (tadminKeys != null) {
        // TADMIN 형식으로 파싱 성공
        uploadedKeys = tadminKeys;
      } else {
        // 일반 형식 → EnhancedExcelParser
        final parseResult = EnhancedExcelParser.parse(byteList);

        if (parseResult.hasErrors) {
          for (final error in parseResult.errors) {
            _addLog('✗ $error');
          }
          setState(() => _isProcessing = false);
          return;
        }

        if (parseResult.totalSeats == 0) {
          _addLog('⚠ 파싱된 좌석이 없습니다');
          setState(() => _isProcessing = false);
          return;
        }

        if (!_hasSeats) {
          // ── 좌석 없음: 새로 생성 (기존 로직) ──
          await _createNewSeats(parseResult);
          setState(() => _isProcessing = false);
          return;
        }

        // 일반 형식에서 seatKey 추출
        uploadedKeys = {};
        for (final seat in parseResult.seats) {
          final key = seat.row.isNotEmpty
              ? '${seat.zone}-${seat.floor}-${seat.row}-${seat.number}'
              : '${seat.zone}-${seat.floor}-${seat.number}';
          uploadedKeys.add(key);
        }

        for (final w in parseResult.warnings) {
          _addLog('⚠ $w');
        }
      }

      if (!_hasSeats) {
        _addLog('⚠ 기존 좌석이 없습니다. 좌석 관리에서 먼저 등록하세요.');
        setState(() => _isProcessing = false);
        return;
      }

      // ── 기존 좌석 있음: seatKey 매칭으로 빈자리 표시 ──
      await _matchSeatsWithKeys(uploadedKeys);
    } catch (e) {
      _addLog('✗ 업로드 오류: ${_shortenError(e)}');
    }

    setState(() => _isProcessing = false);
  }

  // ── seatKey 매칭으로 빈자리 설정 ──
  Future<void> _matchSeatsWithKeys(Set<String> uploadedKeys) async {
    setState(() => _statusText = '빈자리 ${uploadedKeys.length}석 매칭 중...');

    final db = FirebaseFirestore.instance;
    final existingSnap = await db
        .collection('seats')
        .where('eventId', isEqualTo: widget.event.id)
        .get();

    var batch = db.batch();
    var pending = 0;
    int matched = 0;
    int markedSold = 0;

    // 디버깅: seatKey 샘플 수집
    final dbKeySamples = <String>[];
    final uploadKeySamples = uploadedKeys.take(3).toList();

    for (final doc in existingSnap.docs) {
      final data = doc.data();
      final seatKey = data['seatKey'] as String? ?? '';
      final currentStatus = data['status'] as String? ?? '';

      // 디버깅용 샘플
      if (dbKeySamples.length < 3 && seatKey.isNotEmpty) {
        dbKeySamples.add(seatKey);
      }

      if (uploadedKeys.contains(seatKey)) {
        if (currentStatus != 'available') {
          batch.update(doc.reference, {'status': 'available'});
          pending++;
        }
        matched++;
      } else {
        if (currentStatus == 'available') {
          batch.update(doc.reference, {'status': 'sold'});
          pending++;
          markedSold++;
        }
      }

      if (pending >= 400) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();

    _availableCount = matched;
    final notFound = uploadedKeys.length - matched;
    _addLog('✓ 빈자리 ${matched}석 설정 완료');
    if (markedSold > 0) _addLog('— 판매석 ${markedSold}석 → sold 처리');
    if (notFound > 0) {
      _addLog('⚠ 매칭 안됨 ${notFound}석 (seatKey 불일치)');
      // 디버깅: seatKey 형식 비교 표시
      if (dbKeySamples.isNotEmpty) {
        _addLog('  DB: ${dbKeySamples.join(", ")}');
      }
      if (uploadKeySamples.isNotEmpty) {
        _addLog('  업로드: ${uploadKeySamples.join(", ")}');
      }
    }
  }

  // ── 새 좌석 생성 (기존 좌석 삭제 후 새로 생성) ──
  Future<void> _createNewSeats(ExcelParseResult parseResult) async {
    final db = FirebaseFirestore.instance;

    // 기존 좌석 삭제
    if (_seatCount > 0) {
      setState(() => _statusText = '기존 ${_seatCount}석 삭제 중...');
      final oldSnap = await db
          .collection('seats')
          .where('eventId', isEqualTo: widget.event.id)
          .get();
      var delBatch = db.batch();
      var delPending = 0;
      for (final doc in oldSnap.docs) {
        delBatch.delete(doc.reference);
        delPending++;
        if (delPending >= 400) {
          await delBatch.commit();
          delBatch = db.batch();
          delPending = 0;
        }
      }
      if (delPending > 0) await delBatch.commit();
      _addLog('✓ 기존 ${oldSnap.docs.length}석 삭제');
    }

    setState(() => _statusText = '${parseResult.totalSeats}석 업로드 중...');

    var batch = db.batch();
    var pending = 0;
    int count = 0;

    for (final seat in parseResult.seats) {
      final seatKey = seat.row.isNotEmpty
          ? '${seat.zone}-${seat.floor}-${seat.row}-${seat.number}'
          : '${seat.zone}-${seat.floor}-${seat.number}';

      final docRef = db.collection('seats').doc();
      batch.set(docRef, {
        'eventId': widget.event.id,
        'block': seat.zone,
        'floor': seat.floor,
        'row': seat.row,
        'number': seat.number,
        'seatKey': seatKey,
        'grade': seat.grade,
        'status': 'available',
      });
      count++;
      pending++;

      if (pending >= 400) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();

    await db.collection('events').doc(widget.event.id).update({
      'totalSeats': count,
      'availableSeats': count,
    });

    _seatCount = count;
    _availableCount = count;
    _hasSeats = true;

    final summary = parseResult.gradeCounts.entries
        .map((e) => '${e.key} ${e.value}석')
        .join(', ');
    _addLog('✓ $count석 업로드 완료 ($summary)');

    for (final w in parseResult.warnings) {
      _addLog('⚠ $w');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AdminTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AdminTheme.border, width: 0.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: AdminTheme.border),
            _buildStepIndicator(),
            const Divider(height: 1, color: AdminTheme.border),
            Flexible(child: _buildBody()),
            const Divider(height: 1, color: AdminTheme.border),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AdminTheme.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.play_circle_outline_rounded,
                color: AdminTheme.gold, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '공연 시작',
                  style: AdminTheme.serif(
                    fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.event.title,
                  style: AdminTheme.sans(
                    fontSize: 12, color: AdminTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: AdminTheme.textTertiary),
            onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = [
      ('상태 확인', _Step.check),
      ('좌석 배정', _Step.assign),
      ('QR 공개', _Step.reveal),
      ('완료', _Step.done),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1,
                  color: _currentStep.index >= i
                      ? AdminTheme.gold : AdminTheme.border,
                ),
              ),
            _StepDot(
              label: steps[i].$1,
              index: i + 1,
              isActive: _currentStep.index == i,
              isDone: _currentStep.index > i,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_logs.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminTheme.background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AdminTheme.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _logs
                    .map((log) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            log,
                            style: AdminTheme.sans(
                              fontSize: 12,
                              color: log.startsWith('✗')
                                  ? AdminTheme.error
                                  : log.startsWith('✓')
                                      ? AdminTheme.success
                                      : log.startsWith('⚠')
                                          ? AdminTheme.warning
                                          : AdminTheme.textSecondary,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          if (_isProcessing) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AdminTheme.gold),
                ),
                const SizedBox(width: 10),
                Text(_statusText,
                    style: AdminTheme.sans(
                        fontSize: 13, color: AdminTheme.textSecondary)),
              ],
            ),
          ],
          if (!_isProcessing && _currentStep == _Step.done) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AdminTheme.success, size: 20),
                const SizedBox(width: 8),
                Text(
                  '공연 준비 완료!',
                  style: AdminTheme.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '체크인 대시보드에서 실시간 입장 현황을 확인하세요.',
              style: AdminTheme.sans(
                  fontSize: 12, color: AdminTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  // ── 강제 시작 확인 ──
  Future<void> _confirmForceStart() async {
    // 공연 시간 체크
    final eventDate = widget.event.startAt;
    if (eventDate.isAfter(DateTime.now())) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AdminTheme.border, width: 0.5),
          ),
          title: Text('강제 시작',
              style: AdminTheme.serif(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Text(
            '아직 공연 시간이 아닙니다.\n(${_formatTime(eventDate)})\n\n강제로 시작할까요?',
            style: AdminTheme.sans(fontSize: 13, color: AdminTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('취소',
                  style: AdminTheme.sans(fontSize: 13, color: AdminTheme.textTertiary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.gold,
                foregroundColor: AdminTheme.onAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('강제로 시작'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _runAll();
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!_isProcessing && _currentStep != _Step.done)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('취소',
                  style: AdminTheme.sans(
                      fontSize: 13, color: AdminTheme.textTertiary)),
            ),
          ..._buildActionButtons(),
        ],
      ),
    );
  }

  List<Widget> _buildActionButtons() {
    if (_isProcessing) return [];

    switch (_currentStep) {
      case _Step.check:
        if (!_hasSeats) {
          return [
            ElevatedButton.icon(
              onPressed: _uploadSeatsInline,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('엑셀 좌석 업로드'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.gold,
                foregroundColor: AdminTheme.onAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _goToSeatManager,
              child: Text('좌석 관리',
                  style: AdminTheme.sans(
                      fontSize: 13, color: AdminTheme.textTertiary)),
            ),
          ];
        }
        return [
          ElevatedButton.icon(
            onPressed: _uploadSeatsInline,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('빈자리 업로드'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminTheme.surface,
              foregroundColor: AdminTheme.textSecondary,
              side: const BorderSide(color: AdminTheme.border, width: 0.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _confirmForceStart,
            icon: const Icon(Icons.rocket_launch_rounded, size: 18),
            label: const Text('공연 시작'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminTheme.gold,
              foregroundColor: AdminTheme.onAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ];
      case _Step.assign:
        return [
          ElevatedButton.icon(
            onPressed: _assignSeats,
            icon: const Icon(Icons.event_seat_rounded, size: 18),
            label: const Text('좌석 배정'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminTheme.gold,
              foregroundColor: AdminTheme.onAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ];
      case _Step.reveal:
        return [
          ElevatedButton.icon(
            onPressed: _revealQR,
            icon: const Icon(Icons.qr_code_rounded, size: 18),
            label: const Text('QR 공개'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminTheme.gold,
              foregroundColor: AdminTheme.onAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ];
      case _Step.done:
        return [
          ElevatedButton.icon(
            onPressed: _goToCheckin,
            icon: const Icon(Icons.dashboard_rounded, size: 18),
            label: const Text('체크인 대시보드'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminTheme.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ];
    }
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final int index;
  final bool isActive;
  final bool isDone;

  const _StepDot({
    required this.label,
    required this.index,
    required this.isActive,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? AdminTheme.success
                : isActive ? AdminTheme.gold : AdminTheme.background,
            border: Border.all(
              color: isDone ? AdminTheme.success
                  : isActive ? AdminTheme.gold : AdminTheme.border,
              width: 1.5,
            ),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text('$index',
                    style: AdminTheme.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? AdminTheme.onAccent : AdminTheme.textTertiary,
                    )),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: AdminTheme.sans(
              fontSize: 9,
              color: isActive || isDone
                  ? AdminTheme.textPrimary : AdminTheme.textTertiary,
            )),
      ],
    );
  }
}
