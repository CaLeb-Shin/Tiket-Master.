import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:melon_core/melon_core.dart';

// =============================================================================
// 네이버 구매자용 모바일 티켓 페이지 (비로그인, 공개 URL)
// =============================================================================

// ── Color palette (boarding-pass style) ──
const _navy = Color(0xFF3B0D11);
const _accent = Color(0xFF5D141A);
const _surface = Color(0xFFFAF8F5);
const _card = Color(0xFFFFFFFF);
const _border = Color(0x33748386);
const _textPrimary = Color(0xFF111827);
const _textSecondary = Color(0xFF6B7280);
const _textTertiary = Color(0x99748386);
const _success = Color(0xFF2D6A4F);
const _error = Color(0xFFC42A4D);
const _warning = Color(0xFFD4A574);

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
          child: CircularProgressIndicator(color: _navy, strokeWidth: 2),
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
                const Icon(Icons.error_outline_rounded,
                    color: _error, size: 48),
                const SizedBox(height: 16),
                Text(
                  _errorText ?? '오류가 발생했습니다',
                  style: AppTheme.nanum(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary),
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
                  style: TextButton.styleFrom(foregroundColor: _navy),
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
    final venueName = event['venueName'] as String? ?? '';
    final startAtStr = event['startAt'] as String?;
    DateTime? startAt;
    if (startAtStr != null) {
      startAt = DateTime.tryParse(startAtStr);
    }
    // Try Firestore timestamp format
    if (startAt == null && event['startAt'] is Map) {
      final ts = event['startAt'] as Map;
      final seconds = ts['_seconds'] as int?;
      if (seconds != null) {
        startAt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }

    final isCancelled = status == 'cancelled';
    final isUsed = status == 'used';

    // Grade color
    Color gradeColor;
    switch (seatGrade) {
      case 'VIP':
        gradeColor = const Color(0xFFD4A574);
      case 'R':
        gradeColor = const Color(0xFF2F6FB2);
      case 'S':
        gradeColor = _success;
      default:
        gradeColor = _textSecondary;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        children: [
          // ── Boarding Pass Card ──
          Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // ── Header gradient strip ──
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_navy, _accent],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MOBILE TICKET',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.0,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              eventTitle,
                              style: AppTheme.nanum(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Grade badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: gradeColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: gradeColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          seatGrade,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Event info section ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    children: [
                      // Poster + info
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Poster thumbnail
                          if (imageUrl != null && imageUrl.isNotEmpty)
                            Container(
                              width: 64,
                              height: 88,
                              margin: const EdgeInsets.only(right: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _border, width: 0.5),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFFF0ECE4),
                                  child: const Icon(Icons.music_note_rounded,
                                      color: _textTertiary, size: 24),
                                ),
                              ),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (startAt != null) ...[
                                  _InfoChip(
                                    icon: Icons.calendar_today_rounded,
                                    text: DateFormat('yyyy.MM.dd (E)', 'ko_KR')
                                        .format(startAt),
                                  ),
                                  const SizedBox(height: 6),
                                  _InfoChip(
                                    icon: Icons.access_time_rounded,
                                    text: DateFormat('HH:mm').format(startAt),
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                if (venueName.isNotEmpty)
                                  _InfoChip(
                                    icon: Icons.location_on_outlined,
                                    text: venueName,
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
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F6F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      // Entry number circle
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: gradeColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: gradeColor.withValues(alpha: 0.3)),
                        ),
                        child: Center(
                          child: Text(
                            '#$entryNumber',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: gradeColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '입장번호',
                              style: GoogleFonts.inter(
                                fontSize: 10,
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
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                ),
                              )
                            else if (seatNumber != null)
                              Text(
                                '$seatGrade석 $seatNumber',
                                style: AppTheme.nanum(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                ),
                              )
                            else
                              Text(
                                '좌석 미공개 — 공연 당일 공개',
                                style: AppTheme.nanum(
                                  fontSize: 13,
                                  color: _textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Dotted perforation ──
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: List.generate(
                      40,
                      (i) => Expanded(
                        child: Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          color:
                              i % 2 == 0 ? _border : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── QR Section ──
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
                  _MobileQrSection(
                    ticketId: ticketId,
                    accessToken: accessToken,
                    qrVersion: qrVersion,
                  ),

                const SizedBox(height: 16),
              ],
            ),
          ),

          const SizedBox(height: 16),

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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 20),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // QR Code
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border, width: 0.5),
            ),
            child: Center(child: _buildQrContent()),
          ),

          const SizedBox(height: 12),

          // Timer badge
          _buildTimerBadge(),

          const SizedBox(height: 4),

          // Hint
          Text(
            'QR코드를 탭하면 즉시 갱신됩니다',
            style: AppTheme.nanum(fontSize: 10, color: _textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildQrContent() {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(color: _navy, strokeWidth: 2),
      );
    }

    if (_qrData == null) {
      return GestureDetector(
        onTap: _refreshQrToken,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 24, color: _textSecondary),
            const SizedBox(height: 4),
            Text(
              _errorText ?? 'QR 실패',
              style: AppTheme.nanum(fontSize: 11, color: _textSecondary),
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
        size: 156,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isLow
            ? _warning.withValues(alpha: 0.1)
            : _surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLow ? _warning : _border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 12,
            color: isLow ? _warning : _textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            _formatRemaining(_remainingSeconds),
            style: GoogleFonts.robotoMono(
              fontSize: 12,
              color: isLow ? _warning : _textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
