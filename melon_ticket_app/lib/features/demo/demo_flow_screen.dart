import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';

class DemoFlowScreen extends StatefulWidget {
  const DemoFlowScreen({super.key});

  @override
  State<DemoFlowScreen> createState() => _DemoFlowScreenState();
}

class _DemoFlowScreenState extends State<DemoFlowScreen> {
  final _titleController = TextEditingController(text: '2026 멜론 라이브 쇼케이스');
  final _venueController = TextEditingController(text: '부산시민회관 대극장');
  final _priceController = TextEditingController(text: '99000');
  final _seatCountController = TextEditingController(text: '600');
  final _buyerController = TextEditingController(text: '데모관객');
  final _scanController = TextEditingController();

  DateTime _eventAt = DateTime.now().add(const Duration(days: 7, hours: 2));
  _DemoEvent? _event;
  _DemoTicket? _ticket;
  String? _shareUrl;
  String? _scanMessage;
  bool _scanSuccess = false;
  int _quantity = 2;
  final Set<int> _soldSeatNumbers = <int>{};

  @override
  void dispose() {
    _titleController.dispose();
    _venueController.dispose();
    _priceController.dispose();
    _seatCountController.dispose();
    _buyerController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateText =
        DateFormat('yyyy년 M월 d일 (E) HH:mm', 'ko_KR').format(_eventAt);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          '데모 플로우',
          style: GoogleFonts.notoSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _resetAll,
            child: Text(
              '초기화',
              style: GoogleFonts.notoSans(
                color: AppTheme.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.goldSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.gold.withOpacity(0.4)),
            ),
            child: Text(
              '실서비스 연동 없이, 공연등록 → 공유 → 구매(가상결제) → QR스캔 → 입장확인까지 혼자 테스트하는 모드입니다.',
              style: GoogleFonts.notoSans(
                color: AppTheme.textPrimary,
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _runQuickRehearsal,
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                  label: const Text('원클릭 리허설'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/admin/venues'),
                  icon: const Icon(Icons.location_city_rounded, size: 18),
                  label: const Text('공연장 관리 이동'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            step: '1',
            title: '공연 등록 (관리자 시뮬레이션)',
            child: Column(
              children: [
                _LabeledField(
                    label: '공연명',
                    child: TextField(controller: _titleController)),
                const SizedBox(height: 10),
                _LabeledField(
                    label: '공연장',
                    child: TextField(controller: _venueController)),
                const SizedBox(height: 10),
                _LabeledField(
                  label: '공연 일시',
                  child: InkWell(
                    onTap: _pickDateTime,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 15),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        dateText,
                        style: GoogleFonts.notoSans(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: '가격(원)',
                        child: TextField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _LabeledField(
                        label: '총 좌석',
                        child: TextField(
                          controller: _seatCountController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _registerEvent,
                    child: const Text('공연 등록하기'),
                  ),
                ),
                if (_event != null) ...[
                  const SizedBox(height: 10),
                  _InfoBox(
                    lines: [
                      '공연ID: ${_event!.id}',
                      '좌석: ${_event!.availableSeats}/${_event!.totalSeats}',
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            step: '2',
            title: '공유 (관객 유입 시뮬레이션)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_event == null)
                  _DisabledHint(text: '먼저 공연을 등록하면 공유 링크가 생성됩니다.')
                else ...[
                  _InfoBox(
                    lines: [
                      '공유 URL: $_shareUrl',
                      '공유 문구: ${_event!.title} 예매 오픈! 지금 좌석 확인하세요.',
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: _shareUrl ?? ''));
                            _snack('공유 링크를 복사했습니다.');
                          },
                          child: const Text('링크 복사'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.go('/'),
                          child: const Text('관객 홈으로'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            step: '3',
            title: '구매 (결제/로그인 생략 발권)',
            child: Column(
              children: [
                _LabeledField(
                  label: '구매자 이름',
                  child: TextField(controller: _buyerController),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '수량',
                      style: GoogleFonts.notoSans(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _QtyButton(
                      label: '-',
                      onTap: _quantity > 1
                          ? () => setState(() => _quantity--)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 42,
                      alignment: Alignment.center,
                      child: Text(
                        '$_quantity',
                        style: GoogleFonts.notoSans(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _QtyButton(
                      label: '+',
                      onTap: () =>
                          setState(() => _quantity = min(8, _quantity + 1)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _simulatePurchase,
                    child: const Text('가상 결제 후 티켓 발권'),
                  ),
                ),
                if (_ticket != null) ...[
                  const SizedBox(height: 10),
                  _InfoBox(
                    lines: [
                      '티켓 상태: ${_ticketStatusLabel(_ticket!)}',
                      if (_ticket!.checkedInAt != null)
                        '입장시각: ${DateFormat('HH:mm:ss').format(_ticket!.checkedInAt!)}',
                      if (_ticket!.refundedAt != null)
                        '환불시각: ${DateFormat('HH:mm:ss').format(_ticket!.refundedAt!)}',
                    ],
                  ),
                  const SizedBox(height: 8),
                  _InfoBox(
                    lines: [
                      '티켓번호: ${_ticket!.ticketId}',
                      '좌석: ${_ticket!.seatLabels.join(', ')}',
                      '결제금액: ${NumberFormat('#,###').format(_ticket!.totalPrice)}원',
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            step: '4',
            title: '티켓 확인 (QR)',
            child: _ticket == null
                ? _DisabledHint(text: '구매를 완료하면 QR 티켓이 표시됩니다.')
                : Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDDE3EA)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _event?.title ?? '',
                              style: GoogleFonts.notoSans(
                                color: const Color(0xFF111827),
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            QrImageView(
                              data: _ticket!.qrPayload,
                              version: QrVersions.auto,
                              size: 180,
                              backgroundColor: Colors.white,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _ticket!.ticketId,
                              style: GoogleFonts.robotoMono(
                                color: const Color(0xFF334155),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            step: '5',
            title: '입장 스캔 (스태프 시뮬레이션)',
            child: Column(
              children: [
                if (_ticket != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _ticketStatusColor(_ticket!).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _ticketStatusColor(_ticket!)),
                    ),
                    child: Text(
                      '현재 티켓 상태: ${_ticketStatusLabel(_ticket!)}',
                      style: GoogleFonts.notoSans(
                        fontWeight: FontWeight.w700,
                        color: _ticketStatusColor(_ticket!),
                        fontSize: 13,
                      ),
                    ),
                  ),
                TextField(
                  controller: _scanController,
                  maxLines: 2,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: 'QR 스캔값을 입력하거나 자동입력 버튼을 누르세요',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _ticket == null
                            ? null
                            : () => setState(() =>
                                _scanController.text = _ticket!.qrPayload),
                        child: const Text('QR 자동입력'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _runScanCheck,
                        child: const Text('입장 처리'),
                      ),
                    ),
                  ],
                ),
                if (_scanMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _scanSuccess
                          ? AppTheme.success.withOpacity(0.18)
                          : AppTheme.error.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _scanSuccess ? AppTheme.success : AppTheme.error,
                      ),
                    ),
                    child: Text(
                      _scanMessage!,
                      style: GoogleFonts.notoSans(
                        color: _scanSuccess ? AppTheme.success : AppTheme.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            step: '6',
            title: '취소/환불 시뮬레이션',
            child: _ticket == null
                ? _DisabledHint(text: '티켓 발권 후 취소/환불 시나리오를 실행할 수 있습니다.')
                : Column(
                    children: [
                      _InfoBox(
                        lines: [
                          '정책: 입장 전에는 전액 환불, 입장 후에는 환불 불가',
                          '환불 시 좌석은 즉시 재판매 가능 상태로 복원',
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _ticket!.isRefunded ? null : _refundTicket,
                          icon: const Icon(Icons.undo_rounded, size: 18),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.error.withOpacity(0.16),
                            foregroundColor: AppTheme.error,
                          ),
                          label: Text(
                            _ticket!.isRefunded ? '이미 환불된 티켓' : '티켓 환불 처리',
                            style: GoogleFonts.notoSans(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _eventAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eventAt),
    );
    if (time == null || !mounted) return;

    setState(() {
      _eventAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _runQuickRehearsal() {
    _registerEvent();
    if (_event == null) return;
    _simulatePurchase();
    if (_ticket != null) {
      setState(() {
        _scanController.text = _ticket!.qrPayload;
      });
    }
    _snack('원클릭 리허설 준비 완료: 이제 입장 처리 또는 환불을 테스트하세요.');
  }

  void _registerEvent() {
    final title = _titleController.text.trim();
    final venue = _venueController.text.trim();
    final price = int.tryParse(_priceController.text.trim());
    final totalSeats = int.tryParse(_seatCountController.text.trim());

    if (title.isEmpty || venue.isEmpty || price == null || totalSeats == null) {
      _snack('공연 정보 입력값을 확인해주세요.');
      return;
    }
    if (price <= 0 || totalSeats <= 0) {
      _snack('가격과 좌석 수는 1 이상이어야 합니다.');
      return;
    }

    final id =
        'EV-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

    setState(() {
      _event = _DemoEvent(
        id: id,
        title: title,
        venue: venue,
        startsAt: _eventAt,
        price: price,
        totalSeats: totalSeats,
        soldSeats: 0,
      );
      _shareUrl = 'https://melon-ticket.app/event/$id';
      _ticket = null;
      _scanController.clear();
      _scanMessage = null;
      _soldSeatNumbers.clear();
    });

    _snack('공연이 데모로 등록되었습니다.');
  }

  void _simulatePurchase() {
    final event = _event;
    if (event == null) {
      _snack('먼저 공연을 등록해주세요.');
      return;
    }
    final buyer = _buyerController.text.trim().isEmpty
        ? '데모관객'
        : _buyerController.text.trim();
    final qty = _quantity.clamp(1, 8);
    if (event.availableSeats < qty) {
      _snack('남은 좌석이 부족합니다.');
      return;
    }

    final seatNumbers = <int>[];
    var candidate = 1;
    while (seatNumbers.length < qty && candidate <= event.totalSeats) {
      if (!_soldSeatNumbers.contains(candidate)) {
        seatNumbers.add(candidate);
      }
      candidate++;
    }

    if (seatNumbers.length < qty) {
      _snack('좌석 배정에 실패했습니다.');
      return;
    }

    final seatLabels = seatNumbers.map(_seatLabelFromNumber).toList();
    final issuedAt = DateTime.now();
    final ticketId =
        'TK-${issuedAt.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    final qrToken = _randomToken(24);

    setState(() {
      _soldSeatNumbers.addAll(seatNumbers);
      _event = event.copyWith(soldSeats: event.soldSeats + qty);
      _ticket = _DemoTicket(
        ticketId: ticketId,
        eventId: event.id,
        eventTitle: event.title,
        buyerName: buyer,
        quantity: qty,
        seatNumbers: seatNumbers,
        seatLabels: seatLabels,
        totalPrice: event.price * qty,
        issuedAt: issuedAt,
        qrPayload: '$ticketId::$qrToken',
        checkedIn: false,
        checkedInAt: null,
        isRefunded: false,
        refundedAt: null,
      );
      _scanController.clear();
      _scanMessage = null;
    });

    _snack('가상 결제가 완료되고 티켓이 발권되었습니다.');
  }

  void _runScanCheck() {
    final ticket = _ticket;
    final input = _scanController.text.trim();
    if (ticket == null) {
      setState(() {
        _scanSuccess = false;
        _scanMessage = '발권된 티켓이 없습니다.';
      });
      return;
    }
    if (input.isEmpty) {
      setState(() {
        _scanSuccess = false;
        _scanMessage = '스캔값을 입력해주세요.';
      });
      return;
    }
    if (input != ticket.qrPayload) {
      setState(() {
        _scanSuccess = false;
        _scanMessage = '유효하지 않은 QR입니다.';
      });
      return;
    }
    if (ticket.isRefunded) {
      setState(() {
        _scanSuccess = false;
        _scanMessage = '환불된 티켓은 입장 처리할 수 없습니다.';
      });
      return;
    }
    if (ticket.checkedIn) {
      setState(() {
        _scanSuccess = false;
        _scanMessage =
            '이미 입장 처리된 티켓입니다. (${DateFormat('HH:mm:ss').format(ticket.checkedInAt!)})';
      });
      return;
    }

    final now = DateTime.now();
    setState(() {
      _ticket = ticket.copyWith(checkedIn: true, checkedInAt: now);
      _scanSuccess = true;
      _scanMessage = '입장 확인 완료: ${DateFormat('HH:mm:ss').format(now)}';
    });
  }

  void _refundTicket() {
    final ticket = _ticket;
    final event = _event;
    if (ticket == null || event == null) return;
    if (ticket.isRefunded) {
      _snack('이미 환불 처리된 티켓입니다.');
      return;
    }
    if (ticket.checkedIn) {
      _snack('입장 완료된 티켓은 환불할 수 없습니다.');
      return;
    }

    final refundedAt = DateTime.now();
    setState(() {
      for (final seatNo in ticket.seatNumbers) {
        _soldSeatNumbers.remove(seatNo);
      }
      _event =
          event.copyWith(soldSeats: max(0, event.soldSeats - ticket.quantity));
      _ticket = ticket.copyWith(isRefunded: true, refundedAt: refundedAt);
      _scanSuccess = false;
      _scanMessage = '환불 완료: ${DateFormat('HH:mm:ss').format(refundedAt)}';
    });
    _snack('티켓 환불 처리 완료. 좌석이 다시 판매 가능 상태가 되었습니다.');
  }

  void _resetAll() {
    setState(() {
      _event = null;
      _ticket = null;
      _shareUrl = null;
      _scanController.clear();
      _scanMessage = null;
      _scanSuccess = false;
      _soldSeatNumbers.clear();
      _quantity = 2;
    });
    _snack('데모 상태를 초기화했습니다.');
  }

  String _seatLabelFromNumber(int number) {
    final zeroBased = number - 1;
    final rowIndex = zeroBased ~/ 20;
    final seatNo = (zeroBased % 20) + 1;
    final row =
        rowIndex < 26 ? String.fromCharCode(65 + rowIndex) : 'R${rowIndex + 1}';
    return '$row$seatNo';
  }

  String _randomToken(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _ticketStatusLabel(_DemoTicket ticket) {
    if (ticket.isRefunded) return '환불 완료';
    if (ticket.checkedIn) return '입장 완료';
    return '발권 완료';
  }

  Color _ticketStatusColor(_DemoTicket ticket) {
    if (ticket.isRefunded) return AppTheme.error;
    if (ticket.checkedIn) return AppTheme.success;
    return AppTheme.gold;
  }
}

class _SectionCard extends StatelessWidget {
  final String step;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.step,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.goldSubtle,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  step,
                  style: GoogleFonts.robotoMono(
                    color: AppTheme.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.notoSans(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.notoSans(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  final List<String> lines;

  const _InfoBox({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.cardElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                line,
                style: GoogleFonts.notoSans(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DisabledHint extends StatelessWidget {
  final String text;
  const _DisabledHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.cardElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        style: GoogleFonts.notoSans(
          color: AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _QtyButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: onTap == null ? AppTheme.cardElevated : AppTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.notoSans(
              color:
                  onTap == null ? AppTheme.textTertiary : AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoEvent {
  final String id;
  final String title;
  final String venue;
  final DateTime startsAt;
  final int price;
  final int totalSeats;
  final int soldSeats;

  const _DemoEvent({
    required this.id,
    required this.title,
    required this.venue,
    required this.startsAt,
    required this.price,
    required this.totalSeats,
    required this.soldSeats,
  });

  int get availableSeats => totalSeats - soldSeats;

  _DemoEvent copyWith({
    String? id,
    String? title,
    String? venue,
    DateTime? startsAt,
    int? price,
    int? totalSeats,
    int? soldSeats,
  }) {
    return _DemoEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      venue: venue ?? this.venue,
      startsAt: startsAt ?? this.startsAt,
      price: price ?? this.price,
      totalSeats: totalSeats ?? this.totalSeats,
      soldSeats: soldSeats ?? this.soldSeats,
    );
  }
}

class _DemoTicket {
  final String ticketId;
  final String eventId;
  final String eventTitle;
  final String buyerName;
  final int quantity;
  final List<int> seatNumbers;
  final List<String> seatLabels;
  final int totalPrice;
  final DateTime issuedAt;
  final String qrPayload;
  final bool checkedIn;
  final DateTime? checkedInAt;
  final bool isRefunded;
  final DateTime? refundedAt;

  const _DemoTicket({
    required this.ticketId,
    required this.eventId,
    required this.eventTitle,
    required this.buyerName,
    required this.quantity,
    required this.seatNumbers,
    required this.seatLabels,
    required this.totalPrice,
    required this.issuedAt,
    required this.qrPayload,
    required this.checkedIn,
    required this.checkedInAt,
    required this.isRefunded,
    required this.refundedAt,
  });

  _DemoTicket copyWith({
    String? ticketId,
    String? eventId,
    String? eventTitle,
    String? buyerName,
    int? quantity,
    List<int>? seatNumbers,
    List<String>? seatLabels,
    int? totalPrice,
    DateTime? issuedAt,
    String? qrPayload,
    bool? checkedIn,
    DateTime? checkedInAt,
    bool? isRefunded,
    DateTime? refundedAt,
  }) {
    return _DemoTicket(
      ticketId: ticketId ?? this.ticketId,
      eventId: eventId ?? this.eventId,
      eventTitle: eventTitle ?? this.eventTitle,
      buyerName: buyerName ?? this.buyerName,
      quantity: quantity ?? this.quantity,
      seatNumbers: seatNumbers ?? this.seatNumbers,
      seatLabels: seatLabels ?? this.seatLabels,
      totalPrice: totalPrice ?? this.totalPrice,
      issuedAt: issuedAt ?? this.issuedAt,
      qrPayload: qrPayload ?? this.qrPayload,
      checkedIn: checkedIn ?? this.checkedIn,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      isRefunded: isRefunded ?? this.isRefunded,
      refundedAt: refundedAt ?? this.refundedAt,
    );
  }
}
