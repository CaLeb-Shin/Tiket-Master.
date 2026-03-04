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
  PageController? _pageController;
  int _currentPage = 0;

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

      // 그룹 티켓: 현재 티켓 위치 찾기
      final siblings = (result['siblings'] as List?)
          ?.cast<Map<String, dynamic>>() ?? [];
      int initialPage = 0;
      if (siblings.length > 1) {
        initialPage = siblings.indexWhere(
          (s) => s['accessToken'] == widget.accessToken,
        );
        if (initialPage < 0) initialPage = 0;
      }

      _pageController?.dispose();
      setState(() {
        _ticketData = result;
        _isLoading = false;
        _currentPage = initialPage;
        _pageController = PageController(initialPage: initialPage);
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
  void dispose() {
    _pageController?.dispose();
    super.dispose();
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

    final siblings = (_ticketData!['siblings'] as List?)
        ?.cast<Map<String, dynamic>>() ?? [];

    // 그룹 티켓 (2장 이상) → PageView 스와이프
    if (siblings.length > 1 && _pageController != null) {
      return Scaffold(
        backgroundColor: _burgundyDeep,
        body: SafeArea(
          child: Column(
            children: [
              _GroupTicketHeader(
                current: _currentPage,
                total: siblings.length,
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController!,
                  itemCount: siblings.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, index) {
                    final sibling = Map<String, dynamic>.from(siblings[index]);
                    final mainTicket =
                        _ticketData!['ticket'] as Map<String, dynamic>? ?? {};
                    final data = <String, dynamic>{
                      'ticket': <String, dynamic>{
                        ...sibling,
                        'eventId': mainTicket['eventId'],
                        'orderIndex': index + 1,
                        'totalInOrder': siblings.length,
                      },
                      'event': _ticketData!['event'],
                      'isRevealed': _ticketData!['isRevealed'],
                    };
                    return _TicketView(
                      data: data,
                      accessToken: sibling['accessToken'] as String,
                      isGroupTicket: true,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 단일 티켓
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
  final bool isGroupTicket;

  const _TicketView({
    required this.data,
    required this.accessToken,
    this.isGroupTicket = false,
  });

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
    final orderIndex = ticket['orderIndex'] as int? ?? 1;
    final totalInOrder = ticket['totalInOrder'] as int? ?? 1;

    final eventTitle = event['title'] as String? ?? '공연';
    final imageUrl = event['imageUrl'] as String?;
    final naverProductUrl = event['naverProductUrl'] as String?;
    final pamphletUrls = (event['pamphletUrls'] as List?)
        ?.cast<String>() ?? <String>[];
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
            const SizedBox(height: 4),

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
                          startAt: startAt,
                          venueName: venueName,
                          venueAddress: venueAddress,
                          gradeCol: gradeCol,
                          status: status,
                          isCancelled: isCancelled,
                          isUsed: isUsed,
                          qrRevealed: qrRevealed,
                          orderIndex: orderIndex,
                          totalInOrder: totalInOrder,
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
                            pamphletUrls: pamphletUrls,
                            onBack: _flipToFront,
                          ),
                        ),
                );
              },
            ),

            const SizedBox(height: 20),

            // ── 그룹 티켓: 이 티켓 전달하기 버튼 ──
            if (widget.isGroupTicket)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final url = '$_ticketBaseUrl${widget.accessToken}';
                      Share.share(
                        '$eventTitle 티켓\n$url',
                        subject: '티켓 전달',
                      );
                    },
                    icon: const Icon(Icons.send_rounded,
                        size: 18, color: AppTheme.gold),
                    label: Text(
                      '이 티켓 전달하기',
                      style: AppTheme.nanum(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.gold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AppTheme.gold.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),

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
// ── 그룹 티켓 헤더 (스와이프 인디케이터) ──
// ══════════════════════════════════════════════════════════

class _GroupTicketHeader extends StatelessWidget {
  final int current;
  final int total;
  const _GroupTicketHeader({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.confirmation_number_outlined,
              size: 16, color: AppTheme.gold),
          const SizedBox(width: 8),
          Text(
            '${current + 1} / $total',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _cream,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: List.generate(
              total,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: i == current ? 18 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i == current
                      ? AppTheme.gold
                      : _cream.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
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
  final DateTime? startAt;
  final String venueName;
  final String venueAddress;
  final Color gradeCol;
  final String status;
  final bool isCancelled;
  final bool isUsed;
  final bool qrRevealed;
  final int orderIndex;
  final int totalInOrder;
  final VoidCallback onQrTap;

  const _FrontCard({
    required this.eventTitle,
    this.imageUrl,
    this.naverProductUrl,
    required this.buyerName,
    required this.seatGrade,
    this.startAt,
    required this.venueName,
    required this.venueAddress,
    required this.gradeCol,
    required this.status,
    required this.isCancelled,
    required this.isUsed,
    required this.qrRevealed,
    required this.orderIndex,
    required this.totalInOrder,
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
        child: Stack(
          children: [
            Column(
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

            // ── 공연 정보 섹션 (v4 레이아웃) ──
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
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                      noShadow: true,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),

                  // Date & Time (합침)
                  _InfoField(
                    label: 'Date & Time',
                    value: startAt != null
                        ? DateFormat('yyyy.MM.dd (E)  HH:mm', 'ko_KR')
                            .format(startAt!)
                        : '-',
                  ),
                  const SizedBox(height: 14),

                  // Venue
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
                  const SizedBox(height: 16),

                  // Passenger + Grade (한 줄, 각각 라벨)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _InfoField(
                          label: 'Passenger',
                          value: buyerName,
                          valueStyle: GoogleFonts.dmSerifDisplay(
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                            color: _textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _InfoField(
                        label: 'Grade',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                gradeCol,
                                gradeCol.withValues(alpha: 0.85),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: gradeCol.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '${seatGrade}석',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Status — LIVE 카운트다운 (풀 width)
                  _InfoField(
                    label: 'Status',
                    child: _LiveStatusInCard(
                      startAt: startAt,
                      isCancelled: isCancelled,
                      isUsed: isUsed,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Tickets (n매 중 몇 번째)
                  if (totalInOrder > 1)
                    _InfoField(
                      label: 'Tickets',
                      value: '${totalInOrder}매 ($orderIndex/$totalInOrder)',
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 구분선 (골드 다이아몬드) ──
            _GoldDivider(),

            const SizedBox(height: 16),

            // ── 런타임 & 인터미션 (가운데 정렬) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _InfoFieldCenter(
                      label: 'Runtime',
                      value: '2시간 10분',
                    ),
                  ),
                  Expanded(
                    child: _InfoFieldCenter(
                      label: 'Intermission',
                      value: '15분',
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
            // ── 종이 질감 오버레이 ──
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _PaperTexturePainter()),
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
  final List<String> pamphletUrls;
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
    this.pamphletUrls = const [],
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
      child: ClipPath(
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
          child: Stack(
            children: [
              Column(
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

            // ── 팜플렛 갤러리 ──
            if (widget.pamphletUrls.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.auto_stories_rounded,
                        size: 14, color: _textLight),
                    const SizedBox(width: 6),
                    Text(
                      'PROGRAMME',
                      style: GoogleFonts.dmSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _textLight,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.pamphletUrls.length}p',
                      style: GoogleFonts.dmSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _textLight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: _PamphletGallery(
                  urls: widget.pamphletUrls,
                ),
              ),
              const SizedBox(height: 8),
            ],

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
              // ── 종이 질감 오버레이 ──
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _PaperTexturePainter()),
                ),
              ),
            ],
          ),
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
            const Color(0xFF2A0A0E),
            gradeCol.withValues(alpha: 0.5),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.confirmation_number_rounded,
              size: 14, color: AppTheme.gold.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Text(
            'SMART TICKET',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _cream.withValues(alpha: 0.9),
              letterSpacing: 4,
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

enum _LiveStatus { upcoming, playing, ended }

// ── 카드 내부 LIVE 카운트다운 (크림 배경용) ──
class _LiveStatusInCard extends StatefulWidget {
  final DateTime? startAt;
  final bool isCancelled;
  final bool isUsed;

  const _LiveStatusInCard({
    this.startAt,
    required this.isCancelled,
    required this.isUsed,
  });

  @override
  State<_LiveStatusInCard> createState() => _LiveStatusInCardState();
}

class _LiveStatusInCardState extends State<_LiveStatusInCard>
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
    final endAt = widget.startAt!.add(const Duration(hours: 2, minutes: 10));

    if (now.isBefore(widget.startAt!)) {
      setState(() {
        _remaining = widget.startAt!.difference(now);
        _status = _LiveStatus.upcoming;
      });
    } else if (now.isBefore(endAt)) {
      setState(() {
        _remaining = endAt.difference(now);
        _status = _LiveStatus.playing;
      });
    } else {
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

  String _fmt(Duration d) {
    if (d.inDays > 0) {
      final h = d.inHours % 24;
      final m = d.inMinutes % 60;
      final s = d.inSeconds % 60;
      return 'D-${d.inDays} ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCancelled) {
      return Text('취소됨',
          style: GoogleFonts.inter(
              fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFFFF5A5F)));
    }
    if (widget.isUsed) {
      return Text('이용완료',
          style: GoogleFonts.inter(
              fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF22C55E)));
    }

    final isToday = widget.startAt != null &&
        widget.startAt!.difference(DateTime.now()).inDays == 0 &&
        _status == _LiveStatus.upcoming;

    final Color dotColor;
    final String labelText;

    switch (_status) {
      case _LiveStatus.upcoming:
        dotColor = const Color(0xFF22C55E);
        labelText = isToday ? 'TODAY' : 'LIVE';
      case _LiveStatus.playing:
        dotColor = const Color(0xFFFF4444);
        labelText = 'NOW PLAYING';
      case _LiveStatus.ended:
        dotColor = _textLight;
        labelText = 'ENDED';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                      : Color.lerp(dotColor, dotColor.withValues(alpha: 0.3), _pulseCtrl.value),
                  boxShadow: _status != _LiveStatus.ended
                      ? [BoxShadow(color: dotColor.withValues(alpha: 0.4 * (1 - _pulseCtrl.value)), blurRadius: 6)]
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              labelText,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: dotColor,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        if (_status == _LiveStatus.upcoming && widget.startAt != null) ...[
          const SizedBox(height: 3),
          Text(
            _fmt(_remaining),
            style: GoogleFonts.robotoMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '좌석 배정까지 남은 시간',
            style: AppTheme.nanum(fontSize: 11, color: _textLight, noShadow: true),
          ),
        ],
        if (_status == _LiveStatus.playing) ...[
          const SizedBox(height: 2),
          Text(
            '공연 진행 중',
            style: AppTheme.nanum(fontSize: 11, color: _textLight, noShadow: true),
          ),
        ],
      ],
    );
  }
}

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

// ── 정보 필드 (가운데 정렬) ──
class _InfoFieldCenter extends StatelessWidget {
  final String label;
  final String value;

  const _InfoFieldCenter({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
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
        Text(
          value,
          style: AppTheme.nanum(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _textDark,
            noShadow: true,
          ),
        ),
      ],
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
          Expanded(
            child: Container(
              height: 0.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _divider.withValues(alpha: 0),
                    AppTheme.gold.withValues(alpha: 0.4),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '◆',
              style: TextStyle(
                  fontSize: 8, color: AppTheme.gold.withValues(alpha: 0.5)),
            ),
          ),
          Expanded(
            child: Container(
              height: 0.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.gold.withValues(alpha: 0.4),
                    _divider.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
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

// ── 종이 질감 오버레이 ──
class _PaperTexturePainter extends CustomPainter {
  final math.Random _rng = math.Random(42);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Layer 1: 굵은 섬유질 (fiber strokes) — 종이의 결
    for (int i = 0; i < 60; i++) {
      final x = _rng.nextDouble() * size.width;
      final y = _rng.nextDouble() * size.height;
      final len = 8 + _rng.nextDouble() * 20;
      final angle = -0.3 + _rng.nextDouble() * 0.6; // 거의 수평
      paint
        ..color = Colors.black.withValues(alpha: 0.015 + _rng.nextDouble() * 0.02)
        ..strokeWidth = 0.3 + _rng.nextDouble() * 0.4
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + len * math.cos(angle), y + len * math.sin(angle)),
        paint,
      );
    }

    // Layer 2: 고밀도 노이즈 도트 (grain) — 종이 질감 핵심
    paint.style = PaintingStyle.fill;
    for (int i = 0; i < 2500; i++) {
      final x = _rng.nextDouble() * size.width;
      final y = _rng.nextDouble() * size.height;
      final isDark = _rng.nextDouble() > 0.4;
      paint.color = (isDark ? Colors.black : Colors.white)
          .withValues(alpha: 0.04 + _rng.nextDouble() * 0.04);
      canvas.drawCircle(Offset(x, y), 0.4 + _rng.nextDouble() * 0.6, paint);
    }

    // Layer 3: 따뜻한 반점 (warm spots) — 오래된 종이 느낌
    for (int i = 0; i < 15; i++) {
      final x = _rng.nextDouble() * size.width;
      final y = _rng.nextDouble() * size.height;
      final r = 10 + _rng.nextDouble() * 30;
      final spot = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFD4C5A9).withValues(alpha: 0.06),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: r));
      canvas.drawCircle(Offset(x, y), r, spot);
    }

    // Layer 4: 가장자리 비네팅 (강화)
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.06),
        ],
        stops: const [0.6, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignette);

    // Layer 5: 접힌 자국 (노치 위치 근처, 더 뚜렷하게)
    final foldY = size.height * 0.55;
    final foldPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(12, foldY), Offset(size.width - 12, foldY), foldPaint);
    // 접힌 자국 하이라이트 (바로 아래 밝은 선)
    final foldHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(12, foldY + 1),
      Offset(size.width - 12, foldY + 1),
      foldHighlight,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── 팜플렛 갤러리 (가로 스크롤 + 탭 → 풀스크린) ──
class _PamphletGallery extends StatelessWidget {
  final List<String> urls;
  const _PamphletGallery({required this.urls});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: urls.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => _openFullscreen(context, index),
          child: Container(
            width: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.network(
                urls[index],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: _creamDark,
                  child: const Center(
                    child: Icon(Icons.image_not_supported_outlined,
                        size: 24, color: _textLight),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openFullscreen(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => _PamphletFullscreen(
          urls: urls,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }
}

class _PamphletFullscreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _PamphletFullscreen({required this.urls, required this.initialIndex});

  @override
  State<_PamphletFullscreen> createState() => _PamphletFullscreenState();
}

class _PamphletFullscreenState extends State<_PamphletFullscreen> {
  late PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            // 페이지 뷰
            PageView.builder(
              controller: _ctrl,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Image.network(
                        widget.urls[index],
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                );
              },
            ),

            // 상단 닫기 + 페이지 번호
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_current + 1} / ${widget.urls.length}',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 하단 도트 인디케이터
            if (widget.urls.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.urls.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _current ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i == _current
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
