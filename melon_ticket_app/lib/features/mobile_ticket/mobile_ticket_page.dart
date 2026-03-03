import 'dart:async';
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
// 디자인: 기존 마이티켓 보딩패스 스타일 통일
// =============================================================================

// ── AppTheme aliases for convenience ──
const _surface = AppTheme.background;
const _card = AppTheme.card;
const _cardBorder = AppTheme.border;
const _textPrimary = AppTheme.textPrimary;
const _textSecondary = AppTheme.textSecondary;
const _textTertiary = AppTheme.textTertiary;
const _success = AppTheme.success;
const _error = AppTheme.error;

const _ticketBaseUrl = 'https://melonticket-web-20260216.vercel.app/m/';

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
      return const Scaffold(
        backgroundColor: _surface,
        body: Center(
          child: CircularProgressIndicator(
            color: AppTheme.gold,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_errorText != null || _ticketData == null) {
      return Scaffold(
        backgroundColor: _surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: _error,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _errorText ?? '오류가 발생했습니다',
                  style: AppTheme.nanum(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                    shadows: AppTheme.textShadow,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '링크가 올바른지 확인해주세요',
                  style: AppTheme.nanum(fontSize: 13, color: _textSecondary),
                ),
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
      backgroundColor: _surface,
      body: SafeArea(
        child: _TicketView(
          data: _ticketData!,
          accessToken: widget.accessToken,
        ),
      ),
    );
  }
}

// ─── Main Ticket View ───

class _TicketView extends ConsumerWidget {
  final Map<String, dynamic> data;
  final String accessToken;

  const _TicketView({required this.data, required this.accessToken});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = data['ticket'] as Map<String, dynamic>? ?? {};
    final event = data['event'] as Map<String, dynamic>? ?? {};

    final buyerName = ticket['buyerName'] as String? ?? '';
    final seatGrade = ticket['seatGrade'] as String? ?? '';
    final entryNumber = ticket['entryNumber'] as int? ?? 0;
    final status = ticket['status'] as String? ?? 'active';
    final seatInfo = ticket['seatInfo'] as String?;
    final seatNumber = ticket['seatNumber'] as String?;
    final ticketId = ticket['id'] as String? ?? '';
    final qrVersion = ticket['qrVersion'] as int? ?? 1;

    final eventTitle = event['title'] as String? ?? '공연';
    final imageUrl = event['imageUrl'] as String?;
    final naverProductUrl = event['naverProductUrl'] as String?;
    final venueName = event['venueName'] as String? ?? '';
    final venueAddress = event['venueAddress'] as String? ?? '';
    DateTime? startAt;
    final startAtStr = event['startAt'] as String?;
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

    // Grade color (same as 마이티켓)
    final gradeCol = _gradeColor(seatGrade);

    // Ticket URL for sharing
    final ticketUrl = '$_ticketBaseUrl$accessToken';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      child: Column(
        children: [
          // ── Boarding Pass Card (with punch-hole cutouts) ──
          ClipPath(
            clipper: const _BoardingPassClipper(
              notchRadius: 18,
              notchPosition: 0.62,
            ),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: _card,
                boxShadow: [
                  ...AppShadows.card,
                  BoxShadow(
                    color: gradeCol.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // ── Header: Grade gradient + SMART TICKET label ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          gradeCol,
                          gradeCol.withValues(alpha: 0.85),
                          AppTheme.gold,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.confirmation_number_rounded,
                          size: 14,
                          color: AppTheme.onAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'SMART TICKET',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onAccent,
                            letterSpacing: 2.5,
                          ),
                        ),
                        const Spacer(),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _statusBackground(status),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _statusLabel(status),
                            style: AppTheme.nanum(
                              color: _statusTextColor(status),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              noShadow: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Event title + info ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eventTitle,
                          style: AppTheme.nanum(
                            color: _textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            shadows: AppTheme.textShadowStrong,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        // Poster + info chips
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (imageUrl != null && imageUrl.isNotEmpty)
                              GestureDetector(
                                onTap: naverProductUrl != null &&
                                        naverProductUrl.isNotEmpty
                                    ? () => launchUrl(
                                        Uri.parse(naverProductUrl),
                                        mode:
                                            LaunchMode.externalApplication)
                                    : null,
                                child: Container(
                                  width: 64,
                                  height: 88,
                                  margin: const EdgeInsets.only(right: 14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: _cardBorder, width: 0.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.06),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: AppTheme.cardElevated,
                                      child: const Icon(
                                          Icons.music_note_rounded,
                                          color: _textTertiary,
                                          size: 24),
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  if (startAt != null) ...[
                                    _InfoChip(
                                      icon: Icons.calendar_today_rounded,
                                      text: DateFormat(
                                              'yyyy.MM.dd (E)', 'ko_KR')
                                          .format(startAt),
                                    ),
                                    const SizedBox(height: 6),
                                    _InfoChip(
                                      icon: Icons.access_time_rounded,
                                      text:
                                          DateFormat('HH:mm').format(startAt),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  if (venueName.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        final query = venueAddress.isNotEmpty
                                            ? venueAddress
                                            : venueName;
                                        final mapUrl = Uri.parse(
                                          'https://map.kakao.com/link/search/$query',
                                        );
                                        launchUrl(mapUrl,
                                            mode:
                                                LaunchMode.externalApplication);
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _InfoChip(
                                            icon: Icons.location_on_outlined,
                                            text: venueName,
                                          ),
                                          if (venueAddress.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 20, top: 2),
                                              child: Text(
                                                venueAddress,
                                                style: AppTheme.nanum(
                                                  fontSize: 10,
                                                  color: _textTertiary,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  _InfoChip(
                                    icon: Icons.person_outline_rounded,
                                    text: buyerName,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Seat Info / Entry Number ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: gradeCol.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: gradeCol.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          // Grade badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: gradeCol.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: gradeCol.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              seatGrade.isNotEmpty ? seatGrade : '일반',
                              style: AppTheme.nanum(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: gradeCol,
                              ),
                            ),
                          ),
                          // Vertical divider
                          Container(
                            width: 1,
                            height: 36,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 14),
                            color: gradeCol.withValues(alpha: 0.12),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '입장번호',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.5,
                                    color: _textTertiary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (seatInfo != null)
                                  Text(
                                    seatInfo,
                                    style: AppTheme.nanum(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimary,
                                      shadows: AppTheme.textShadow,
                                    ),
                                  )
                                else if (seatNumber != null)
                                  Text(
                                    '$seatGrade석 $seatNumber',
                                    style: AppTheme.nanum(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimary,
                                      shadows: AppTheme.textShadow,
                                    ),
                                  )
                                else
                                  Row(
                                    children: [
                                      Text(
                                        '#$entryNumber',
                                        style: GoogleFonts.inter(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: gradeCol,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '좌석 미공개',
                                        style: AppTheme.nanum(
                                          fontSize: 12,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Perforation line (dotted) ──
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 1,
                      child: CustomPaint(
                        painter: _DottedLinePainter(
                          color: AppTheme.sage.withValues(alpha: 0.3),
                          dashWidth: 5,
                          dashSpace: 4,
                        ),
                      ),
                    ),
                  ),

                  // ── QR Section or Status Banner ──
                  if (isCancelled)
                    _StatusBanner(
                      text: '취소된 티켓입니다',
                      color: _error,
                      icon: Icons.cancel_outlined,
                    )
                  else if (isUsed)
                    _StatusBanner(
                      text: '입장이 완료되었습니다',
                      color: _success,
                      icon: Icons.check_circle_outlined,
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // QR code (left)
                          Container(
                            width: 120,
                            height: 120,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: AppTheme.borderLight),
                            ),
                            child: _MobileQrSection(
                              ticketId: ticketId,
                              accessToken: accessToken,
                              qrVersion: qrVersion,
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Ticket meta (right)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '입장번호',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.5,
                                    color: _textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '#$entryNumber',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimary,
                                    letterSpacing: 1.5,
                                    shadows: [
                                      Shadow(
                                        color: _textPrimary
                                            .withValues(alpha: 0.1),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '구매자',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.5,
                                    color: _textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  buyerName,
                                  style: AppTheme.nanum(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (!isCancelled && !isUsed) const SizedBox(height: 0),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Share & Invite Actions ──
          if (!isCancelled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Copy link
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.link_rounded,
                          label: '링크 복사',
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: ticketUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '티켓 링크가 복사되었습니다',
                                  style: AppTheme.nanum(
                                      color: Colors.white),
                                ),
                                backgroundColor: _success,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 44,
                        color: _cardBorder,
                      ),
                      // Share
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.share_rounded,
                          label: '공유하기',
                          onTap: () {
                            Share.share(
                              '[$eventTitle] 모바일 티켓\n$ticketUrl',
                              subject: eventTitle,
                            );
                          },
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 44,
                        color: _cardBorder,
                      ),
                      // Invite friend
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.group_add_rounded,
                          label: '친구 초대',
                          color: AppTheme.gold,
                          onTap: () {
                            final inviteText =
                                '같이 가요! $eventTitle\n'
                                '${startAt != null ? DateFormat('M월 d일 (E) HH:mm', 'ko_KR').format(startAt!) : ''}'
                                '${venueName.isNotEmpty ? ' @ $venueName' : ''}\n'
                                '${naverProductUrl ?? ticketUrl}';
                            Share.share(
                              inviteText,
                              subject: '공연 초대',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // ── 네이버 스토어 버튼 ──
          if (naverProductUrl != null && naverProductUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
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
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF03C75A), // 네이버 그린
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),

          // ── Footer note ──
          Text(
            '이 티켓은 공연 당일 입장 시 QR코드를 스캔하여 확인합니다.\n'
            'QR코드는 보안을 위해 2분마다 자동 갱신됩니다.',
            textAlign: TextAlign.center,
            style: AppTheme.nanum(
              fontSize: 11,
              color: _textTertiary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grade color helper (matches 마이티켓) ───

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
      return _textSecondary;
  }
}

// ─── Status helpers ───

Color _statusBackground(String status) {
  switch (status) {
    case 'active':
      return AppTheme.gold;
    case 'used':
      return const Color(0x1A30D158);
    case 'cancelled':
      return const Color(0x1AFF5A5F);
    default:
      return AppTheme.gold;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'active':
      return '스마트티켓';
    case 'used':
      return '이용완료';
    case 'cancelled':
      return '취소됨';
    default:
      return '스마트티켓';
  }
}

Color _statusTextColor(String status) {
  switch (status) {
    case 'active':
      return AppTheme.onAccent;
    case 'used':
      return _success;
    case 'cancelled':
      return _error;
    default:
      return AppTheme.onAccent;
  }
}

// ─── Boarding Pass Clipper (matches 마이티켓) ───

class _BoardingPassClipper extends CustomClipper<Path> {
  final double notchRadius;
  final double notchPosition;

  const _BoardingPassClipper({
    this.notchRadius = 18,
    this.notchPosition = 0.55,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    final notchY = size.height * notchPosition;

    path.moveTo(14, 0);
    path.lineTo(size.width - 14, 0);
    path.arcToPoint(
      Offset(size.width, 14),
      radius: const Radius.circular(14),
    );

    path.lineTo(size.width, notchY - notchRadius);
    path.arcToPoint(
      Offset(size.width, notchY + notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    path.lineTo(size.width, size.height - 14);
    path.arcToPoint(
      Offset(size.width - 14, size.height),
      radius: const Radius.circular(14),
    );

    path.lineTo(14, size.height);
    path.arcToPoint(
      Offset(0, size.height - 14),
      radius: const Radius.circular(14),
    );

    path.lineTo(0, notchY + notchRadius);
    path.arcToPoint(
      Offset(0, notchY - notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    path.lineTo(0, 14);
    path.arcToPoint(
      const Offset(14, 0),
      radius: const Radius.circular(14),
    );

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _BoardingPassClipper oldClipper) =>
      notchRadius != oldClipper.notchRadius ||
      notchPosition != oldClipper.notchPosition;
}

// ─── Dotted Line Painter (matches 마이티켓) ───

class _DottedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;

  _DottedLinePainter({
    required this.color,
    this.dashWidth = 5,
    this.dashSpace = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter old) =>
      color != old.color ||
      dashWidth != old.dashWidth ||
      dashSpace != old.dashSpace;
}

// ─── Info Chip (icon + text) ───

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppTheme.nanum(fontSize: 12, color: _textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─── Status Banner (cancelled / used) ───

class _StatusBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _StatusBanner(
      {required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTheme.nanum(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action Button (share bar) ───

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? _textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.nanum(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mobile QR Section (auto-refresh, 2min JWT) ───

class _MobileQrSection extends ConsumerStatefulWidget {
  final String ticketId;
  final String accessToken;
  final int qrVersion;

  const _MobileQrSection({
    required this.ticketId,
    required this.accessToken,
    required this.qrVersion,
  });

  @override
  ConsumerState<_MobileQrSection> createState() => _MobileQrSectionState();
}

class _MobileQrSectionState extends ConsumerState<_MobileQrSection> {
  static const int _refreshIntervalSeconds = 120;

  int _remainingSeconds = _refreshIntervalSeconds;
  String? _qrData;
  bool _isLoading = true;
  String? _errorText;
  bool _isRefreshingToken = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _refreshQrToken();
  }

  @override
  void didUpdateWidget(covariant _MobileQrSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ticketId != oldWidget.ticketId ||
        widget.qrVersion != oldWidget.qrVersion) {
      _refreshQrToken();
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      }
      if (_remainingSeconds <= 0) {
        _refreshQrToken();
      }
    });
  }

  Future<void> _refreshQrToken() async {
    if (_isRefreshingToken) return;
    if (!mounted) return;

    _isRefreshingToken = true;
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

  String _formatRemaining(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // QR Code
        Expanded(child: Center(child: _buildQrContent())),
        // Timer badge
        _buildTimerBadge(),
      ],
    );
  }

  Widget _buildQrContent() {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child:
            CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2),
      );
    }

    if (_qrData == null) {
      return GestureDetector(
        onTap: _refreshQrToken,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded,
                size: 24, color: _textSecondary),
            const SizedBox(height: 4),
            Text(
              _errorText ?? 'QR 실패',
              style: AppTheme.nanum(fontSize: 10, color: _textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _refreshQrToken,
      child: QrImageView(
        data: _qrData!,
        version: QrVersions.auto,
        size: 96,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF111827),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF111827),
        ),
        gapless: true,
      ),
    );
  }

  Widget _buildTimerBadge() {
    final isLow = _remainingSeconds <= 30;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLow
            ? AppTheme.warning.withValues(alpha: 0.1)
            : AppTheme.cardElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLow ? AppTheme.warning : _cardBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 10,
            color: isLow ? AppTheme.warning : _textSecondary,
          ),
          const SizedBox(width: 2),
          Text(
            _formatRemaining(_remainingSeconds),
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              color: isLow ? AppTheme.warning : _textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
