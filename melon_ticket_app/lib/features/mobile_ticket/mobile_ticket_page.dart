import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:melon_core/melon_core.dart';
import 'mobile_ticket_logic.dart';

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
const _ticketAccent = Color(0xFFD4A574);
const _defaultRevealLeadTime = Duration(hours: 2);

DateTime? _parseEventDateTime(dynamic raw) => switch (raw) {
  DateTime value => value,
  String value => DateTime.tryParse(value),
  {'_seconds': int seconds} => DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
  ),
  {'seconds': int seconds} => DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
  ),
  _ => null,
};

String? _maskPhoneNumber(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 7) return raw;

  final prefix = digits.substring(0, 3);
  final last = digits.substring(digits.length - 4);
  final maskedMiddle = '*' * (digits.length - 7);
  return '$prefix-$maskedMiddle-$last';
}

String _formatShareSchedule(DateTime? startAt, String venueName) {
  final parts = <String>[
    if (startAt != null)
      DateFormat('yyyy.MM.dd (E) HH:mm', 'ko_KR').format(startAt),
    if (venueName.trim().isNotEmpty) venueName.trim(),
  ];
  return parts.join(' | ');
}

String _buildTicketShareMessage({
  required String eventTitle,
  required DateTime? startAt,
  required String venueName,
  required String url,
}) {
  return [
    '🎫 $eventTitle 모바일 티켓',
    '',
    if (startAt != null)
      '📅 ${DateFormat('yyyy.MM.dd (E) HH:mm', 'ko_KR').format(startAt)}',
    if (venueName.trim().isNotEmpty) '📍 ${venueName.trim()}',
    '',
    '👇 공연장 입장 시 이 링크의 QR을 보여주세요',
    url,
  ].join('\n');
}

String _buildTransferShareMessage({
  required String eventTitle,
  required String recipientName,
  required DateTime? startAt,
  required String venueName,
  required String url,
}) {
  return [
    recipientName.isNotEmpty
        ? '🎫 ${recipientName}님이 티켓을 보냈어요!'
        : '🎫 티켓을 전달했어요!',
    '',
    '🎵 $eventTitle',
    if (startAt != null)
      '📅 ${DateFormat('yyyy.MM.dd (E) HH:mm', 'ko_KR').format(startAt)}',
    if (venueName.trim().isNotEmpty) '📍 ${venueName.trim()}',
    '',
    '👇 아래 링크에서 모바일 티켓을 확인하세요',
    url,
  ].join('\n');
}

String _buildInviteShareMessage({
  required String eventTitle,
  required DateTime? startAt,
  required String venueName,
  required String url,
}) {
  return [
    '🎶 같이 가요! $eventTitle',
    '',
    if (startAt != null)
      '📅 ${DateFormat('yyyy.MM.dd (E) HH:mm', 'ko_KR').format(startAt)}',
    if (venueName.trim().isNotEmpty) '📍 ${venueName.trim()}',
    '',
    '👇 아래 링크에서 예매할 수 있어요',
    url,
  ].join('\n');
}

/// 데스크톱 브라우저에서 티켓 컨텐츠를 중앙 쇼케이스로 감싸는 래퍼.
/// 좁은 화면에서는 그대로 패스스루.
const _desktopBreakpoint = 600.0;
const _desktopMaxWidth = 480.0;

Widget _desktopShowcase(Widget child) {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth <= _desktopBreakpoint) return child;
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_cream, Color(0xFFF5F0EB), Color(0xFFEFE7E1)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 56,
              left: -120,
              child: IgnorePointer(
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _burgundy.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 96,
              right: -80,
              child: IgnorePointer(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.goldLight.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _desktopMaxWidth),
                child: child,
              ),
            ),
          ],
        ),
      );
    },
  );
}

typedef _TicketStateInfo = TicketStateInfo;

String _normalizeTicketStatus(String? raw) => normalizeTicketStatus(raw);

_TicketStateInfo _resolveTicketState({
  required String? status,
  required bool isCheckedIn,
  required bool isRevealed,
  bool isIntermissionCheckedIn = false,
  String? eventStatus,
}) => resolveTicketState(
  status: status,
  isCheckedIn: isCheckedIn,
  isRevealed: isRevealed,
  isIntermissionCheckedIn: isIntermissionCheckedIn,
  eventStatus: eventStatus,
);

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
  bool _showGroupOverview = false;

  @override
  void initState() {
    super.initState();
    _loadTicket();
  }

  bool _isFromCache = false;

  Future<void> _loadTicket({bool preserveGroupContext = false}) async {
    final previousPage = _currentPage;
    final previousOverview = _showGroupOverview;

    setState(() {
      _isLoading = true;
      _errorText = null;
      _isFromCache = false;
    });

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .getMobileTicketByToken(accessToken: widget.accessToken);
      if (!mounted) return;

      // 성공 시 로컬 캐시에 저장 (오프라인 폴백용)
      _saveTicketCache(widget.accessToken, result);

      _applyTicketData(result, preserveGroupContext, previousPage, previousOverview);
    } catch (e) {
      if (!mounted) return;
      // 네트워크 실패 시 로컬 캐시에서 로드
      final cached = await _loadTicketCache(widget.accessToken);
      if (cached != null && mounted) {
        _applyTicketData(cached, preserveGroupContext, previousPage, previousOverview);
        setState(() => _isFromCache = true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = '티켓을 찾을 수 없습니다';
      });
    }
  }

  void _applyTicketData(
    Map<String, dynamic> result,
    bool preserveGroupContext,
    int previousPage,
    bool previousOverview,
  ) {
    final siblings =
        (result['siblings'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final groupViewState = deriveGroupTicketViewState(
      siblings: siblings,
      currentAccessToken: widget.accessToken,
      preserveGroupContext: preserveGroupContext,
      previousPage: previousPage,
      previousOverview: previousOverview,
    );

    _pageController?.dispose();
    setState(() {
      _ticketData = result;
      _isLoading = false;
      _currentPage = groupViewState.currentPage;
      _pageController = PageController(
        initialPage: groupViewState.currentPage,
      );
      _showGroupOverview = groupViewState.showGroupOverview;
    });
  }

  // ─── 로컬 캐시 (오프라인 폴백용) ───
  static const _cacheKeyPrefix = 'ticket_cache_';

  Future<void> _saveTicketCache(String token, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cacheKeyPrefix$token', jsonEncode(data));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _loadTicketCache(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cacheKeyPrefix$token');
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _openGroupTicket(int index) {
    // PageView isn't in the widget tree while overview is shown,
    // so jumpToPage() is a no-op. Recreate controller with correct initial page.
    _pageController?.dispose();
    _pageController = PageController(initialPage: index);
    setState(() {
      _currentPage = index;
      _showGroupOverview = false;
    });
  }

  void _backToGroupOverview() {
    setState(() => _showGroupOverview = true);
  }

  Future<void> _refreshTicketState() {
    return _loadTicket(preserveGroupContext: true);
  }

  void _updateRecipientName({
    required String accessToken,
    required String recipientName,
  }) {
    final currentData = _ticketData;
    if (currentData == null) return;

    final currentTicket = Map<String, dynamic>.from(
      currentData['ticket'] as Map? ?? {},
    );
    if (currentTicket['accessToken'] == accessToken) {
      currentTicket['recipientName'] = recipientName;
    }

    final updatedSiblings = ((currentData['siblings'] as List?) ?? []).map((
      item,
    ) {
      final sibling = Map<String, dynamic>.from(item as Map);
      if (sibling['accessToken'] == accessToken) {
        sibling['recipientName'] = recipientName;
      }
      return sibling;
    }).toList();

    setState(() {
      _ticketData = {
        ...currentData,
        'ticket': currentTicket,
        'siblings': updatedSiblings,
      };
    });
  }

  Future<void> _showTransferDialog(
    BuildContext context, {
    required String eventTitle,
    required DateTime? startAt,
    required String venueName,
    required String accessToken,
  }) async {
    // 이름 입력 없이 바로 공유 (예매자 이름 그대로 사용)
    final url = '$_ticketBaseUrl$accessToken';
    if (!mounted) return;

    final ticket = _ticketData?['ticket'] as Map<String, dynamic>? ?? {};
    final buyerName = ticket['buyerName'] as String? ?? '';

    Share.share(
      _buildTransferShareMessage(
        eventTitle: eventTitle,
        recipientName: buyerName,
        startAt: startAt,
        venueName: venueName,
        url: url,
      ),
      subject: '🎫 티켓이 도착했어요!',
    );
  }

  Map<String, dynamic> _buildGroupTicketData(
    Map<String, dynamic> sibling,
    int index,
    int total,
  ) {
    final mainTicket = _ticketData!['ticket'] as Map<String, dynamic>? ?? {};
    return <String, dynamic>{
      'ticket': <String, dynamic>{
        ...sibling,
        'eventId': mainTicket['eventId'],
        'orderIndex': index + 1,
        'totalInOrder': total,
      },
      'event': _ticketData!['event'],
      'isRevealed': _ticketData!['isRevealed'],
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _cream,
        body: _desktopShowcase(
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: _burgundy,
                  strokeWidth: 2,
                ),
                const SizedBox(height: 16),
                Text(
                  '티켓 불러오는 중...',
                  style: AppTheme.nanum(
                    fontSize: 13,
                    color: _burgundy.withValues(alpha: 0.74),
                    noShadow: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_errorText != null || _ticketData == null) {
      return Scaffold(
        backgroundColor: _cream,
        body: _desktopShowcase(
          Center(
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
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFFF6B6B),
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _errorText ?? '오류가 발생했습니다',
                    style: AppTheme.nanum(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _burgundy,
                      noShadow: true,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '링크가 올바른지 확인해주세요',
                    style: AppTheme.nanum(
                      fontSize: 13,
                      color: _burgundy.withValues(alpha: 0.70),
                      noShadow: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: _loadTicket,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('다시 시도'),
                    style: TextButton.styleFrom(foregroundColor: _burgundy),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final siblings =
        (_ticketData!['siblings'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // 그룹 티켓 (2장 이상) → 메인 화면 후 개별 티켓 진입
    if (siblings.length > 1 && _pageController != null) {
      final event = _ticketData!['event'] as Map<String, dynamic>? ?? {};
      final eventTitle = event['title'] as String? ?? '공연';
      final imageUrl = event['imageUrl'] as String?;
      final venueName = event['venueName'] as String? ?? '';
      final startAt = _parseEventDateTime(event['startAt']);
      final isRevealed = _ticketData!['isRevealed'] == true;

      if (_showGroupOverview) {
        return Scaffold(
          backgroundColor: _cream,
          body: _desktopShowcase(
            SafeArea(
              child: _GroupTicketOverview(
                eventTitle: eventTitle,
                imageUrl: imageUrl,
                venueName: venueName,
                startAt: startAt,
                siblings: siblings,
                isRevealed: isRevealed,
                onRefresh: _refreshTicketState,
                onOpenTicket: _openGroupTicket,
                onTransferTicket: (accessToken) => _showTransferDialog(
                  context,
                  eventTitle: eventTitle,
                  startAt: startAt,
                  venueName: venueName,
                  accessToken: accessToken,
                ),
              ),
            ),
          ),
        );
      }

      return Scaffold(
        backgroundColor: _cream,
        body: _desktopShowcase(
          SafeArea(
            child: Column(
              children: [
                _GroupTicketHeader(
                  current: _currentPage,
                  total: siblings.length,
                  onBackToOverview: _backToGroupOverview,
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController!,
                    itemCount: siblings.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (context, index) {
                      final sibling = Map<String, dynamic>.from(
                        siblings[index],
                      );
                      final data = _buildGroupTicketData(
                        sibling,
                        index,
                        siblings.length,
                      );
                      return _TicketView(
                        data: data,
                        accessToken: sibling['accessToken'] as String,
                        isGroupTicket: true,
                        onRefresh: _refreshTicketState,
                        onRecipientNameUpdated: _updateRecipientName,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 단일 티켓
    return Scaffold(
      backgroundColor: _cream,
      body: _desktopShowcase(
        SafeArea(
          child: Column(
            children: [
              if (_isFromCache) _buildCacheBanner(),
              Expanded(
                child: _TicketView(
                  data: _ticketData!,
                  accessToken: widget.accessToken,
                  onRefresh: _refreshTicketState,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCacheBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFFFF3CD),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 14, color: Color(0xFF856404)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '오프라인 — 마지막 저장 데이터 표시 중',
              style: AppTheme.nanum(
                fontSize: 12,
                color: const Color(0xFF856404),
                noShadow: true,
              ),
            ),
          ),
          InkWell(
            onTap: _loadTicket,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF856404)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Main Ticket View (앞/뒤 플립) ───

class _TicketView extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  final String accessToken;
  final bool isGroupTicket;
  final Future<void> Function()? onRefresh;
  final void Function({
    required String accessToken,
    required String recipientName,
  })?
  onRecipientNameUpdated;

  const _TicketView({
    required this.data,
    required this.accessToken,
    this.isGroupTicket = false,
    this.onRefresh,
    this.onRecipientNameUpdated,
  });

  @override
  ConsumerState<_TicketView> createState() => _TicketViewState();
}

class _TicketViewState extends ConsumerState<_TicketView>
    with SingleTickerProviderStateMixin {
  bool _showFront = true;
  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;
  final _cardKey = GlobalKey();
  final _sharePosterKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _flipAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutCubic));
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

  Future<void> _showTransferDialog(
    BuildContext context, {
    required String eventTitle,
    required String accessToken,
  }) async {
    // 이름 입력 없이 바로 공유 (예매자 이름 그대로 사용)
    final url = '$_ticketBaseUrl$accessToken';
    final event = widget.data['event'] as Map<String, dynamic>? ?? {};
    final ticket = widget.data['ticket'] as Map<String, dynamic>? ?? {};
    final startAt = _parseEventDateTime(event['startAt']);
    final venueName = event['venueName'] as String? ?? '';
    final buyerName = ticket['buyerName'] as String? ?? '';
    if (!mounted) return;
    Share.share(
      _buildTransferShareMessage(
        eventTitle: eventTitle,
        recipientName: buyerName,
        startAt: startAt,
        venueName: venueName,
        url: url,
      ),
      subject: '🎫 티켓이 도착했어요!',
    );
  }

  Future<void> _captureAndShare({
    required String eventTitle,
    required String? imageUrl,
    required DateTime? startAt,
    required String venueName,
    required String holderName,
    required String buyerName,
    required String? recipientName,
    required String seatGrade,
    required int entryNumber,
    required _TicketStateInfo stateInfo,
  }) async {
    OverlayEntry? overlayEntry;

    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          await precacheImage(NetworkImage(imageUrl), context);
        } catch (_) {
          // 이미지 캐시 실패 시 플레이스홀더로 계속 진행
        }
      }
      if (!mounted) return;

      final overlay = Overlay.of(context, rootOverlay: true);
      overlayEntry = OverlayEntry(
        builder: (context) => IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Opacity(
                opacity: 0.01,
                child: RepaintBoundary(
                  key: _sharePosterKey,
                  child: _SharePosterImage(
                    eventTitle: eventTitle,
                    imageUrl: imageUrl,
                    startAt: startAt,
                    venueName: venueName,
                    holderName: holderName,
                    buyerName: buyerName,
                    recipientName: recipientName,
                    seatGrade: seatGrade,
                    entryNumber: entryNumber,
                    stateInfo: stateInfo,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(overlayEntry);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          _sharePosterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: 'smart_ticket_story.png',
        ),
      ], subject: '$eventTitle 공유 이미지');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '이미지 저장에 실패했습니다',
              style: AppTheme.nanum(fontSize: 13, color: _cream),
            ),
            backgroundColor: _burgundy,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      overlayEntry?.remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final ticket = data['ticket'] as Map<String, dynamic>? ?? {};
    final event = data['event'] as Map<String, dynamic>? ?? {};

    final buyerName = ticket['buyerName'] as String? ?? '';
    final buyerPhone = ticket['buyerPhone'] as String?;
    final naverOrderId = ticket['naverOrderId'] as String?;
    final buyerPhoneMasked = _maskPhoneNumber(buyerPhone);
    final recipientName = ticket['recipientName'] as String?;
    final seatGrade = ticket['seatGrade'] as String? ?? '';
    final seatInfo = ticket['seatInfo'] as String?;
    final entryNumber = ticket['entryNumber'] as int? ?? 0;
    final status = _normalizeTicketStatus(ticket['status'] as String?);
    final ticketId = ticket['id'] as String? ?? '';
    final qrVersion = ticket['qrVersion'] as int? ?? 1;
    final orderIndex = ticket['orderIndex'] as int? ?? 1;
    final totalInOrder = ticket['totalInOrder'] as int? ?? 1;
    final isCheckedIn = ticket['isCheckedIn'] == true;
    final isIntermissionCheckedIn = ticket['isIntermissionCheckedIn'] == true;
    final lastCheckInStage = ticket['lastCheckInStage'] as String?;

    final eventTitle = event['title'] as String? ?? '공연';
    final imageUrl = event['imageUrl'] as String?;
    final naverProductUrl = event['naverProductUrl'] as String?;
    final pamphletUrls =
        (event['pamphletUrls'] as List?)?.cast<String>() ?? <String>[];
    final venueName = event['venueName'] as String? ?? '';
    final venueAddress = event['venueAddress'] as String? ?? '';
    final eventStatus = event['eventStatus'] as String? ?? 'active';
    final startAt = _parseEventDateTime(event['startAt']);
    final revealAt =
        _parseEventDateTime(event['revealAt']) ??
        startAt?.subtract(_defaultRevealLeadTime);
    final gradeCol = _gradeColor(seatGrade);
    final ticketUrl = '$_ticketBaseUrl${widget.accessToken}';

    final now = DateTime.now();
    final qrRevealed = revealAt != null && !now.isBefore(revealAt);
    final stateInfo = _resolveTicketState(
      status: status,
      isCheckedIn: isCheckedIn,
      isRevealed: qrRevealed,
      isIntermissionCheckedIn: isIntermissionCheckedIn,
      eventStatus: eventStatus,
    );
    final isCancelled = stateInfo.code == 'cancelled';
    final isUsed = stateInfo.code == 'used' || stateInfo.code == 'eventCompleted';
    final shareMessage = _buildTicketShareMessage(
      eventTitle: eventTitle,
      startAt: startAt,
      venueName: venueName,
      url: ticketUrl,
    );
    final holderName = recipientName != null && recipientName.isNotEmpty
        ? recipientName
        : buyerName;
    final inviteUrl = naverProductUrl?.trim();
    final hasInviteUrl = inviteUrl != null && inviteUrl.isNotEmpty;
    final actionButtons = <Widget>[
      Expanded(
        child: _ActionButton(
          icon: Icons.link_rounded,
          label: '링크 복사',
          onTap: () {
            Clipboard.setData(ClipboardData(text: ticketUrl));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '티켓 링크가 복사되었습니다',
                  style: AppTheme.nanum(fontSize: 13, color: _cream),
                ),
                backgroundColor: _burgundy,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ),
      Expanded(
        child: _ActionButton(
          icon: Icons.share_rounded,
          label: '티켓 공유',
          onTap: () => Share.share(shareMessage, subject: '$eventTitle 모바일 티켓'),
        ),
      ),
      if (hasInviteUrl)
        Expanded(
          child: _ActionButton(
            icon: Icons.group_add_rounded,
            label: '친구 초대',
            onTap: () => Share.share(
              _buildInviteShareMessage(
                eventTitle: eventTitle,
                startAt: startAt,
                venueName: venueName,
                url: inviteUrl,
              ),
              subject: '$eventTitle 공연 초대',
            ),
          ),
        ),
      Expanded(
        child: _ActionButton(
          icon: Icons.camera_alt_rounded,
          label: '이미지 저장',
          onTap: () => _captureAndShare(
            eventTitle: eventTitle,
            imageUrl: imageUrl,
            startAt: startAt,
            venueName: venueName,
            holderName: holderName,
            buyerName: buyerName,
            recipientName: recipientName,
            seatGrade: seatGrade,
            entryNumber: orderIndex,
            stateInfo: stateInfo,
          ),
        ),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_cream, const Color(0xFFF6F0EB), const Color(0xFFEEE5DE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          children: [
            if (widget.onRefresh != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => widget.onRefresh!.call(),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: AppTheme.gold,
                  ),
                  label: Text(
                    '상태 새로고침',
                    style: AppTheme.nanum(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.gold,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),

            // ══════════════════════════════════════════
            // ── 메인 카드 (플립 애니메이션) ──
            // ══════════════════════════════════════════
            RepaintBoundary(
              key: _cardKey,
              child: AnimatedBuilder(
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
                            buyerPhoneMasked: buyerPhoneMasked,
                            recipientName: recipientName,
                            seatGrade: seatGrade,
                            startAt: startAt,
                            revealAt: revealAt,
                            venueName: venueName,
                            venueAddress: venueAddress,
                            gradeCol: gradeCol,
                            stateInfo: stateInfo,
                            isCancelled: isCancelled,
                            isUsed: isUsed,
                            qrRevealed: qrRevealed,
                            orderIndex: orderIndex,
                            totalInOrder: totalInOrder,
                            entryNumber: entryNumber,
                            onQrTap: _flipToQr,
                            onDoubleTap: _flipToQr,
                          )
                        : Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..rotateY(math.pi),
                            child: _BackCard(
                              eventTitle: eventTitle,
                              venueName: venueName,
                              buyerName: buyerName,
                              buyerPhoneMasked: buyerPhoneMasked,
                              recipientName: recipientName,
                              naverOrderId: naverOrderId,
                              seatGrade: seatGrade,
                              seatInfo: seatInfo,
                              entryNumber: entryNumber,
                              orderIndex: orderIndex,
                              startAt: startAt,
                              revealAt: revealAt,
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
            ),

            const SizedBox(height: 20),

            // ══════════════════════════════════════════
            // ── 라이브 상태: 스탬프 + 인터미션 + 리뷰 ──
            // ══════════════════════════════════════════
            if (isCheckedIn || isIntermissionCheckedIn || stateInfo.code == 'eventCompleted')
              _LiveStatusSection(
                stateCode: stateInfo.code,
                isCheckedIn: isCheckedIn,
                isIntermissionCheckedIn: isIntermissionCheckedIn,
                ticketId: ticketId,
                accessToken: widget.accessToken,
                qrVersion: qrVersion,
                qrRevealed: qrRevealed,
                isCancelled: isCancelled,
                naverProductUrl: naverProductUrl,
              ),

            // ── 그룹 티켓: 이 티켓 전달하기 버튼 ──
            if (widget.isGroupTicket)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _showTransferDialog(
                      context,
                      eventTitle: eventTitle,
                      accessToken: widget.accessToken,
                    ),
                    icon: const Icon(
                      Icons.send_rounded,
                      size: 18,
                      color: AppTheme.gold,
                    ),
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
                        color: AppTheme.gold.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),

            // ── 액션 버튼 (카드 밖) ──
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _burgundy.withValues(alpha: 0.10)),
                boxShadow: [
                  BoxShadow(
                    color: _burgundy.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < actionButtons.length; i++) ...[
                    actionButtons[i],
                    if (i < actionButtons.length - 1)
                      Container(
                        width: 1,
                        height: 36,
                        color: _burgundy.withValues(alpha: 0.08),
                      ),
                  ],
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
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _naverGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // ── 안내 텍스트 ──
            Text(
              '이 티켓은 공연 당일 입장 시 QR코드를 스캔하여 확인합니다.\n'
              '인터미션은 티켓 화면 확인이 기본이며 재입장 처리 시에만 QR을 사용합니다.\n'
              'QR코드는 보안을 위해 2분마다 자동 갱신됩니다.',
              textAlign: TextAlign.center,
              style: AppTheme.nanum(
                fontSize: 11,
                color: _burgundy.withValues(alpha: 0.64),
                height: 1.6,
                noShadow: true,
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
  final VoidCallback? onBackToOverview;

  const _GroupTicketHeader({
    required this.current,
    required this.total,
    this.onBackToOverview,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _burgundy.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: _burgundy.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            if (onBackToOverview != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onBackToOverview,
                  icon: const Icon(
                    Icons.grid_view_rounded,
                    size: 16,
                    color: _burgundy,
                  ),
                  label: Text(
                    '전체 티켓',
                    style: AppTheme.nanum(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _burgundy,
                      noShadow: true,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _burgundy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${current + 1}',
                  style: AppTheme.nanum(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _burgundy,
                    noShadow: true,
                  ),
                ),
                Text(
                  ' / $total',
                  style: AppTheme.nanum(
                    fontSize: 13,
                    color: _burgundy.withValues(alpha: 0.45),
                    noShadow: true,
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  children: List.generate(
                    total,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: i == current ? 20 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i == current
                            ? _burgundy
                            : _burgundy.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ── 그룹 티켓 메인 화면 ──
// ══════════════════════════════════════════════════════════

class _GroupTicketOverview extends StatelessWidget {
  final String eventTitle;
  final String? imageUrl;
  final String venueName;
  final DateTime? startAt;
  final List<Map<String, dynamic>> siblings;
  final bool isRevealed;
  final Future<void> Function()? onRefresh;
  final ValueChanged<int> onOpenTicket;
  final Future<void> Function(String accessToken) onTransferTicket;

  const _GroupTicketOverview({
    required this.eventTitle,
    this.imageUrl,
    required this.venueName,
    this.startAt,
    required this.siblings,
    required this.isRevealed,
    this.onRefresh,
    required this.onOpenTicket,
    required this.onTransferTicket,
  });

  @override
  Widget build(BuildContext context) {
    final revealLabel = isRevealed ? '좌석·QR 공개됨' : '공연 2시간 전 공개';

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _cream.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _cream.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '그룹 티켓',
                  style: AppTheme.nanum(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _cream,
                    letterSpacing: 1.6,
                    noShadow: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _burgundy.withValues(alpha: 0.10)),
                boxShadow: [
                  BoxShadow(
                    color: _burgundy.withValues(alpha: 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 110,
                      height: 150,
                      color: _creamDark,
                      child: imageUrl != null && imageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.music_note_rounded,
                                color: _burgundy,
                                size: 28,
                              ),
                            )
                          : const Icon(
                              Icons.music_note_rounded,
                              color: _burgundy,
                              size: 28,
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 150,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              eventTitle,
                              style: AppTheme.nanum(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: _burgundy,
                                noShadow: true,
                              ),
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (startAt != null)
                            Text(
                              DateFormat(
                                'yyyy.MM.dd (E) HH:mm',
                                'ko_KR',
                              ).format(startAt!),
                              style: AppTheme.nanum(
                                fontSize: 13,
                                color: _burgundy.withValues(alpha: 0.78),
                                noShadow: true,
                              ),
                            ),
                          if (venueName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              venueName,
                              style: AppTheme.nanum(
                                fontSize: 13,
                                color: _burgundy.withValues(alpha: 0.78),
                                noShadow: true,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _OverviewMetaChip(
                                icon: Icons.confirmation_number_outlined,
                                label: '${siblings.length}매',
                              ),
                              _OverviewMetaChip(
                                icon: isRevealed
                                    ? Icons.qr_code_2_rounded
                                    : Icons.lock_clock_rounded,
                                label: revealLabel,
                                accent: isRevealed ? AppTheme.gold : null,
                                showLive: isRevealed,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '전체 티켓',
              style: AppTheme.nanum(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _cream,
                letterSpacing: 0.4,
                noShadow: true,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '탭해서 QR · 좌석을 확인하세요',
              style: AppTheme.nanum(
                fontSize: 12,
                color: _cream.withValues(alpha: 0.55),
                noShadow: true,
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(siblings.length, (index) {
              final sibling = siblings[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == siblings.length - 1 ? 0 : 12,
                ),
                child: _GroupTicketSummaryCard(
                  index: index,
                  sibling: sibling,
                  isRevealed: isRevealed,
                  onOpenTicket: () => onOpenTicket(index),
                  onTransferTicket: () =>
                      onTransferTicket(sibling['accessToken'] as String? ?? ''),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _GroupTicketSummaryCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> sibling;
  final bool isRevealed;
  final VoidCallback onOpenTicket;
  final Future<void> Function() onTransferTicket;

  const _GroupTicketSummaryCard({
    required this.index,
    required this.sibling,
    required this.isRevealed,
    required this.onOpenTicket,
    required this.onTransferTicket,
  });

  @override
  Widget build(BuildContext context) {
    final status = _normalizeTicketStatus(sibling['status'] as String?);
    final isCheckedIn = sibling['isCheckedIn'] == true;
    final isIntermissionCheckedIn = sibling['isIntermissionCheckedIn'] == true;
    final stateInfo = _resolveTicketState(
      status: status,
      isCheckedIn: isCheckedIn,
      isRevealed: isRevealed,
      isIntermissionCheckedIn: isIntermissionCheckedIn,
    );
    final recipientName = sibling['recipientName'] as String?;
    final buyerName = sibling['buyerName'] as String? ?? '예매자';
    final displayName = recipientName != null && recipientName.isNotEmpty
        ? recipientName
        : buyerName;
    final seatGrade = sibling['seatGrade'] as String? ?? '';
    final seatInfo = sibling['seatInfo'] as String?;
    final entryNumber = sibling['entryNumber'] as int? ?? index + 1;
    final sibOrderIndex = sibling['orderIndex'] as int? ?? index + 1;
    final accessToken = sibling['accessToken'] as String? ?? '';
    final canTransfer =
        accessToken.isNotEmpty && status == 'active' && !isCheckedIn;
    final seatLabel = isRevealed
        ? (seatInfo != null && seatInfo.isNotEmpty
              ? seatInfo
              : seatGrade.isNotEmpty
              ? '$seatGrade석 · #$sibOrderIndex'
              : '#$sibOrderIndex')
        : '공연 시작 2시간 전에 좌석 공개';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _burgundy.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: _burgundy.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _burgundy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: AppTheme.nanum(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _burgundy,
                    noShadow: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: AppTheme.nanum(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: _burgundy,
                                  noShadow: true,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                recipientName != null && recipientName.isNotEmpty
                                    ? '수령인'
                                    : '예매자',
                                style: AppTheme.nanum(
                                  fontSize: 11,
                                  color: _burgundy.withValues(alpha: 0.42),
                                  noShadow: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: stateInfo.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: stateInfo.color.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Text(
                            stateInfo.label,
                            style: AppTheme.nanum(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: stateInfo.color,
                              noShadow: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _creamDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _burgundy.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (seatGrade.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _gradeColor(seatGrade).withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$seatGrade석',
                          style: AppTheme.nanum(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _gradeColor(seatGrade),
                            noShadow: true,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _burgundy,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$sibOrderIndex',
                        style: AppTheme.nanum(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _cream,
                          noShadow: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  seatLabel,
                  style: AppTheme.nanum(
                    fontSize: isRevealed ? 14 : 13,
                    fontWeight: isRevealed ? FontWeight.w800 : FontWeight.w600,
                    color: isRevealed
                        ? _burgundy
                        : _burgundy.withValues(alpha: 0.82),
                    noShadow: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canTransfer
                      ? () async {
                          await onTransferTicket();
                        }
                      : null,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: Text(
                    '전달하기',
                    style: AppTheme.nanum(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      noShadow: true,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _burgundy,
                    backgroundColor: Colors.white.withValues(alpha: 0.86),
                    side: BorderSide(
                      color: canTransfer
                          ? _burgundy.withValues(alpha: 0.32)
                          : _burgundy.withValues(alpha: 0.14),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onOpenTicket,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(
                    '티켓 보기',
                    style: AppTheme.nanum(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _cream,
                      noShadow: true,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _burgundy,
                    foregroundColor: _cream,
                    elevation: 2,
                    shadowColor: _burgundy.withValues(alpha: 0.20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewMetaChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color? accent;
  final bool showLive;

  const _OverviewMetaChip({
    required this.icon,
    required this.label,
    this.accent,
    this.showLive = false,
  });

  @override
  State<_OverviewMetaChip> createState() => _OverviewMetaChipState();
}

class _OverviewMetaChipState extends State<_OverviewMetaChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnim = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    if (widget.showLive) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _OverviewMetaChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showLive && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.showLive && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accent ?? _burgundy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: widget.accent == null ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showLive) ...[
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: const Color(0xFF4ADE80).withValues(alpha: _pulseAnim.value),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4ADE80).withValues(alpha: _pulseAnim.value * 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Icon(widget.icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: AppTheme.nanum(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              noShadow: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _FrontIdentityChip extends StatelessWidget {
  final String label;
  final Color accentColor;

  const _FrontIdentityChip({required this.label, this.accentColor = _burgundy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accentColor.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: AppTheme.nanum(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: accentColor,
          noShadow: true,
        ),
      ),
    );
  }
}

class _SharePosterImage extends StatelessWidget {
  final String eventTitle;
  final String? imageUrl;
  final DateTime? startAt;
  final String venueName;
  final String holderName;
  final String buyerName;
  final String? recipientName;
  final String seatGrade;
  final int entryNumber;
  final _TicketStateInfo stateInfo;

  const _SharePosterImage({
    required this.eventTitle,
    this.imageUrl,
    this.startAt,
    required this.venueName,
    required this.holderName,
    required this.buyerName,
    this.recipientName,
    required this.seatGrade,
    required this.entryNumber,
    required this.stateInfo,
  });

  @override
  Widget build(BuildContext context) {
    final hasRecipient = recipientName != null && recipientName!.isNotEmpty;
    final schedule = _formatShareSchedule(startAt, venueName);
    final holderLabel = hasRecipient ? '받는 사람' : '예매자';
    final ownerText = hasRecipient ? '예매자 $buyerName' : '모바일 스마트 티켓';

    return SizedBox(
      width: 360,
      height: 450,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_burgundyDeep, _burgundy, Color(0xFF5E1820)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -40,
              right: -24,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.gold.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -20,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '멜론티켓',
                          style: AppTheme.nanum(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _cream,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _SharePosterStatusChip(stateInfo: stateInfo),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _cream,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 30,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                            child: Container(
                              height: 208,
                              width: double.infinity,
                              color: _creamDark,
                              child: imageUrl != null && imageUrl!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: imageUrl!,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          const _SharePosterPlaceholder(),
                                    )
                                  : const _SharePosterPlaceholder(),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                18,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _FrontIdentityChip(label: holderLabel),
                                      const SizedBox(width: 8),
                                      if (seatGrade.isNotEmpty)
                                        _ShareMetaPill(
                                          label: '$seatGrade석',
                                          backgroundColor: _gradeColor(
                                            seatGrade,
                                          ).withValues(alpha: 0.12),
                                          foregroundColor: _gradeColor(
                                            seatGrade,
                                          ),
                                        ),
                                      const Spacer(),
                                      Text(
                                        '티켓 #$entryNumber',
                                        style: AppTheme.nanum(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: _textMid,
                                          noShadow: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    holderName,
                                    style: AppTheme.serif(
                                      fontSize: 30,
                                      color: _burgundy,
                                      height: 0.95,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    ownerText,
                                    style: AppTheme.nanum(
                                      fontSize: 11,
                                      color: _textMid,
                                      noShadow: true,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    eventTitle,
                                    style: AppTheme.nanum(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: _textDark,
                                      noShadow: true,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                  if (schedule.isNotEmpty)
                                    _ShareInfoLine(
                                      icon: Icons.calendar_month_rounded,
                                      text: schedule,
                                    ),
                                  if (venueName.trim().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: _ShareInfoLine(
                                        icon: Icons.place_rounded,
                                        text: venueName.trim(),
                                      ),
                                    ),
                                  const Spacer(),
                                  Text(
                                    '멜론티켓 · 공유용 이미지',
                                    style: AppTheme.nanum(
                                      fontSize: 11,
                                      color: _textMid,
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharePosterStatusChip extends StatelessWidget {
  final _TicketStateInfo stateInfo;

  const _SharePosterStatusChip({required this.stateInfo});

  @override
  Widget build(BuildContext context) {
    final color = stateInfo.color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        stateInfo.label,
        style: AppTheme.nanum(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ShareMetaPill extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _ShareMetaPill({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.nanum(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
          noShadow: true,
        ),
      ),
    );
  }
}

class _ShareInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ShareInfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: _textMid),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTheme.nanum(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _textDark,
              noShadow: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _SharePosterPlaceholder extends StatelessWidget {
  const _SharePosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_burgundy, _burgundyDeep],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: _cream, size: 42),
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
  final String? buyerPhoneMasked;
  final String? recipientName;
  final String seatGrade;
  final DateTime? startAt;
  final DateTime? revealAt;
  final String venueName;
  final String venueAddress;
  final Color gradeCol;
  final _TicketStateInfo stateInfo;
  final bool isCancelled;
  final bool isUsed;
  final bool qrRevealed;
  final int orderIndex;
  final int totalInOrder;
  final int entryNumber;
  final VoidCallback onQrTap;
  final VoidCallback? onDoubleTap;

  const _FrontCard({
    required this.eventTitle,
    this.imageUrl,
    this.naverProductUrl,
    required this.buyerName,
    this.buyerPhoneMasked,
    this.recipientName,
    required this.seatGrade,
    this.startAt,
    this.revealAt,
    required this.venueName,
    required this.venueAddress,
    required this.gradeCol,
    required this.stateInfo,
    required this.isCancelled,
    required this.isUsed,
    required this.qrRevealed,
    required this.orderIndex,
    required this.totalInOrder,
    required this.entryNumber,
    required this.onQrTap,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasRecipient = recipientName != null && recipientName!.isNotEmpty;
    final holderName = hasRecipient ? recipientName! : buyerName;
    final ownerDescription = hasRecipient
        ? buyerPhoneMasked != null
              ? '예매자 $buyerName · $buyerPhoneMasked'
              : '예매자 $buyerName'
        : '이름을 등록하면 전달용 티켓으로 보낼 수 있습니다';

    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Stack(
        children: [
          ClipPath(
            clipper: const _BoardingPassClipper(
              notchRadius: 20,
              notchPosition: 0.58,
            ),
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
                  _SmartTicketHeader(stateInfo: stateInfo, gradeCol: gradeCol),

                  // ── 포스터 풀사이즈 + QR 오버랩 ──
                  _PosterWithQr(
                    imageUrl: imageUrl,
                    naverProductUrl: naverProductUrl,
                    qrRevealed: qrRevealed,
                    isCancelled: isCancelled,
                    isUsed: isUsed,
                    onQrTap: onQrTap,
                  ),

                  // ── 보딩패스 정보 섹션 ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 공연명 (대형, 한 줄 — 길면 자동 축소)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            eventTitle,
                            style: AppTheme.nanum(
                              color: _textDark,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                              height: 1.25,
                              noShadow: true,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Row 1: 예매자 | No. | 등급 ──
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // 예매자 이름 (대형)
                            Expanded(
                              flex: 5,
                              child: _InfoField(
                                label: 'Holder  ·  예매자',
                                child: Text(
                                  holderName,
                                  style: AppTheme.serif(
                                    fontSize: 28,
                                    color: _burgundy,
                                    height: 1.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            // No.
                            Expanded(
                              flex: 2,
                              child: _InfoFieldCentered(
                                label: 'No.',
                                child: Text(
                                  '#$orderIndex',
                                  style: AppTheme.nanum(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: _burgundy,
                                    noShadow: true,
                                  ),
                                ),
                              ),
                            ),
                            // 등급
                            Expanded(
                              flex: 3,
                              child: _InfoFieldCentered(
                                label: 'Grade  ·  등급',
                                child: Text(
                                  '${seatGrade}석',
                                  style: AppTheme.nanum(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: gradeCol,
                                    noShadow: true,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // ── Row 2: 공연장 | 공연 일시 ──
                        // Date를 No.~등급 사이 위치에 정렬 (flex 5:5 = 예매자 영역 | 나머지)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _InfoField(
                                label: 'Venue  ·  공연장',
                                value: venueName,
                                shrinkToFit: true,
                                onTap: venueName.isNotEmpty
                                    ? () {
                                        final query = venueAddress.isNotEmpty
                                            ? venueAddress
                                            : venueName;
                                        launchUrl(
                                          Uri.parse(
                                            'https://map.kakao.com/link/search/$query',
                                          ),
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                    : null,
                              ),
                            ),
                            Expanded(
                              flex: 5,
                              child: _InfoFieldCentered(
                                label: 'Date  ·  공연 일시',
                                value: startAt != null
                                    ? DateFormat(
                                        'MM.dd (E) HH:mm',
                                        'ko_KR',
                                      ).format(startAt!)
                                    : '-',
                              ),
                            ),
                          ],
                        ),
                        if (venueAddress.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              venueAddress,
                              style: AppTheme.nanum(
                                fontSize: 12,
                                color: _textMid,
                                noShadow: true,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ── 노치 구분선 영역 ──
                  // (ClipPath 노치와 정렬되는 위치)

                  // ── 구분선 (골드 다이아몬드) ──
                  _GoldDivider(),

                  const SizedBox(height: 14),

                  // ── 하단: 상태 라이브 + 러닝타임 + 인터미션 (가운데 정렬) ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _InfoFieldCentered(
                            label: 'LIVE · 좌석공개',
                            child: _LiveStatusInCard(
                              startAt: startAt,
                              revealAt: revealAt,
                              isCancelled: isCancelled,
                              isUsed: isUsed,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: _InfoFieldCentered(
                            label: 'Runtime',
                            value: '130분',
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: _InfoFieldCentered(
                            label: 'Break',
                            value: '15분',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── 하단 띠: 두 번 탭하여 QR 보기 ──
                  GestureDetector(
                    onDoubleTap: onDoubleTap,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1A0508),
                            _burgundy,
                            const Color(0xFF1A0508),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            size: 14,
                            color: _cream.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '두 번 탭하여 QR 보기',
                            style: AppTheme.nanum(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _cream.withValues(alpha: 0.7),
                              letterSpacing: 0.5,
                              noShadow: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
          // 노치 inner shadow (구멍 깊이감)
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final notchY = constraints.maxHeight * 0.58;
                  const nr = 20.0;
                  return Stack(
                    children: [
                      // 왼쪽 노치 — 그림자로 깊이감
                      Positioned(
                        left: -nr + 2,
                        top: notchY - nr,
                        child: Container(
                          width: nr * 2,
                          height: nr * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.transparent,
                                _burgundy.withValues(alpha: 0.06),
                                _burgundy.withValues(alpha: 0.15),
                              ],
                              stops: const [0.0, 0.7, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // 오른쪽 노치 — 그림자로 깊이감
                      Positioned(
                        right: -nr + 2,
                        top: notchY - nr,
                        child: Container(
                          width: nr * 2,
                          height: nr * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.transparent,
                                _burgundy.withValues(alpha: 0.06),
                                _burgundy.withValues(alpha: 0.15),
                              ],
                              stops: const [0.0, 0.7, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
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
  final String? buyerPhoneMasked;
  final String? recipientName;
  final String? naverOrderId;
  final String seatGrade;
  final String? seatInfo;
  final int entryNumber;
  final int orderIndex;
  final DateTime? startAt;
  final DateTime? revealAt;
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
    this.buyerPhoneMasked,
    this.recipientName,
    this.naverOrderId,
    this.seatGrade = '',
    this.seatInfo,
    required this.entryNumber,
    required this.orderIndex,
    this.startAt,
    this.revealAt,
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

class _BackCardState extends State<_BackCard>
    with SingleTickerProviderStateMixin {
  bool _localQrRevealed = false;
  late final AnimationController _refreshCtrl;

  @override
  void initState() {
    super.initState();
    _localQrRevealed = widget.qrRevealed;
    _refreshCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _refreshCtrl.dispose();
    super.dispose();
  }

  void _handleRefresh() {
    // 회전 애니메이션
    _refreshCtrl.forward(from: 0);
    // QR 공개 여부 재확인
    if (widget.revealAt != null) {
      final now = DateTime.now();
      final revealed = !now.isBefore(widget.revealAt!);
      setState(() => _localQrRevealed = revealed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onBack,
      child: ClipPath(
        clipper: const _BoardingPassClipper(
          notchRadius: 16,
          notchPosition: 0.55,
        ),
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
                    child: Icon(
                      Icons.confirmation_number_rounded,
                      size: 28,
                      color: _burgundy,
                    ),
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
                  const SizedBox(height: 8),

                  // ── QR 코드 영역 ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child:
                        _localQrRevealed &&
                            !widget.isCancelled &&
                            !widget.isUsed
                        ? _QrSection(
                            ticketId: widget.ticketId,
                            accessToken: widget.accessToken,
                            qrVersion: widget.qrVersion,
                          )
                        : _QrPlaceholderBack(
                            revealAt: widget.revealAt,
                            isCancelled: widget.isCancelled,
                            isUsed: widget.isUsed,
                            onRefresh: _handleRefresh,
                            refreshAnimation: _refreshCtrl,
                          ),
                  ),

                  // ── 입장번호 백업 (QR 리더 고장 시) ──
                  if (_localQrRevealed && widget.entryNumber > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2A2A35), width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.confirmation_number_rounded, size: 14, color: Color(0xFF8A8A9A)),
                            const SizedBox(width: 6),
                            Text(
                              '입장번호',
                              style: AppTheme.nanum(
                                fontSize: 11,
                                color: const Color(0xFF8A8A9A),
                                noShadow: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${widget.seatGrade}-${widget.entryNumber.toString().padLeft(3, '0')}',
                              style: AppTheme.nanum(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFC9A84C),
                                letterSpacing: 1.5,
                                noShadow: true,
                              ),
                            ),
                          ],
                        ),
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
                          Icon(
                            Icons.auto_stories_rounded,
                            size: 14,
                            color: _textMid,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '프로그램',
                            style: AppTheme.nanum(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _textMid,
                              noShadow: true,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${widget.pamphletUrls.length}장',
                            style: AppTheme.nanum(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _textLight,
                              noShadow: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 160,
                      child: _PamphletGallery(urls: widget.pamphletUrls),
                    ),
                    const SizedBox(height: 8),
                  ],

                  const SizedBox(height: 20),

                  // ── 하단 정보 ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.eventTitle,
                            style: AppTheme.nanum(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _textDark,
                              noShadow: true,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.venueName,
                          style: AppTheme.nanum(
                            fontSize: 13,
                            color: _textMid,
                            noShadow: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _creamDark,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '본인 확인 정보',
                                style: AppTheme.nanum(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _textMid,
                                  noShadow: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _InfoField(
                                      label: '예매자',
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.buyerName,
                                            style: AppTheme.serif(
                                              fontSize: 18,
                                              color: _textDark,
                                            ),
                                          ),
                                          if (widget.buyerPhoneMasked != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 2,
                                              ),
                                              child: Text(
                                                widget.buyerPhoneMasked!,
                                                style: AppTheme.nanum(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: _textMid,
                                                  noShadow: true,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _InfoField(
                                      label: '좌석등급',
                                      value: widget.seatGrade.isNotEmpty
                                          ? '${widget.seatGrade}석'
                                          : '-',
                                      valueStyle: AppTheme.serif(
                                        fontSize: 18,
                                        color: _textDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _InfoField(
                                      label: '예매번호',
                                      value:
                                          widget.naverOrderId != null &&
                                              widget.naverOrderId!.isNotEmpty
                                          ? widget.naverOrderId!
                                          : '-',
                                      valueStyle: AppTheme.nanum(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _textMid,
                                        noShadow: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _InfoField(
                                      label: '티켓번호',
                                      value: '#${widget.orderIndex}',
                                      valueStyle: AppTheme.nanum(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: _textDark,
                                        noShadow: true,
                                      ),
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
                          text: '공연 시작 2시간 전에 좌석과 QR 코드가 공개됩니다',
                        ),
                        const SizedBox(height: 6),
                        _NoteRow(
                          icon: Icons.refresh_rounded,
                          text: 'QR 코드는 2분마다 자동 갱신됩니다',
                        ),
                        const SizedBox(height: 6),
                        _NoteRow(
                          icon: Icons.visibility_rounded,
                          text: '인터미션은 티켓 화면 확인 중심이며 재입장 시에만 QR을 사용합니다',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── 돌아가기 안내 ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.touch_app_rounded,
                        size: 14,
                        color: _textLight,
                      ),
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
  final _TicketStateInfo stateInfo;
  final Color gradeCol;

  const _SmartTicketHeader({required this.stateInfo, required this.gradeCol});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_burgundy, const Color(0xFF2A0A0E), const Color(0xFF1A0508)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.confirmation_number_rounded,
            size: 14,
            color: _ticketAccent,
          ),
          const SizedBox(width: 8),
          Text(
            '스마트 티켓',
            style: AppTheme.nanum(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _cream,
              letterSpacing: 1.2,
              noShadow: true,
            ),
          ),
          const Spacer(),
          _StatusBadge(stateInfo: stateInfo),
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
        // 포스터 이미지 (전체 보이도록)
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 200),
          color: _creamDark,
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.fitWidth,
                  width: double.infinity,
                  placeholder: (_, __) => const SizedBox(
                    height: 280,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _burgundy,
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => const SizedBox(
                    height: 280,
                    child: Center(
                      child: Icon(
                        Icons.music_note_rounded,
                        color: _textLight,
                        size: 40,
                      ),
                    ),
                  ),
                )
              : const SizedBox(
                  height: 280,
                  child: Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      color: _textLight,
                      size: 40,
                    ),
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
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.lock_rounded,
                            size: 16,
                            color: _textMid,
                          ),
                        ),
                      ),
                    if (isCancelled)
                      Icon(
                        Icons.cancel_rounded,
                        size: 28,
                        color: const Color(0xFFFF5A5F),
                      ),
                    if (isUsed)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 28,
                        color: const Color(0xFF22C55E),
                      ),
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

enum _LiveTicketState { beforeReveal, beforeStart, playing, ended }

// ── 카드 내부 LIVE 카운트다운 (크림 배경용) ──
class _LiveStatusInCard extends StatefulWidget {
  final DateTime? startAt;
  final DateTime? revealAt;
  final bool isCancelled;
  final bool isUsed;

  const _LiveStatusInCard({
    this.startAt,
    this.revealAt,
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
  final _remaining = ValueNotifier<Duration>(Duration.zero);
  final _status = ValueNotifier<_LiveTicketState>(_LiveTicketState.beforeReveal);

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
    final revealAt = widget.revealAt;
    final endAt = widget.startAt!.add(const Duration(hours: 2, minutes: 10));

    if (revealAt != null && now.isBefore(revealAt)) {
      _remaining.value = revealAt.difference(now);
      _status.value = _LiveTicketState.beforeReveal;
    } else if (now.isBefore(widget.startAt!)) {
      _remaining.value = widget.startAt!.difference(now);
      _status.value = _LiveTicketState.beforeStart;
    } else if (now.isBefore(endAt)) {
      _remaining.value = endAt.difference(now);
      _status.value = _LiveTicketState.playing;
    } else {
      _remaining.value = Duration.zero;
      _status.value = _LiveTicketState.ended;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _tickTimer?.cancel();
    _remaining.dispose();
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCancelled) {
      return Text(
        '취소됨',
        style: AppTheme.nanum(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFFF5A5F),
          noShadow: true,
        ),
      );
    }
    if (widget.isUsed) {
      return Text(
        '사용 완료',
        style: AppTheme.nanum(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF22C55E),
          noShadow: true,
        ),
      );
    }

    return ValueListenableBuilder<_LiveTicketState>(
      valueListenable: _status,
      builder: (context, status, _) {
        final Color dotColor;
        switch (status) {
          case _LiveTicketState.beforeReveal:
            dotColor = const Color(0xFF22C55E);
          case _LiveTicketState.beforeStart:
            dotColor = AppTheme.gold;
          case _LiveTicketState.playing:
            dotColor = const Color(0xFFFF4444);
          case _LiveTicketState.ended:
            dotColor = _textLight;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ● dot + D-day (가로)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: status == _LiveTicketState.ended
                          ? dotColor
                          : Color.lerp(
                              dotColor,
                              dotColor.withValues(alpha: 0.2),
                              _pulseCtrl.value,
                            ),
                      boxShadow: status != _LiveTicketState.ended
                          ? [
                              BoxShadow(
                                color: dotColor.withValues(
                                  alpha: 0.6 * (1 - _pulseCtrl.value),
                                ),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
                // D-day
                ValueListenableBuilder<Duration>(
                  valueListenable: _remaining,
                  builder: (_, remaining, __) {
                    final dDay = remaining.inDays > 0 ? 'D-${remaining.inDays}' : '';
                    if (dDay.isEmpty) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 6),
                        Text(
                          dDay,
                          style: AppTheme.nanum(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: _textDark,
                            noShadow: true,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (status == _LiveTicketState.ended) ...[
                  const SizedBox(width: 6),
                  Text(
                    '종료',
                    style: AppTheme.nanum(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _textLight,
                      noShadow: true,
                    ),
                  ),
                ],
              ],
            ),
            // 시간 (아래) — 매초 이 부분만 리빌드
            ValueListenableBuilder<Duration>(
              valueListenable: _remaining,
              builder: (_, remaining, __) {
                if (remaining <= Duration.zero) return const SizedBox.shrink();
                final h = remaining.inHours % 24;
                final m = remaining.inMinutes % 60;
                final s = remaining.inSeconds % 60;
                final hms = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    hms,
                    style: GoogleFonts.robotoMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _textMid,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

// ── 상태 배지 ──
class _StatusBadge extends StatelessWidget {
  final _TicketStateInfo stateInfo;
  const _StatusBadge({required this.stateInfo});

  @override
  Widget build(BuildContext context) {
    final useLightAccent =
        stateInfo.code == 'beforeReveal' || stateInfo.code == 'active';
    final bgColor = useLightAccent
        ? Colors.white.withValues(alpha: 0.10)
        : stateInfo.color.withValues(alpha: 0.14);
    final fgColor = useLightAccent ? _ticketAccent : stateInfo.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        stateInfo.label,
        style: AppTheme.nanum(
          color: fgColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          noShadow: true,
        ),
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
  final bool shrinkToFit;

  const _InfoField({
    required this.label,
    this.value,
    this.child,
    this.valueStyle,
    this.onTap,
    this.shrinkToFit = false,
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
            style: AppTheme.nanum(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _burgundy.withValues(alpha: 0.50),
              letterSpacing: 0.5,
              noShadow: true,
            ),
          ),
          const SizedBox(height: 4),
          if (child != null)
            child!
          else if (shrinkToFit)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value ?? '-',
                style:
                    valueStyle ??
                    AppTheme.nanum(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                      noShadow: true,
                    ),
                maxLines: 1,
              ),
            )
          else
            Text(
              value ?? '-',
              style:
                  valueStyle ??
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

// ── 정보 필드 (칸 안에서 가운데 정렬) ──
class _InfoFieldCentered extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;

  const _InfoFieldCentered({
    required this.label,
    this.value,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppTheme.nanum(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _burgundy.withValues(alpha: 0.50),
            letterSpacing: 0.5,
            noShadow: true,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        if (child != null)
          child!
        else
          Text(
            value ?? '-',
            style: AppTheme.nanum(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _textDark,
              noShadow: true,
            ),
            textAlign: TextAlign.center,
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
                fontSize: 8,
                color: AppTheme.gold.withValues(alpha: 0.5),
              ),
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
              fontSize: 12,
              color: _textMid,
              noShadow: true,
            ),
          ),
        ),
      ],
    );
  }
}

// ── QR 플레이스홀더 (뒷면 - 공개 전) ──
class _QrPlaceholderBack extends StatelessWidget {
  final DateTime? revealAt;
  final bool isCancelled;
  final bool isUsed;
  final VoidCallback? onRefresh;
  final Animation<double>? refreshAnimation;

  const _QrPlaceholderBack({
    this.revealAt,
    required this.isCancelled,
    required this.isUsed,
    this.onRefresh,
    this.refreshAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final message = isCancelled
        ? '취소된 티켓입니다'
        : isUsed
        ? '이미 사용 완료된 티켓입니다'
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
          if (!isCancelled && !isUsed && revealAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '${DateFormat('M월 d일 HH:mm', 'ko_KR').format(revealAt!)} 공개',
              style: AppTheme.nanum(
                fontSize: 12,
                color: _textLight,
                noShadow: true,
              ),
            ),
            const SizedBox(height: 16),
            // 새로고침 버튼
            GestureDetector(
              onTap: onRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (refreshAnimation != null)
                      RotationTransition(
                        turns: refreshAnimation!,
                        child: Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: _textMid,
                        ),
                      )
                    else
                      Icon(Icons.refresh_rounded, size: 16, color: _textMid),
                    const SizedBox(width: 6),
                    Text(
                      '새로고침',
                      style: AppTheme.nanum(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _textMid,
                        noShadow: true,
                      ),
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
  final _remainingSeconds = ValueNotifier<int>(_refreshIntervalSeconds);
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
      _remainingSeconds.value--;
      if (_remainingSeconds.value <= 0) {
        _refreshQrToken();
      }
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
      final secondsLeft = (exp - now).clamp(1, _refreshIntervalSeconds).toInt();

      if (!mounted) return;
      setState(() {
        _qrData = token;
        _isLoading = false;
      });
      _remainingSeconds.value = secondsLeft;
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
    _remainingSeconds.dispose();
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
          child: CircularProgressIndicator(
            color: AppTheme.gold,
            strokeWidth: 2,
          ),
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
                  fontSize: 12,
                  color: _textMid,
                  noShadow: true,
                ),
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
        errorCorrectionLevel: QrErrorCorrectLevel.L,
        size: 220,
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
    return ValueListenableBuilder<int>(
      valueListenable: _remainingSeconds,
      builder: (_, seconds, __) {
        final isLow = seconds <= 30;
        final min = seconds ~/ 60;
        final sec = seconds % 60;
        final timeStr =
            '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isLow ? const Color(0x1AFF9500) : _creamDark,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: isLow ? const Color(0x4DFF9500) : _divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 12,
                color: isLow ? const Color(0xFFFF9500) : _textMid,
              ),
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
      },
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
            Icon(icon, size: 20, color: _burgundy),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.nanum(
                fontSize: 11,
                color: _burgundy.withValues(alpha: 0.84),
                fontWeight: FontWeight.w600,
                noShadow: true,
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
              child: CachedNetworkImage(
                imageUrl: urls[index],
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: _creamDark,
                  child: const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 24,
                      color: _textLight,
                    ),
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
        pageBuilder: (_, __, ___) =>
            _PamphletFullscreen(urls: urls, initialIndex: initialIndex),
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
                      child: CachedNetworkImage(
                        imageUrl: widget.urls[index],
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_current + 1} / ${widget.urls.length}',
                      style: AppTheme.nanum(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        noShadow: true,
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

// ══════════════════════════════════════════════════════════════════
// ── 라이브 상태 섹션: 스탬프 + 인터미션 QR + 리뷰 카드 ──
// ══════════════════════════════════════════════════════════════════

class _LiveStatusSection extends ConsumerStatefulWidget {
  final String stateCode;
  final bool isCheckedIn;
  final bool isIntermissionCheckedIn;
  final String ticketId;
  final String accessToken;
  final int qrVersion;
  final bool qrRevealed;
  final bool isCancelled;
  final String? naverProductUrl;

  const _LiveStatusSection({
    required this.stateCode,
    required this.isCheckedIn,
    required this.isIntermissionCheckedIn,
    required this.ticketId,
    required this.accessToken,
    required this.qrVersion,
    required this.qrRevealed,
    required this.isCancelled,
    this.naverProductUrl,
  });

  @override
  ConsumerState<_LiveStatusSection> createState() => _LiveStatusSectionState();
}

class _LiveStatusSectionState extends ConsumerState<_LiveStatusSection> {
  bool _showIntermissionQr = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          // ── 1부 입장완료 스탬프 ──
          if (widget.isCheckedIn) _buildEntryStamp(),

          // ── 인터미션 완료 스탬프 ──
          if (widget.isIntermissionCheckedIn) ...[
            const SizedBox(height: 8),
            _buildIntermissionStamp(),
          ],

          // ── 인터미션 입장하기 버튼 (1부 완료 + 인터미션 미완료) ──
          if (widget.isCheckedIn &&
              !widget.isIntermissionCheckedIn &&
              widget.stateCode == 'entryCheckedIn') ...[
            const SizedBox(height: 12),
            if (!_showIntermissionQr)
              _buildIntermissionButton()
            else
              _buildIntermissionQrCard(),
          ],

          // ── 공연종료 → 리뷰 카드 ──
          if (widget.stateCode == 'eventCompleted') ...[
            const SizedBox(height: 12),
            _buildReviewCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildEntryStamp() {
    return _RubberStamp(
      label: '1부',
      subLabel: '입장완료',
      color: const Color(0xFFC0392B),
      angle: -0.21,
      message: '공연을 즐겨주세요!',
    );
  }

  Widget _buildIntermissionStamp() {
    return _RubberStamp(
      label: '2부',
      subLabel: '입장완료',
      color: AppTheme.gold,
      angle: 0.15,
      message: '2부 공연을 즐겨주세요!',
    );
  }

  Widget _buildIntermissionButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => setState(() => _showIntermissionQr = true),
        icon: const Icon(Icons.qr_code_2_rounded, size: 22),
        label: Text(
          '인터미션 입장하기',
          style: AppTheme.nanum(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            noShadow: true,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _burgundy,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildIntermissionQrCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _burgundy.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: _burgundy.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '인터미션 입장 QR',
                style: AppTheme.nanum(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _burgundy,
                  noShadow: true,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _showIntermissionQr = false),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _creamDark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 16, color: _textMid),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '스태프에게 이 QR을 보여주세요',
            style: AppTheme.nanum(
              fontSize: 12,
              color: _textMid,
              noShadow: true,
            ),
          ),
          const SizedBox(height: 16),
          _QrSection(
            ticketId: widget.ticketId,
            accessToken: widget.accessToken,
            qrVersion: widget.qrVersion,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard() {
    final hasNaverUrl = widget.naverProductUrl != null && widget.naverProductUrl!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _naverGreen.withValues(alpha: 0.08),
            _naverGreen.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _naverGreen.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.star_rounded,
            color: AppTheme.gold,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            '공연은 어떠셨나요?',
            style: AppTheme.nanum(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _burgundy,
              noShadow: true,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '네이버 스토어에서 리뷰를 남겨주세요',
            style: AppTheme.nanum(
              fontSize: 13,
              color: _textMid,
              noShadow: true,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: hasNaverUrl
                  ? () => launchUrl(
                        Uri.parse(widget.naverProductUrl!),
                        mode: LaunchMode.externalApplication,
                      )
                  : null,
              icon: const Icon(Icons.rate_review_rounded, size: 20),
              label: Text(
                '네이버 리뷰 작성하기',
                style: AppTheme.nanum(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  noShadow: true,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _naverGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _creamDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ── 빈티지 도장 스탬프 위젯 ──
// ══════════════════════════════════════════════════════════════════

class _RubberStamp extends StatelessWidget {
  final String label;
  final String subLabel;
  final Color color;
  final double angle; // radians
  final String message;

  const _RubberStamp({
    required this.label,
    required this.subLabel,
    required this.color,
    required this.angle,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 안내 메시지
        Expanded(
          child: Text(
            message,
            style: AppTheme.nanum(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _textMid,
              noShadow: true,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 도장
        Transform.rotate(
          angle: angle,
          child: CustomPaint(
            painter: _StampPainter(color: color),
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTheme.nanum(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: color.withValues(alpha: 0.85),
                      letterSpacing: 2,
                      noShadow: true,
                    ),
                  ),
                  Text(
                    subLabel,
                    style: AppTheme.nanum(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: color.withValues(alpha: 0.7),
                      letterSpacing: 1,
                      noShadow: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StampPainter extends CustomPainter {
  final Color color;
  const _StampPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - 2;
    final innerR = outerR - 4;

    // 외부 원 (두꺼운 잉크)
    final outerPaint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, outerR, outerPaint);

    // 내부 원 (얇은 선)
    final innerPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, innerR, innerPaint);

    // 잉크 얼룩 효과 (불규칙 점들)
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final rng = [
      Offset(center.dx - 18, center.dy - 22),
      Offset(center.dx + 20, center.dy + 18),
      Offset(center.dx - 25, center.dy + 10),
      Offset(center.dx + 12, center.dy - 26),
      Offset(center.dx + 28, center.dy - 5),
    ];
    for (final p in rng) {
      canvas.drawCircle(p, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StampPainter old) => color != old.color;
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
    path.arcToPoint(Offset(size.width, r), radius: const Radius.circular(r));

    path.lineTo(size.width, notchY - notchRadius);
    path.arcToPoint(
      Offset(size.width, notchY + notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    path.lineTo(size.width, size.height - r);
    path.arcToPoint(
      Offset(size.width - r, size.height),
      radius: const Radius.circular(r),
    );

    path.lineTo(r, size.height);
    path.arcToPoint(
      Offset(0, size.height - r),
      radius: const Radius.circular(r),
    );

    path.lineTo(0, notchY + notchRadius);
    path.arcToPoint(
      Offset(0, notchY - notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

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
