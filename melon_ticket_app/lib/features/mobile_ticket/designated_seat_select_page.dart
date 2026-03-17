import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// =============================================================================
// 2-3b: 지정석 좌석 선택 페이지 (비로그인, accessToken + 전화번호 끝4자리 인증)
// 플로우: 링크 → 전화번호 인증 → 등급 좌석맵 → 선택 → 확정 (+ 1회 변경)
// =============================================================================

const _cfBase =
    'https://us-central1-melon-ticket-mvp-2026.cloudfunctions.net';

const _cream = Color(0xFFFAF8F5);
const _burgundy = Color(0xFF3B0D11);
const _burgundyDeep = Color(0xFF1A0508);
const _textDark = Color(0xFF1C1917);
const _textMid = Color(0xFF78716C);
const _divider = Color(0xFFE7E0D8);
const _gold = Color(0xFFC9A84C);

const _gradeColors = {
  'VIP': Color(0xFFC9A84C),
  'R': Color(0xFF4CAF50),
  'S': Color(0xFF2196F3),
  'A': Color(0xFFFFC107),
};

class DesignatedSeatSelectPage extends StatefulWidget {
  final String accessToken;

  const DesignatedSeatSelectPage({super.key, required this.accessToken});

  @override
  State<DesignatedSeatSelectPage> createState() =>
      _DesignatedSeatSelectPageState();
}

class _DesignatedSeatSelectPageState extends State<DesignatedSeatSelectPage> {
  // ── 상태 ──
  _PageStep _step = _PageStep.phoneVerify;
  bool _loading = false;
  String? _error;

  // 인증
  final _phoneController = TextEditingController();

  // 데이터
  Map<String, dynamic>? _ticket;
  Map<String, dynamic>? _event;
  List<Map<String, dynamic>> _availableSeats = [];

  // 좌석 선택
  String? _selectedSeatId;

  // 확정 결과
  String? _confirmedSeatInfo;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  // ── 전화번호 인증 & 정보 로드 ──
  Future<void> _verifyAndLoad() async {
    final phoneLast4 = _phoneController.text.trim();
    if (phoneLast4.length != 4 || int.tryParse(phoneLast4) == null) {
      setState(() => _error = '전화번호 끝 4자리를 입력해주세요');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.post(
        Uri.parse('$_cfBase/getDesignatedSeatInfo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'accessToken': widget.accessToken,
          'phoneLast4': phoneLast4,
        }),
      );

      final body = jsonDecode(resp.body);
      if (resp.statusCode != 200) {
        setState(() {
          _error = body['error'] ?? '인증 실패';
          _loading = false;
        });
        return;
      }

      _ticket = Map<String, dynamic>.from(body['ticket']);
      _event = Map<String, dynamic>.from(body['event']);
      _availableSeats = (body['availableSeats'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // 이미 좌석이 배정된 경우
      if (_ticket!['seatId'] != null) {
        setState(() {
          _step = _PageStep.alreadyAssigned;
          _loading = false;
        });
        return;
      }

      // 마감 확인
      final deadlineStr = _ticket!['seatSelectionDeadline'] as String?;
      if (deadlineStr != null) {
        final deadline = DateTime.tryParse(deadlineStr);
        if (deadline != null && DateTime.now().isAfter(deadline)) {
          setState(() {
            _error = '좌석 선택 기한이 만료되었습니다. 자동 배정을 기다려주세요.';
            _loading = false;
          });
          return;
        }
      }

      setState(() {
        _step = _PageStep.seatMap;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '서버 연결 실패: $e';
        _loading = false;
      });
    }
  }

  // ── 좌석 확정 ──
  Future<void> _confirmSeat() async {
    if (_selectedSeatId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.post(
        Uri.parse('$_cfBase/confirmDesignatedSeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'accessToken': widget.accessToken,
          'phoneLast4': _phoneController.text.trim(),
          'seatId': _selectedSeatId,
        }),
      );

      final body = jsonDecode(resp.body);
      if (resp.statusCode != 200) {
        setState(() {
          _error = body['error'] ?? '좌석 확정 실패';
          _loading = false;
        });
        return;
      }

      setState(() {
        _confirmedSeatInfo = body['seatInfo'];
        _step = _PageStep.confirmed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '서버 연결 실패';
        _loading = false;
      });
    }
  }

  // ── 좌석 변경 ──
  Future<void> _changeSeat() async {
    if (_selectedSeatId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.post(
        Uri.parse('$_cfBase/changeDesignatedSeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'accessToken': widget.accessToken,
          'phoneLast4': _phoneController.text.trim(),
          'newSeatId': _selectedSeatId,
        }),
      );

      final body = jsonDecode(resp.body);
      if (resp.statusCode != 200) {
        setState(() {
          _error = body['error'] ?? '좌석 변경 실패';
          _loading = false;
        });
        return;
      }

      setState(() {
        _confirmedSeatInfo = body['seatInfo'];
        _step = _PageStep.confirmed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '서버 연결 실패';
        _loading = false;
      });
    }
  }

  // ── 좌석 변경 모드 진입 ──
  void _enterChangeMode() {
    setState(() {
      _step = _PageStep.seatMap;
      _selectedSeatId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _burgundyDeep,
        foregroundColor: Colors.white,
        title: const Text('좌석 선택', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: switch (_step) {
          _PageStep.phoneVerify => _buildPhoneVerify(),
          _PageStep.seatMap => _buildSeatMap(),
          _PageStep.confirmed => _buildConfirmed(),
          _PageStep.alreadyAssigned => _buildAlreadyAssigned(),
        },
      ),
    );
  }

  // ═══ Step 1: 전화번호 인증 ═══
  Widget _buildPhoneVerify() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.phone_android_rounded, size: 64, color: _burgundy),
          const SizedBox(height: 24),
          const Text(
            '본인 확인',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '구매 시 사용한 전화번호 끝 4자리를 입력해주세요',
            style: TextStyle(fontSize: 14, color: _textMid),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 12,
              color: _textDark,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '●  ●  ●  ●',
              hintStyle: TextStyle(
                fontSize: 32,
                color: _textMid.withValues(alpha: 0.3),
                letterSpacing: 12,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _gold, width: 2),
              ),
            ),
            onSubmitted: (_) => _verifyAndLoad(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _verifyAndLoad,
              style: ElevatedButton.styleFrom(
                backgroundColor: _burgundy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                disabledBackgroundColor: _burgundy.withValues(alpha: 0.5),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══ Step 2: 좌석맵 ═══
  Widget _buildSeatMap() {
    final grade = _ticket?['seatGrade'] ?? '';
    final gradeColor = _gradeColors[grade] ?? _gold;
    final eventTitle = _event?['title'] ?? '';
    final venueName = _event?['venueName'] ?? '';
    final deadlineStr = _ticket?['seatSelectionDeadline'] as String?;
    final isChangeMode = (_ticket?['seatChangeCount'] ?? 0) == 0 &&
        _ticket?['seatId'] != null;

    // 좌석을 block → floor → row → number 순으로 그룹화
    final seatsByBlock = <String, List<Map<String, dynamic>>>{};
    for (final seat in _availableSeats) {
      final key = '${seat['floor'] ?? ''} ${seat['block'] ?? ''}';
      seatsByBlock.putIfAbsent(key, () => []).add(seat);
    }

    return Column(
      children: [
        // 헤더
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eventTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              if (venueName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  venueName,
                  style: const TextStyle(fontSize: 13, color: _textMid),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: gradeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$grade석',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: gradeColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '잔여 ${_availableSeats.length}석',
                    style: const TextStyle(fontSize: 13, color: _textMid),
                  ),
                  const Spacer(),
                  if (deadlineStr != null)
                    _DeadlineChip(deadlineStr: deadlineStr),
                ],
              ),
              if (isChangeMode) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz_rounded,
                          size: 18, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '좌석 변경 모드 (1회 제한)',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: _divider),

        // 스테이지 표시
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: _burgundyDeep.withValues(alpha: 0.05),
          child: const Center(
            child: Text(
              'S T A G E',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textMid,
                letterSpacing: 4,
              ),
            ),
          ),
        ),

        // 좌석 목록
        Expanded(
          child: _availableSeats.isEmpty
              ? const Center(
                  child: Text(
                    '선택 가능한 좌석이 없습니다',
                    style: TextStyle(color: _textMid, fontSize: 15),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: seatsByBlock.length,
                  itemBuilder: (context, index) {
                    final entry = seatsByBlock.entries.elementAt(index);
                    final blockName = entry.key.trim();
                    final seats = entry.value
                      ..sort((a, b) {
                        final rowCmp = (a['row'] ?? '')
                            .toString()
                            .compareTo((b['row'] ?? '').toString());
                        if (rowCmp != 0) return rowCmp;
                        return (a['number'] as int)
                            .compareTo(b['number'] as int);
                      });

                    // row별로 그룹화
                    final seatsByRow = <String, List<Map<String, dynamic>>>{};
                    for (final s in seats) {
                      final row = (s['row'] ?? '').toString();
                      seatsByRow.putIfAbsent(row, () => []).add(s);
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 12,
                            bottom: 6,
                            left: 4,
                          ),
                          child: Text(
                            blockName.isNotEmpty ? '$blockName 구역' : '좌석',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _textDark,
                            ),
                          ),
                        ),
                        ...seatsByRow.entries.map((rowEntry) {
                          final rowName = rowEntry.key;
                          final rowSeats = rowEntry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 36,
                                  child: Text(
                                    rowName.isNotEmpty ? '$rowName열' : '',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _textMid,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: rowSeats.map((seat) {
                                      final seatId = seat['id'] as String;
                                      final isSelected =
                                          _selectedSeatId == seatId;
                                      final isHeld = seat['heldBy'] != null;

                                      return GestureDetector(
                                        onTap: isHeld
                                            ? null
                                            : () {
                                                setState(() {
                                                  _selectedSeatId = isSelected
                                                      ? null
                                                      : seatId;
                                                });
                                              },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: isHeld
                                                ? Colors.grey.shade300
                                                : isSelected
                                                    ? gradeColor
                                                    : Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isSelected
                                                  ? gradeColor
                                                  : _divider,
                                              width: isSelected ? 2 : 1,
                                            ),
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                      color: gradeColor
                                                          .withValues(
                                                            alpha: 0.3,
                                                          ),
                                                      blurRadius: 8,
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${seat['number']}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isHeld
                                                  ? Colors.grey
                                                  : isSelected
                                                      ? Colors.white
                                                      : _textDark,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
        ),

        // 선택한 좌석 정보 + 확정 버튼
        if (_selectedSeatId != null) _buildBottomBar(gradeColor, isChangeMode),

        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.red.shade50,
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildBottomBar(Color gradeColor, bool isChangeMode) {
    final seat = _availableSeats.firstWhere(
      (s) => s['id'] == _selectedSeatId,
      orElse: () => {},
    );
    if (seat.isEmpty) return const SizedBox.shrink();

    final seatLabel = [
      seat['floor'],
      seat['block'],
      seat['row'] != null ? '${seat['row']}열' : null,
      '${seat['number']}번',
    ].where((e) => e != null && e.toString().isNotEmpty).join(' ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.event_seat_rounded, color: gradeColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    seatLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading
                    ? null
                    : (isChangeMode ? _changeSeat : _confirmSeat),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isChangeMode ? Colors.orange : _burgundy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  disabledBackgroundColor: _burgundy.withValues(alpha: 0.5),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        isChangeMode ? '좌석 변경 확정' : '이 좌석으로 확정',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══ Step 3: 확정 완료 ═══
  Widget _buildConfirmed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                size: 56,
                color: Colors.green.shade600,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '좌석이 확정되었습니다!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _confirmedSeatInfo ?? '',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '모바일 티켓에서 좌석 정보를 확인하실 수 있습니다',
              style: TextStyle(
                fontSize: 14,
                color: _textMid,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  // 모바일 티켓 페이지로 이동
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _burgundy,
                  side: const BorderSide(color: _burgundy),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  '모바일 티켓 보기',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══ 이미 배정된 상태 ═══
  Widget _buildAlreadyAssigned() {
    final seatInfo = _ticket?['seatInfo'] ?? '좌석 정보 없음';
    final canChange = (_ticket?['seatChangeCount'] ?? 0) < 1;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.event_seat_rounded,
              size: 64,
              color: _gold,
            ),
            const SizedBox(height: 24),
            const Text(
              '이미 좌석이 배정되었습니다',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                seatInfo,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (canChange) ...[
              Text(
                '좌석 변경은 1회만 가능합니다',
                style: TextStyle(fontSize: 13, color: _textMid),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _enterChangeMode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '좌석 변경하기',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ] else ...[
              Text(
                '좌석 변경 횟수를 모두 사용하였습니다',
                style: TextStyle(fontSize: 13, color: Colors.red.shade400),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _burgundy,
                  side: const BorderSide(color: _burgundy),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  '모바일 티켓 보기',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PageStep { phoneVerify, seatMap, confirmed, alreadyAssigned }

// ── 마감 카운트다운 칩 ──
class _DeadlineChip extends StatefulWidget {
  final String deadlineStr;
  const _DeadlineChip({required this.deadlineStr});

  @override
  State<_DeadlineChip> createState() => _DeadlineChipState();
}

class _DeadlineChipState extends State<_DeadlineChip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = DateTime.tryParse(widget.deadlineStr);
    if (deadline == null) return const SizedBox.shrink();

    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '마감됨',
          style: TextStyle(
            fontSize: 12,
            color: Colors.red.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final hours = remaining.inHours;
    final mins = remaining.inMinutes % 60;
    final label = hours > 0 ? '${hours}시간 ${mins}분 남음' : '${mins}분 남음';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: remaining.inHours < 2
            ? Colors.red.shade50
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 14,
            color: remaining.inHours < 2
                ? Colors.red.shade700
                : Colors.orange.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: remaining.inHours < 2
                  ? Colors.red.shade700
                  : Colors.orange.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
