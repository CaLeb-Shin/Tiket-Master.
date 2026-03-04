import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:melon_core/melon_core.dart';

// =============================================================================
// 네이버 구매자용 모바일 티켓 페이지 (비로그인, 공개 URL)
// 디자인 v3: 포스터 전체 + QR 원형 오버랩 + 플립 전환 + 런타임/인터미션
// =============================================================================

const _ticketBaseUrl = 'https://melonticket-web-20260216.vercel.app/m/';

// ── 색상 ──
const _cream = Color(0xFFFAF8F5);
const _creamDark = Color(0xFFF0EDE8);
const _burgundy = Color(0xFF3B0D11);
const _burgundyDeep = Color(0xFF1A0508);
const _textDark = Color(0xFF1C1917);
const _textMid = Color(0xFF78716C);
const _textLight = Color(0xFFB8B2AA);
const _divider = Color(0xFFE7E0D8);
const _naverGreen = Color(0xFF03C75A);

class MobileTicketPage extends ConsumerStatefulWidget {
  final String accessToken;
  const MobileTicketPage({super.key, required this.accessToken});

  @override
  ConsumerState<MobileTicketPage> createState() => _MobileTicketPageState();
}

class _MobileTicketPageState extends ConsumerState<MobileTicketPage> {
  Map<String, dynamic>? _ticketData;
  bool _isLoading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadTicket();
  }

  Future<void> _loadTicket() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .getMobileTicketByToken(accessToken: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _ticketData = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = '티켓을 찾을 수 없습니다';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _burgundyDeep,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                  color: AppTheme.gold, strokeWidth: 2),
              const SizedBox(height: 16),
              Text('티켓 불러오는 중...',
                  style: AppTheme.nanum(fontSize: 13, color: _textLight)),
            ],
          ),
        ),
      );
    }

    if (_errorText != null || _ticketData == null) {
      return Scaffold(
        backgroundColor: _burgundyDeep,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _burgundy.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFFF6B6B), size: 36),
                ),
                const SizedBox(height: 18),
                Text(
                  _errorText ?? '오류가 발생했습니다',
                  style: AppTheme.nanum(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _cream),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('링크가 올바른지 확인해주세요',
                    style: AppTheme.nanum(fontSize: 13, color: _textLight)),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: _loadTicket,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('다시 시도'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.gold),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _burgundyDeep,
      body: SafeArea(
        child: _TicketView(
          data: _ticketData!,
          accessToken: widget.accessToken,
        ),
      ),
    );
  }
}

// ─── Main Ticket View (앞/뒤 플립) ───

class _TicketView extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  final String accessToken;

  const _TicketView({required this.data, required this.accessToken});

  @override
  ConsumerState<_TicketView> createState() => _TicketViewState();
}

class _TicketViewState extends ConsumerState<_TicketView>
    with SingleTickerProviderStateMixin {
  bool _showFront = true;
  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutCubic),
    );
    _flipCtrl.addListener(() {
      if (_flipCtrl.value >= 0.5 && _showFront) {
        setState(() => _showFront = false);
      } else if (_flipCtrl.value < 0.5 && !_showFront) {
        setState(() => _showFront = true);
      }
    });
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  void _flipToQr() {
    if (_flipCtrl.status == AnimationStatus.dismissed) {
      _flipCtrl.forward();
    }
  }

  void _flipToFront() {
    if (_flipCtrl.status == AnimationStatus.completed) {
      _flipCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final ticket = data['ticket'] as Map<String, dynamic>? ?? {};
    final event = data['event'] as Map<String, dynamic>? ?? {};

    final buyerName = ticket['buyerName'] as String? ?? '';
    final seatGrade = ticket['seatGrade'] as String? ?? '';
    final entryNumber = ticket['entryNumber'] as int? ?? 0;
    final status = ticket['status'] as String? ?? 'active';
    final seatInfo = ticket['seatInfo'] as String?;
    final ticketId = ticket['id'] as String? ?? '';
    final qrVersion = ticket['qrVersion'] as int? ?? 1;

    final eventTitle = event['title'] as String? ?? '공연';
    final imageUrl = event['imageUrl'] as String?;
    final naverProductUrl = event['naverProductUrl'] as String?;
    final venueName = event['venueName'] as String? ?? '';
    final venueAddress = event['venueAddress'] as String? ?? '';
    DateTime? startAt;
    final startAtRaw = event['startAt'];
    final startAtStr = startAtRaw is String ? startAtRaw : null;
    if (startAtStr != null) {
      startAt = DateTime.tryParse(startAtStr);
    }
    if (startAt == null && event['startAt'] is Map) {
      final ts = event['startAt'] as Map;
      final seconds = ts['_seconds'] as int?;
      if (seconds != null) {
        startAt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }

    final isCancelled = status == 'cancelled';
    final isUsed = status == 'used';
    final gradeCol = _gradeColor(seatGrade);
    final ticketUrl = '$_ticketBaseUrl${widget.accessToken}';

    final now = DateTime.now();
    final qrRevealed =
        startAt != null && now.isAfter(startAt.subtract(const Duration(hours: 2)));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_burgundy, _burgundyDeep, const Color(0xFF0A0305)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          children: [
            // ── LIVE 인디케이터 ──
            if (!isCancelled && !isUsed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _LiveBadge(startAt: startAt),
              ),

            // ══════════════════════════════════════════
            // ── 메인 카드 (플립 애니메이션) ──
            // ══════════════════════════════════════════
            AnimatedBuilder(
              animation: _flipAnim,
              builder: (context, _) {
                final angle = _flipAnim.value * math.pi;
                final isFront = _flipAnim.value < 0.5;

                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(angle),
                  child: isFront
                      ? _FrontCard(
                          eventTitle: eventTitle,
                          imageUrl: imageUrl,
                          naverProductUrl: naverProductUrl,
                          buyerName: buyerName,
                          seatGrade: seatGrade,
                          seatInfo: seatInfo,
                          entryNumber: entryNumber,
                          startAt: startAt,
                          venueName: venueName,
                          venueAddress: venueAddress,
                          gradeCol: gradeCol,
                          status: status,
                          isCancelled: isCancelled,
                          isUsed: isUsed,
                          qrRevealed: qrRevealed,
                          onQrTap: _flipToQr,
                        )
                      : Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(math.pi),
                          child: _BackCard(
                            eventTitle: eventTitle,
                            venueName: venueName,
                            buyerName: buyerName,
                            entryNumber: entryNumber,
                            startAt: startAt,
                            ticketId: ticketId,
                            accessToken: widget.accessToken,
                            qrVersion: qrVersion,
                            qrRevealed: qrRevealed,
                            isCancelled: isCancelled,
                            isUsed: isUsed,
                            onBack: _flipToFront,
                          ),
                        ),
                );
              },
            ),

            const SizedBox(height: 20),

            // ── 액션 버튼 (카드 밖) ──
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.link_rounded,
                      label: '링크 복사',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: ticketUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('링크가 복사되었습니다',
                                style: AppTheme.nanum(
                                    fontSize: 13, color: _cream)),
                            backgroundColor: _burgundy,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                      width: 1,
                      height: 36,
                      color: Colors.white.withValues(alpha: 0.08)),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.share_rounded,
                      label: '공유하기',
                      onTap: () => Share.share(
                        '$eventTitle\n$ticketUrl',
                        subject: eventTitle,
                      ),
                    ),
                  ),
                  Container(
                      width: 1,
                      height: 36,
                      color: Colors.white.withValues(alpha: 0.08)),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.group_add_rounded,
                      label: '친구 초대',
                      onTap: () {
                        final inviteText = '같이 가요! $eventTitle\n'
                            '${startAt != null ? DateFormat('M월 d일 (E) HH:mm', 'ko_KR').format(startAt!) : ''}'
                            '${venueName.isNotEmpty ? ' @ $venueName' : ''}\n'
                            '${naverProductUrl ?? ticketUrl}';
                        Share.share(inviteText, subject: '공연 초대');
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── 네이버 스토어 버튼 ──
            if (naverProductUrl != null && naverProductUrl.isNotEmpty)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(naverProductUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.storefront_rounded, size: 20),
                  label: Text(
                    '네이버 스토어에서 확인하기',
                    style: AppTheme.nanum(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _naverGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // ── 안내 텍스트 ──
            Text(
              '이 티켓은 공연 당일 입장 시 QR코드를 스캔하여 확인합니다.\n'
              'QR코드는 보안을 위해 2분마다 자동 갱신됩니다.',
              textAlign: TextAlign.center,
              style: AppTheme.nanum(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.3),
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ── 앞면 카드 (포스터 + 정보 + 작은 QR) ──
// ══════════════════════════════════════════════════════════

class _FrontCard extends StatelessWidget {
  final String eventTitle;
  final String? imageUrl;
  final String? naverProductUrl;
  final String buyerName;
  final String seatGrade;
  final String? seatInfo;
  final int entryNumber;
  final DateTime? startAt;
  final String venueName;
  final String venueAddress;
  final Color gradeCol;
  final String status;
  final bool isCancelled;
  final bool isUsed;
  final bool qrRevealed;
  final VoidCallback onQrTap;

  const _FrontCard({
    required this.eventTitle,
    this.imageUrl,
    this.naverProductUrl,
    required this.buyerName,
    required this.seatGrade,
    this.seatInfo,
    required this.entryNumber,
    this.startAt,
    required this.venueName,
    required this.venueAddress,
    required this.gradeCol,
    required this.status,
    required this.isCancelled,
    required this.isUsed,
    required this.qrRevealed,
    required this.onQrTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _BoardingPassClipper(notchRadius: 16, notchPosition: 0.55),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _cream,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── 헤더: SMART TICKET ──
            _SmartTicketHeader(status: status, gradeCol: gradeCol),

            // ── 포스터 + QR 오버랩 ──
            _PosterWithQr(
              imageUrl: imageUrl,
              naverProductUrl: naverProductUrl,
              qrRevealed: qrRevealed,
              isCancelled: isCancelled,
              isUsed: isUsed,
              onQrTap: onQrTap,
            ),

            // ── 공연 정보 섹션 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 공연명
                  Text(
                    eventTitle,
                    style: AppTheme.nanum(
                      color: _textDark,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      noShadow: true,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),

                  // 정보 그리드
                  Row(
                    children: [
                      Expanded(
                          child:
                              _InfoField(label: 'Passenger', value: buyerName)),
                      Expanded(
                        child: _InfoField(
                          label: 'Date',
                          value: startAt != null
                              ? DateFormat('yyyy.MM.dd (E)', 'ko_KR')
                                  .format(startAt!)
                              : '-',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoField(
                          label: 'Entry No.',
                          value: '#$entryNumber',
                          valueStyle: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: gradeCol,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _InfoField(
                          label: 'Grade',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: gradeCol.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: gradeCol.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '${seatGrade}석',
                              style: AppTheme.nanum(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: gradeCol,
                                noShadow: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoField(
                          label: 'Seat',
                          value: seatInfo ?? '공연당일 배정',
                        ),
                      ),
                      Expanded(
                        child: _InfoField(
                          label: 'Time',
                          value: startAt != null
                              ? DateFormat('HH:mm').format(startAt!)
                              : '-',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _InfoField(
                    label: 'Venue',
                    value: venueName,
                    onTap: venueName.isNotEmpty
                        ? () {
                            final query = venueAddress.isNotEmpty
                                ? venueAddress
                                : venueName;
                            launchUrl(
                              Uri.parse(
                                  'https://map.kakao.com/link/search/$query'),
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        : null,
                  ),
                  if (venueAddress.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        venueAddress,
                        style: AppTheme.nanum(
                            fontSize: 11,
                            color: _textLight,
                            noShadow: true),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 구분선 (골드 다이아몬드) ──
            _GoldDivider(),

            const SizedBox(height: 16),

            // ── 런타임 & 인터미션 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _InfoField(
                      label: 'Runtime',
                      value: '2시간 10분',
                      valueStyle: AppTheme.nanum(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                        noShadow: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _InfoField(
                      label: 'Intermission',
                      value: '15분',
                      valueStyle: AppTheme.nanum(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                        noShadow: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── QR 탭 안내 ──
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: GestureDetector(
                onTap: onQrTap,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app_rounded,
                        size: 14, color: _textLight),
                    const SizedBox(width: 4),
                    Text(
                      'QR코드를 탭하여 확인',
                      style: AppTheme.nanum(
                        fontSize: 11,
                        color: _textLight,
                        noShadow: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ── 뒷면 카드 (QR 전체화면) ──
// ══════════════════════════════════════════════════════════

class _BackCard extends StatefulWidget {
  final String eventTitle;
  final String venueName;
  final String buyerName;
  final int entryNumber;
  final DateTime? startAt;
  final String ticketId;
  final String accessToken;
  final int qrVersion;
  final bool qrRevealed;
  final bool isCancelled;
  final bool isUsed;
  final VoidCallback onBack;

  const _BackCard({
    required this.eventTitle,
    required this.venueName,
    required this.buyerName,
    required this.entryNumber,
    this.startAt,
    required this.ticketId,
    required this.accessToken,
    required this.qrVersion,
    required this.qrRevealed,
    required this.isCancelled,
    required this.isUsed,
    required this.onBack,
  });

  @override
  State<_BackCard> createState() => _BackCardState();
}

class _BackCardState extends State<_BackCard> {
  bool _localQrRevealed = false;

  @override
  void initState() {
    super.initState();
    _localQrRevealed = widget.qrRevealed;
  }

  void _handleRefresh() {
    // 새로고침 시 현재 시각으로 QR 공개 여부 재확인
    if (widget.startAt != null) {
      final now = DateTime.now();
      final revealed = now.isAfter(widget.startAt!.subtract(const Duration(hours: 2)));
      setState(() => _localQrRevealed = revealed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onBack,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _cream,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 32),

            // ── 아이콘 ──
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _burgundy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.confirmation_number_rounded,
                  size: 28, color: _burgundy),
            ),
            const SizedBox(height: 16),

            // ── 안내 텍스트 ──
            Text(
              '입장 시 QR 코드를 보여주세요',
              style: AppTheme.nanum(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textMid,
                noShadow: true,
              ),
            ),
            const SizedBox(height: 24),

            // ── QR 코드 영역 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: _localQrRevealed && !widget.isCancelled && !widget.isUsed
                  ? _QrSection(
                      ticketId: widget.ticketId,
                      accessToken: widget.accessToken,
                      qrVersion: widget.qrVersion,
                    )
                  : _QrPlaceholderBack(
                      startAt: widget.startAt,
                      isCancelled: widget.isCancelled,
                      isUsed: widget.isUsed,
                      onRefresh: _handleRefresh,
                    ),
            ),

            const SizedBox(height: 24),

            // ── 구분선 ──
            _GoldDivider(),

            const SizedBox(height: 20),

            // ── 하단 정보 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    widget.eventTitle,
                    style: AppTheme.nanum(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _textDark,
                      noShadow: true,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.venueName,
                    style: AppTheme.nanum(
                        fontSize: 13, color: _textMid, noShadow: true),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _InfoField(
                          label: 'Passenger',
                          value: widget.buyerName,
                        ),
                      ),
                      Expanded(
                        child: _InfoField(
                          label: 'ETKT',
                          value: '#${widget.entryNumber}',
                          valueStyle: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 안내 사항 ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _creamDark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _NoteRow(
                    icon: Icons.schedule_rounded,
                    text: '공연 2시간 전에 QR 코드가 공개됩니다',
                  ),
                  const SizedBox(height: 6),
                  _NoteRow(
                    icon: Icons.refresh_rounded,
                    text: 'QR 코드는 2분마다 자동 갱신됩니다',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 돌아가기 안내 ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app_rounded, size: 14, color: _textLight),
                const SizedBox(width: 4),
                Text(
                  '탭하여 티켓으로 돌아가기',
                  style: AppTheme.nanum(
                    fontSize: 11,
                    color: _textLight,
                    noShadow: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ── 위젯 조각들 ──
// ══════════════════════════════════════════════════════════

// ── SMART TICKET 헤더 ──
class _SmartTicketHeader extends StatelessWidget {
  final String status;
  final Color gradeCol;

  const _SmartTicketHeader({required this.status, required this.gradeCol});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _burgundy,
            _burgundy.withValues(alpha: 0.9),
            gradeCol.withValues(alpha: 0.7),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.confirmation_number_rounded,
              size: 16, color: _cream),
          const SizedBox(width: 8),
          Text(
            'SMART TICKET',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _cream,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          _StatusBadge(status: status),
        ],
      ),
    );
  }
}

// ── 포스터 + QR 원형 오버랩 ──
class _PosterWithQr extends StatelessWidget {
  final String? imageUrl;
  final String? naverProductUrl;
  final bool qrRevealed;
  final bool isCancelled;
  final bool isUsed;
  final VoidCallback onQrTap;

  const _PosterWithQr({
    this.imageUrl,
    this.naverProductUrl,
    required this.qrRevealed,
    required this.isCancelled,
    required this.isUsed,
    required this.onQrTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // 포스터 이미지 (전체 비율 유지)
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 200),
          color: _creamDark,
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => SizedBox(
                    height: 200,
                    child: Center(
                      child: Icon(Icons.music_note_rounded,
                          color: _textLight, size: 40),
                    ),
                  ),
                )
              : SizedBox(
                  height: 200,
                  child: Center(
                    child: Icon(Icons.music_note_rounded,
                        color: _textLight, size: 40),
                  ),
                ),
        ),

        // QR 원형 오버랩 (포스터 하단에 걸침) — 미니 QR 패턴 + 잠금 오버레이
        Positioned(
          bottom: -30,
          child: GestureDetector(
            onTap: onQrTap,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: _cream, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 미니 QR 패턴 (배경)
                    if (!isCancelled && !isUsed)
                      Opacity(
                        opacity: qrRevealed ? 1.0 : 0.3,
                        child: QrImageView(
                          data: 'MELON-TICKET',
                          version: QrVersions.auto,
                          size: 40,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: _textDark,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: _textDark,
                          ),
                          gapless: true,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    // 잠금 오버레이 (공개 전)
                    if (!qrRevealed && !isCancelled && !isUsed)
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.lock_rounded,
                            size: 14, color: _textMid),
                      ),
                    if (isCancelled)
                      Icon(Icons.cancel_rounded,
                          size: 28, color: const Color(0xFFFF5A5F)),
                    if (isUsed)
                      Icon(Icons.check_circle_rounded,
                          size: 28, color: const Color(0xFF22C55E)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── LIVE 배지 (실시간 카운트다운) ──
class _LiveBadge extends StatefulWidget {
  final DateTime? startAt;
  const _LiveBadge({this.startAt});

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  Timer? _tickTimer;
  Duration _remaining = Duration.zero;
  _LiveStatus _status = _LiveStatus.upcoming;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _updateCountdown();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateCountdown();
    });
  }

  void _updateCountdown() {
    if (widget.startAt == null) return;
    final now = DateTime.now();
    // 런타임 2시간 10분 기준 공연 종료
    final endAt = widget.startAt!.add(const Duration(hours: 2, minutes: 10));

    if (now.isBefore(widget.startAt!)) {
      // 공연 전
      setState(() {
        _remaining = widget.startAt!.difference(now);
        _status = _LiveStatus.upcoming;
      });
    } else if (now.isBefore(endAt)) {
      // 공연 중
      setState(() {
        _remaining = endAt.difference(now);
        _status = _LiveStatus.playing;
      });
    } else {
      // 공연 종료
      setState(() {
        _remaining = Duration.zero;
        _status = _LiveStatus.ended;
      });
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _tickTimer?.cancel();
    super.dispose();
  }

  String _formatCountdown(Duration d) {
    if (d.inDays > 0) {
      final h = d.inHours % 24;
      final m = d.inMinutes % 60;
      final s = d.inSeconds % 60;
      return 'D-${d.inDays}  ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isToday = widget.startAt != null &&
        widget.startAt!.difference(DateTime.now()).inDays == 0 &&
        _status == _LiveStatus.upcoming;

    final Color dotColor;
    final String labelText;
    final String? countdownText;

    switch (_status) {
      case _LiveStatus.upcoming:
        dotColor = const Color(0xFF22C55E);
        labelText = isToday ? 'TODAY' : 'LIVE';
        countdownText = widget.startAt != null
            ? (isToday
                ? _formatCountdown(_remaining)
                : 'D-${_remaining.inDays}  ${(_remaining.inHours % 24).toString().padLeft(2, '0')}:${(_remaining.inMinutes % 60).toString().padLeft(2, '0')}:${(_remaining.inSeconds % 60).toString().padLeft(2, '0')}')
            : null;
      case _LiveStatus.playing:
        dotColor = const Color(0xFFFF4444);
        labelText = 'NOW PLAYING';
        countdownText = null;
      case _LiveStatus.ended:
        dotColor = _textLight;
        labelText = 'ENDED';
        countdownText = null;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _status == _LiveStatus.ended
                  ? dotColor
                  : Color.lerp(
                      dotColor,
                      dotColor.withValues(alpha: 0.3),
                      _pulseCtrl.value,
                    ),
              boxShadow: _status != _LiveStatus.ended
                  ? [
                      BoxShadow(
                        color: dotColor
                            .withValues(alpha: 0.4 * (1 - _pulseCtrl.value)),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          labelText,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: dotColor,
            letterSpacing: 2,
          ),
        ),
        if (countdownText != null) ...[
          const SizedBox(width: 8),
          Text(
            countdownText,
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}

enum _LiveStatus { upcoming, playing, ended }

// ── 상태 배지 ──
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bgColor, fgColor) = switch (status) {
      'active' => ('스마트티켓', const Color(0x33FFFFFF), _cream),
      'used' => ('이용완료', const Color(0x3322C55E), const Color(0xFF22C55E)),
      'cancelled' =>
        ('취소됨', const Color(0x33FF5A5F), const Color(0xFFFF5A5F)),
      _ => ('스마트티켓', const Color(0x33FFFFFF), _cream),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.nanum(
            color: fgColor,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            noShadow: true),
      ),
    );
  }
}

// ── 정보 필드 ──
class _InfoField extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  final TextStyle? valueStyle;
  final VoidCallback? onTap;

  const _InfoField({
    required this.label,
    this.value,
    this.child,
    this.valueStyle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _textLight,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          if (child != null)
            child!
          else
            Text(
              value ?? '-',
              style: valueStyle ??
                  AppTheme.nanum(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _textDark,
                    noShadow: true,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

// ── 골드 구분선 ──
class _GoldDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: _divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '✦',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.gold.withValues(alpha: 0.6)),
            ),
          ),
          Expanded(child: Container(height: 1, color: _divider)),
        ],
      ),
    );
  }
}

// ── 노트 행 (뒷면 안내사항) ──
class _NoteRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _NoteRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _textMid),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTheme.nanum(
                fontSize: 12, color: _textMid, noShadow: true),
          ),
        ),
      ],
    );
  }
}

// ── QR 플레이스홀더 (뒷면 - 공개 전) ──
class _QrPlaceholderBack extends StatelessWidget {
  final DateTime? startAt;
  final bool isCancelled;
  final bool isUsed;
  final VoidCallback? onRefresh;

  const _QrPlaceholderBack({
    this.startAt,
    required this.isCancelled,
    required this.isUsed,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final message = isCancelled
        ? '취소된 티켓입니다'
        : isUsed
            ? '이미 사용된 티켓입니다'
            : '공연시작 2시간 전에\n입장 QR과 좌석이 공개됩니다';
    final icon = isCancelled
        ? Icons.cancel_rounded
        : isUsed
            ? Icons.check_circle_rounded
            : Icons.lock_clock_rounded;
    final iconColor = isCancelled
        ? const Color(0xFFFF5A5F)
        : isUsed
            ? const Color(0xFF22C55E)
            : AppTheme.gold;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: _creamDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: iconColor),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.nanum(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _textMid,
              height: 1.5,
              noShadow: true,
            ),
          ),
          if (!isCancelled && !isUsed && startAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '${DateFormat('M월 d일 HH:mm', 'ko_KR').format(startAt!.subtract(const Duration(hours: 2)))} 공개',
              style:
                  AppTheme.nanum(fontSize: 12, color: _textLight, noShadow: true),
            ),
            const SizedBox(height: 16),
            // 새로고침 버튼
            GestureDetector(
              onTap: onRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 16, color: _textMid),
                    const SizedBox(width: 6),
                    Text(
                      '새로고침',
                      style: AppTheme.nanum(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _textMid,
                          noShadow: true),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── QR 코드 섹션 (공개 후) ──
class _QrSection extends ConsumerStatefulWidget {
  final String ticketId;
  final String accessToken;
  final int qrVersion;

  const _QrSection({
    required this.ticketId,
    required this.accessToken,
    required this.qrVersion,
  });

  @override
  ConsumerState<_QrSection> createState() => _QrSectionState();
}

class _QrSectionState extends ConsumerState<_QrSection> {
  static const _refreshIntervalSeconds = 120;

  Timer? _countdownTimer;
  String? _qrData;
  int _remainingSeconds = _refreshIntervalSeconds;
  bool _isLoading = true;
  bool _isRefreshingToken = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _refreshQrToken();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _refreshQrToken();
        }
      });
    });
  }

  Future<void> _refreshQrToken() async {
    if (_isRefreshingToken) return;
    _isRefreshingToken = true;

    _countdownTimer?.cancel();
    setState(() {
      _isLoading = _qrData == null;
      _errorText = null;
    });

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .issueMobileQrToken(
            ticketId: widget.ticketId,
            accessToken: widget.accessToken,
          );
      final token = result['token'] as String?;
      final exp = result['exp'] as int?;

      if (token == null || token.isEmpty || exp == null) {
        throw Exception('QR 토큰 응답이 올바르지 않습니다');
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final secondsLeft =
          (exp - now).clamp(1, _refreshIntervalSeconds).toInt();

      if (!mounted) return;
      setState(() {
        _qrData = token;
        _remainingSeconds = secondsLeft;
        _isLoading = false;
      });
      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = 'QR 발급 실패';
      });
    } finally {
      _isRefreshingToken = false;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _divider),
          ),
          child: _buildQrContent(),
        ),
        const SizedBox(height: 8),
        _buildTimerBadge(),
      ],
    );
  }

  Widget _buildQrContent() {
    if (_isLoading) {
      return const SizedBox(
        width: 200,
        height: 200,
        child: Center(
          child:
              CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2),
        ),
      );
    }

    if (_qrData == null) {
      return GestureDetector(
        onTap: _refreshQrToken,
        child: SizedBox(
          width: 200,
          height: 200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.refresh_rounded, size: 28, color: _textLight),
              const SizedBox(height: 8),
              Text(
                _errorText ?? 'QR 생성 실패',
                style: AppTheme.nanum(
                    fontSize: 12, color: _textMid, noShadow: true),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _refreshQrToken,
      child: QrImageView(
        data: _qrData!,
        version: QrVersions.auto,
        size: 200,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: _textDark,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: _textDark,
        ),
        gapless: true,
      ),
    );
  }

  Widget _buildTimerBadge() {
    final isLow = _remainingSeconds <= 30;
    final min = _remainingSeconds ~/ 60;
    final sec = _remainingSeconds % 60;
    final timeStr =
        '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isLow ? const Color(0x1AFF9500) : _creamDark,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLow ? const Color(0x4DFF9500) : _divider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined,
              size: 12,
              color: isLow ? const Color(0xFFFF9500) : _textMid),
          const SizedBox(width: 4),
          Text(
            timeStr,
            style: GoogleFonts.robotoMono(
              fontSize: 12,
              color: isLow ? const Color(0xFFFF9500) : _textMid,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 액션 버튼 ──
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.nanum(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Grade color helper ──
Color _gradeColor(String grade) {
  switch (grade) {
    case 'VIP':
      return const Color(0xFFC9A84C);
    case 'R':
      return const Color(0xFF6B4FA0);
    case 'S':
      return const Color(0xFF2D6A4F);
    case 'A':
      return const Color(0xFF3B7DD8);
    default:
      return _textMid;
  }
}

// ── Boarding Pass Clipper ──
class _BoardingPassClipper extends CustomClipper<Path> {
  final double notchRadius;
  final double notchPosition;

  const _BoardingPassClipper({
    this.notchRadius = 16,
    this.notchPosition = 0.55,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    const r = 20.0;
    final notchY = size.height * notchPosition;

    path.moveTo(r, 0);
    path.lineTo(size.width - r, 0);
    path.arcToPoint(Offset(size.width, r),
        radius: const Radius.circular(r));

    path.lineTo(size.width, notchY - notchRadius);
    path.arcToPoint(Offset(size.width, notchY + notchRadius),
        radius: Radius.circular(notchRadius), clockwise: false);

    path.lineTo(size.width, size.height - r);
    path.arcToPoint(Offset(size.width - r, size.height),
        radius: const Radius.circular(r));

    path.lineTo(r, size.height);
    path.arcToPoint(Offset(0, size.height - r),
        radius: const Radius.circular(r));

    path.lineTo(0, notchY + notchRadius);
    path.arcToPoint(Offset(0, notchY - notchRadius),
        radius: Radius.circular(notchRadius), clockwise: false);

    path.lineTo(0, r);
    path.arcToPoint(Offset(r, 0), radius: const Radius.circular(r));

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _BoardingPassClipper oldClipper) =>
      notchRadius != oldClipper.notchRadius ||
      notchPosition != oldClipper.notchPosition;
}
