import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/event.dart';

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
      // 좌석 수 확인
      final seatSnap = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .collection('seats')
          .get();
      _seatCount = seatSnap.docs.length;
      _hasSeats = _seatCount > 0;

      if (_hasSeats) {
        _addLog('✓ 좌석 ${_seatCount}석 등록됨');
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

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!_isProcessing && _currentStep != _Step.done)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('취소',
                  style: AdminTheme.sans(
                      fontSize: 13, color: AdminTheme.textTertiary)),
            ),
          const SizedBox(width: 8),
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
              onPressed: _goToSeatManager,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('좌석 관리로 이동'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.warning,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ];
        }
        return [
          ElevatedButton.icon(
            onPressed: _runAll,
            icon: const Icon(Icons.rocket_launch_rounded, size: 18),
            label: const Text('배정 + QR 공개'),
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
