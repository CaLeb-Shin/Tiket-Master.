import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/domain/catalog/event.dart';
import 'package:melon_core/infrastructure/device/offline_checkin_cache.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/services/functions_service.dart';
import 'package:melon_core/services/scanner_device_service.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  final String? inviteToken;
  const ScannerScreen({super.key, this.inviteToken});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  late final MobileScannerController _controller;
  String _checkinStage = 'entry';
  bool _isProcessing = false;
  _ScanResultData? _lastResult;
  Timer? _resultDismissTimer;
  bool _isDeviceLoading = true;
  bool _isDeviceApproved = false;
  bool _isDeviceBlocked = false;
  String? _scannerDeviceId;
  String _scannerDeviceLabel = '';
  String? _deviceStatusMessage;
  bool _cameraStarted = false;

  // ─── 오프라인 캐시 관련 ─────────────────────────────
  bool _isOfflineMode = false;
  String? _selectedEventId;
  String? _selectedEventTitle;
  bool _isCacheDownloading = false;
  int _cachedTicketCount = 0;
  int _pendingSyncCount = 0;
  String? _cacheDownloadedAt;

  bool get _isIntermissionStage => _checkinStage == 'intermission';

  String get _stageHeadline => _isIntermissionStage ? '인터미션 확인' : '1차 입장';

  String get _stageInstruction =>
      _isIntermissionStage ? '재입장 처리 시에만 QR을 스캔하세요' : '입장용 QR을 영역 안에 맞춰주세요';

  String get _stageModeDescription => _isIntermissionStage
      ? '기본은 티켓 화면 확인, 필요 시만 재입장 QR 스캔'
      : 'QR 스캔으로 1차 입장을 처리합니다';

  String _resultTitleForResponse(bool success, Map<String, dynamic> result) {
    final providedTitle = (result['title'] as String?)?.trim();
    if (providedTitle != null && providedTitle.isNotEmpty) {
      return providedTitle;
    }
    if (success) {
      return '입장 확인';
    }

    return switch (result['result'] as String?) {
      'beforeReveal' => '공개 전',
      'cancelled' || 'canceled' => '취소됨',
      'alreadyUsed' => _isIntermissionStage ? '사용 완료' : '입장 완료',
      'missingEntryCheckin' => '1차 입장 필요',
      'notAllowedDevice' => '승인되지 않은 기기',
      'expired' => 'QR 만료',
      'invalidSignature' || 'invalidTicket' => '잘못된 QR',
      _ => '입장 불가',
    };
  }

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: [BarcodeFormat.qrCode],
    );
    unawaited(_registerCurrentDevice());
  }

  @override
  void dispose() {
    _resultDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _registerCurrentDevice({bool silent = false}) async {
    if (!mounted) return;
    setState(() => _isDeviceLoading = true);

    try {
      // Firebase Auth가 아직 로드 안 됐을 수 있으므로 잠시 대기
      var authUser = ref.read(authStateProvider).valueOrNull;
      if (authUser == null) {
        // 최대 3초 대기 (100ms × 30)
        for (int i = 0; i < 30 && authUser == null; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!mounted) return;
          authUser = ref.read(authStateProvider).valueOrNull;
        }
      }
      if (authUser == null) {
        throw const FormatException('스캐너 사용 전 로그인이 필요합니다');
      }

      final scannerDeviceService = ref.read(scannerDeviceServiceProvider);
      final deviceId = await scannerDeviceService.getOrCreateInstallationId();
      final label = scannerDeviceService.defaultLabel();
      final platform = scannerDeviceService.platformName();

      final result = await ref
          .read(functionsServiceProvider)
          .registerScannerDevice(
            deviceId: deviceId,
            label: label,
            platform: platform,
            inviteToken: widget.inviteToken,
          );

      if (!mounted) return;
      final approved = result['approved'] == true;
      final blocked = result['blocked'] == true;
      final message = result['message'] as String?;

      setState(() {
        _scannerDeviceId = deviceId;
        _scannerDeviceLabel = label;
        _isDeviceApproved = approved;
        _isDeviceBlocked = blocked;
        _deviceStatusMessage = blocked
            ? '차단된 기기입니다. 관리자에게 해제를 요청하세요.'
            : approved
            ? '승인된 기기'
            : (message ?? '승인 대기 중입니다.');
      });

      if (!approved || blocked) {
        _controller.stop();
      } else {
        // 웹에서는 약간의 딜레이 후 카메라 시작 (렌더링 안정화)
        if (kIsWeb) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
        }
        try {
          await _controller.start();
          if (mounted) setState(() => _cameraStarted = true);
        } catch (e) {
          debugPrint('카메라 시작 실패: $e');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeviceApproved = false;
        _deviceStatusMessage = '기기 등록 실패: $e';
      });
      _controller.stop();
    } finally {
      if (mounted) {
        setState(() => _isDeviceLoading = false);
      }
      if (!silent && mounted && _deviceStatusMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_deviceStatusMessage!)));
      }
    }
  }

  // ──────────────────────────────────────────────
  //  오프라인 캐시 관련
  // ──────────────────────────────────────────────

  Future<void> _showEventSelector() async {
    final events = ref.read(allEventsStreamProvider).valueOrNull ?? [];
    // 오늘~내일 공연만 필터 (캐시 대상)
    final now = DateTime.now();
    final relevantEvents = events.where((e) {
      if (e.startAt == null) return false;
      final diff = e.startAt!.difference(now).inHours;
      return diff > -6 && diff < 48; // 6시간 전 ~ 48시간 후
    }).toList()
      ..sort((a, b) => (a.startAt ?? now).compareTo(b.startAt ?? now));

    if (!mounted) return;
    final selected = await showDialog<Event>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '공연 선택 (오프라인 캐시)',
          style: AppTheme.nanum(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            shadows: AppTheme.textShadow,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: relevantEvents.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    '오늘~내일 예정된 공연이 없습니다.',
                    style: AppTheme.nanum(color: AppTheme.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: relevantEvents.length,
                  separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                  itemBuilder: (_, i) {
                    final e = relevantEvents[i];
                    final timeStr = e.startAt != null
                        ? '${e.startAt!.month}/${e.startAt!.day} ${e.startAt!.hour}:${e.startAt!.minute.toString().padLeft(2, '0')}'
                        : '';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      title: Text(
                        e.title,
                        style: AppTheme.nanum(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        timeStr,
                        style: AppTheme.nanum(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.download_rounded, color: AppTheme.gold, size: 20),
                      onTap: () => Navigator.pop(ctx, e),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('닫기', style: AppTheme.nanum(color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );

    if (selected != null) {
      _downloadCache(selected.id, selected.title);
    }
  }

  Future<void> _downloadCache(String eventId, String eventTitle) async {
    if (_isCacheDownloading) return;
    setState(() => _isCacheDownloading = true);

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .downloadEventTicketsForScanner(eventId: eventId);

      if (result['success'] == true) {
        final cache = ref.read(offlineCheckinCacheProvider);
        await cache.cacheEventTickets(result);
        final total = (result['totalTickets'] as int? ?? 0) +
            (result['totalMobileTickets'] as int? ?? 0);

        if (mounted) {
          setState(() {
            _selectedEventId = eventId;
            _selectedEventTitle = eventTitle;
            _cachedTicketCount = total;
            _cacheDownloadedAt = result['downloadedAt'] as String?;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$total장 티켓 캐시 완료', style: AppTheme.nanum(fontSize: 13)),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('캐시 다운로드 실패: $e', style: AppTheme.nanum(fontSize: 13)),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCacheDownloading = false);
    }
  }

  Future<void> _updatePendingSyncCount() async {
    final cache = ref.read(offlineCheckinCacheProvider);
    final count = await cache.pendingSyncCount();
    if (mounted) setState(() => _pendingSyncCount = count);
  }

  /// 오프라인 체크인 큐를 서버에 동기화
  Future<void> _syncOfflineCheckins() async {
    final cache = ref.read(offlineCheckinCacheProvider);
    final queue = await cache.getSyncQueue();
    if (queue.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('동기화할 항목이 없습니다.', style: AppTheme.nanum(fontSize: 13)),
          ),
        );
      }
      return;
    }

    try {
      final result = await ref
          .read(functionsServiceProvider)
          .syncOfflineCheckins(checkins: queue);

      final synced = result['synced'] ?? 0;
      final skipped = result['skipped'] ?? 0;
      await cache.clearSyncQueue();

      if (mounted) {
        setState(() {
          _pendingSyncCount = 0;
          _isOfflineMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '동기화 완료: $synced건 성공${skipped > 0 ? ', $skipped건 스킵' : ''}',
              style: AppTheme.nanum(fontSize: 13),
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('동기화 실패: $e', style: AppTheme.nanum(fontSize: 13)),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  // ──────────────────────────────────────────────
  //  QR Processing
  // ──────────────────────────────────────────────

  Future<void> _processQrCode(String qrData) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _lastResult = null;
    });

    try {
      final raw = qrData.trim();
      final authUser = ref.read(authStateProvider).valueOrNull;
      if (authUser == null) {
        throw const FormatException('스캐너 사용 전 로그인이 필요합니다');
      }
      if (_scannerDeviceId == null || !_isDeviceApproved || _isDeviceBlocked) {
        throw const FormatException('승인된 스캐너 기기에서만 입장 체크가 가능합니다');
      }

      if (RegExp(r'^ticket:[^:]+:\d+$').hasMatch(raw)) {
        throw const FormatException('구버전 QR입니다. 티켓 앱을 최신 버전으로 업데이트해주세요');
      }

      final functionsService = ref.read(functionsServiceProvider);
      Map<String, dynamic> result;

      // 통합 QR: group:{orderId}:{jwtToken}
      if (raw.startsWith('group:')) {
        final firstColon = raw.indexOf(':');
        final secondColon = raw.indexOf(':', firstColon + 1);
        if (secondColon <= firstColon + 1 || secondColon >= raw.length - 1) {
          throw const FormatException('잘못된 통합 QR 형식입니다');
        }
        final orderId = raw.substring(firstColon + 1, secondColon);
        final qrToken = raw.substring(secondColon + 1);

        result = await functionsService.verifyAndCheckInGroup(
          orderId: orderId,
          qrToken: qrToken,
          staffId: authUser.uid,
          scannerDeviceId: _scannerDeviceId!,
          checkinStage: _checkinStage,
        );
      } else {
        // 개별 QR: ticketId:jwtToken
        final sepIndex = raw.indexOf(':');
        if (sepIndex <= 0 || sepIndex >= raw.length - 1) {
          throw const FormatException('지원하지 않는 QR 형식입니다');
        }
        final ticketId = raw.substring(0, sepIndex);
        final qrToken = raw.substring(sepIndex + 1);

        result = await functionsService.verifyAndCheckIn(
          ticketId: ticketId,
          qrToken: qrToken,
          staffId: authUser.uid,
          scannerDeviceId: _scannerDeviceId!,
          checkinStage: _checkinStage,
        );
      }

      _handleResult(result);
    } on FormatException catch (e) {
      if (!kIsWeb) HapticFeedback.vibrate();
      setState(() {
        _lastResult = _ScanResultData(
          isSuccess: false,
          title: '인식 오류',
          message: e.message,
        );
      });
    } catch (e) {
      // 네트워크 오류 시 오프라인 캐시로 폴백
      if (_selectedEventId != null) {
        try {
          final ticketId = _extractTicketId(qrData);
          if (ticketId != null) {
            final cache = ref.read(offlineCheckinCacheProvider);
            final offlineResult = await cache.offlineVerify(
              ticketId: ticketId,
              eventId: _selectedEventId!,
              checkinStage: _checkinStage,
            );
            _handleResult(offlineResult);
            await _updatePendingSyncCount();
            if (mounted) setState(() => _isOfflineMode = true);
            return; // finally 블록은 아래에서 처리
          }
        } catch (_) {
          // 오프라인 폴백도 실패하면 원래 에러 표시
        }
      }

      if (!kIsWeb) HapticFeedback.vibrate();
      setState(() {
        _lastResult = _ScanResultData(
          isSuccess: false,
          title: '처리 실패',
          message: e.toString().replaceAll(RegExp(r'\[.*?\]'), '').trim(),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);

        // Auto-dismiss result after 5 seconds and resume scanning
        _resultDismissTimer?.cancel();
        _resultDismissTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() => _lastResult = null);
            if (_isDeviceApproved && !_isDeviceBlocked) {
              _controller.start();
            }
          }
        });
      }
    }
  }

  void _handleResult(Map<String, dynamic> result) {
    final success = result['success'] == true;
    final message =
        result['message'] as String? ?? (success ? '입장 성공' : '입장 실패');
    final seatInfo = result['seatInfo'] as String?;
    final buyerName = result['buyerName'] as String?;
    final phoneLast4 = result['phoneLast4'] as String?;

    if (!kIsWeb) {
      if (success) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.vibrate();
      }
    }

    setState(() {
      _lastResult = _ScanResultData(
        isSuccess: success,
        title: _resultTitleForResponse(success, result),
        message: message,
        seatInfo: seatInfo,
        buyerName: buyerName,
        phoneLast4: phoneLast4,
      );
    });
  }

  /// QR 데이터에서 ticketId 추출 (오프라인 폴백용)
  String? _extractTicketId(String qrData) {
    final raw = qrData.trim();
    if (raw.startsWith('group:')) return null; // 그룹 QR은 오프라인 미지원
    final sepIndex = raw.indexOf(':');
    if (sepIndex <= 0) return null;
    return raw.substring(0, sepIndex);
  }

  // ──────────────────────────────────────────────
  //  긴급 수동모드 — 이름/전화번호로 검색 입장
  // ──────────────────────────────────────────────

  Future<void> _showManualSearchDialog() async {
    if (_selectedEventId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('먼저 캐시를 다운로드하세요.', style: AppTheme.nanum(fontSize: 13)),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    final textController = TextEditingController();
    final cache = ref.read(offlineCheckinCacheProvider);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppTheme.warning, size: 22),
                const SizedBox(width: 8),
                Text(
                  '긴급 수동 입장',
                  style: AppTheme.nanum(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    shadows: AppTheme.textShadow,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: textController,
                    autofocus: true,
                    style: AppTheme.nanum(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '이름 또는 전화번호 뒷자리',
                      hintStyle: AppTheme.nanum(color: AppTheme.textTertiary, fontSize: 13),
                      filled: true,
                      fillColor: AppTheme.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(() {}),
                        icon: const Icon(Icons.search, color: AppTheme.gold, size: 20),
                      ),
                    ),
                    onSubmitted: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: textController.text.trim().length >= 2
                        ? cache.searchByNameOrPhone(
                            eventId: _selectedEventId!,
                            query: textController.text.trim(),
                          )
                        : Future.value([]),
                    builder: (_, snap) {
                      final results = snap.data ?? [];
                      if (textController.text.trim().length < 2) {
                        return Text(
                          '2글자 이상 입력하세요',
                          style: AppTheme.nanum(color: AppTheme.textTertiary, fontSize: 12),
                        );
                      }
                      if (results.isEmpty) {
                        return Text(
                          '검색 결과 없음',
                          style: AppTheme.nanum(color: AppTheme.textSecondary, fontSize: 13),
                        );
                      }
                      return SizedBox(
                        height: 200,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                          itemBuilder: (_, i) {
                            final t = results[i];
                            final name = t['buyerName'] ?? '';
                            final phone = t['phoneLast4'] ?? '';
                            final seat = t['seatInfo'] ?? t['seatGrade'] ?? '';
                            final cacheKey = t['_cacheKey'] as String? ?? '';
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              title: Text(
                                '$name ($phone)',
                                style: AppTheme.nanum(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                seat,
                                style: AppTheme.nanum(color: AppTheme.textSecondary, fontSize: 12),
                              ),
                              trailing: FilledButton(
                                onPressed: () async {
                                  final result = await cache.offlineVerify(
                                    ticketId: cacheKey,
                                    eventId: _selectedEventId!,
                                    checkinStage: _checkinStage,
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(ctx);
                                    _handleResult(result);
                                    await _updatePendingSyncCount();
                                  }
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.success,
                                  minimumSize: const Size(60, 32),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  '입장',
                                  style: AppTheme.nanum(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('닫기', style: AppTheme.nanum(color: AppTheme.textSecondary)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Manual QR Input (for web testing)
  // ──────────────────────────────────────────────

  Future<void> _showManualQrInput() async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'QR 수동 입력',
          style: AppTheme.nanum(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            shadows: AppTheme.textShadow,
          ),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 3,
          style: AppTheme.nanum(color: AppTheme.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: '티켓 QR 데이터를 붙여넣으세요',
            hintStyle: AppTheme.nanum(
              color: AppTheme.textTertiary,
              fontSize: 13,
            ),
            filled: true,
            fillColor: AppTheme.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.gold, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '취소',
              style: AppTheme.nanum(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, textController.text),
            child: Text(
              '확인',
              style: AppTheme.nanum(
                color: AppTheme.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      _processQrCode(result.trim());
    }
  }

  // ──────────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Stack(
              children: [
                // Camera view
                _buildCameraView(),

                // Scan area overlay
                _buildScanOverlay(),

                // Instruction label
                _buildInstructionBadge(),

                // Processing indicator
                if (_isProcessing) _buildProcessingOverlay(),

                // Device approval guard
                if (_isDeviceLoading || !_isDeviceApproved || _isDeviceBlocked)
                  _buildDeviceGuardOverlay(),

                // Result overlay
                if (_lastResult != null && !_isProcessing)
                  _buildResultOverlay(_lastResult!),
              ],
            ),
          ),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Header
  // ──────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 8,
        right: 8,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary,
              size: 20,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              fixedSize: const Size(40, 40),
            ),
          ),
          const SizedBox(width: 12),

          // Title with gold accent
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: AppTheme.goldGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Color(0xFFFDF3F6),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '입장 스캐너',
                  style: AppTheme.nanum(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    shadows: AppTheme.textShadow,
                  ),
                ),
              ],
            ),
          ),

          // Flash toggle
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, child) {
              final isOn = state.torchState == TorchState.on;
              return IconButton(
                onPressed: () => _controller.toggleTorch(),
                icon: Icon(
                  isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: isOn ? AppTheme.gold : AppTheme.textSecondary,
                  size: 22,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  fixedSize: const Size(40, 40),
                ),
              );
            },
          ),
          const SizedBox(width: 6),

          // Camera switch
          IconButton(
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(
              Icons.cameraswitch_rounded,
              color: AppTheme.textSecondary,
              size: 22,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              fixedSize: const Size(40, 40),
            ),
          ),
          const SizedBox(width: 6),

          // 긴급 수동 검색
          IconButton(
            onPressed: _showManualSearchDialog,
            icon: const Icon(
              Icons.person_search_rounded,
              color: AppTheme.textSecondary,
              size: 22,
            ),
            tooltip: '긴급 수동 입장',
            style: IconButton.styleFrom(
              backgroundColor: _selectedEventId != null
                  ? AppTheme.warning.withAlpha(30)
                  : AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              fixedSize: const Size(40, 40),
            ),
          ),
          const SizedBox(width: 6),

          // Manual QR input
          IconButton(
            onPressed: _showManualQrInput,
            icon: const Icon(
              Icons.keyboard_rounded,
              color: AppTheme.textSecondary,
              size: 22,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              fixedSize: const Size(40, 40),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Camera View
  // ──────────────────────────────────────────────

  Widget _buildCameraView() {
    return Container(
      color: AppTheme.background,
      child: ClipRRect(
        child: MobileScanner(
          controller: _controller,
          errorBuilder: (context, error, child) {
            return _buildCameraError(error);
          },
          onDetect: (capture) {
            final barcode = capture.barcodes.firstOrNull;
            if (barcode?.rawValue != null &&
                !_isProcessing &&
                _isDeviceApproved &&
                !_isDeviceBlocked) {
              _controller.stop();
              _processQrCode(barcode!.rawValue!);
            }
          },
        ),
      ),
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    return Container(
      color: AppTheme.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: const Icon(
                  Icons.videocam_off_rounded,
                  size: 40,
                  color: AppTheme.textTertiary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '카메라를 사용할 수 없습니다',
                style: AppTheme.nanum(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '설정에서 카메라 권한을 허용해주세요',
                style: AppTheme.nanum(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  if (_isDeviceApproved && !_isDeviceBlocked) {
                    _controller.start();
                  }
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  '다시 시도',
                  style: AppTheme.nanum(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.gold,
                  side: const BorderSide(color: AppTheme.gold, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Scan Overlay (Viewfinder)
  // ──────────────────────────────────────────────

  Widget _buildScanOverlay() {
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 260,
          height: 260,
          child: CustomPaint(
            painter: _ViewfinderPainter(
              cornerColor: AppTheme.gold,
              borderColor: AppTheme.goldSubtle,
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Instruction Badge
  // ──────────────────────────────────────────────

  Widget _buildInstructionBadge() {
    return Positioned(
      top: 24,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xCC0B0B0F),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.goldSubtle, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.qr_code_rounded, color: AppTheme.gold, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$_stageHeadline · $_stageInstruction',
                  style: AppTheme.nanum(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Processing Overlay
  // ──────────────────────────────────────────────

  Widget _buildProcessingOverlay() {
    return Container(
      color: const Color(0xAA0B0B0F),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppTheme.gold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '확인 중...',
                style: AppTheme.nanum(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceGuardOverlay() {
    final title = _isDeviceLoading
        ? '스캐너 기기 확인 중'
        : _isDeviceBlocked
        ? '기기 사용이 차단되었습니다'
        : '승인 대기 중인 스캐너';
    final description = _isDeviceLoading
        ? '잠시만 기다려주세요.'
        : (_deviceStatusMessage ?? '관리자 승인 후 스캔이 활성화됩니다. 승인 요청은 자동으로 접수됩니다.');

    return Container(
      color: const Color(0xCC0B0B0F),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 26),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.borderLight, width: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isDeviceLoading
                    ? Icons.hourglass_top_rounded
                    : (_isDeviceBlocked
                          ? Icons.block_rounded
                          : Icons.admin_panel_settings_rounded),
                color: _isDeviceBlocked ? AppTheme.error : AppTheme.gold,
                size: 34,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: AppTheme.nanum(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  shadows: AppTheme.textShadow,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: AppTheme.nanum(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              if (_scannerDeviceId != null) ...[
                const SizedBox(height: 8),
                Text(
                  '기기 ID: ${_scannerDeviceId!.substring(0, 8)}...',
                  style: GoogleFonts.robotoMono(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isDeviceLoading
                      ? null
                      : () => _registerCurrentDevice(silent: true),
                  child: Text(
                    _isDeviceLoading ? '확인 중...' : '승인 상태 새로고침',
                    style: AppTheme.nanum(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Result Overlay
  // ──────────────────────────────────────────────

  Widget _buildResultOverlay(_ScanResultData result) {
    final color = result.isSuccess ? AppTheme.success : AppTheme.error;

    return GestureDetector(
      onTap: () {
        _resultDismissTimer?.cancel();
        setState(() => _lastResult = null);
        if (_isDeviceApproved && !_isDeviceBlocked) {
          _controller.start();
        }
      },
      child: Container(
        color: Color.lerp(const Color(0xFF0B0B0F), color, 0.08),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withAlpha(40),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withAlpha(26),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    result.isSuccess
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 44,
                    color: color,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  result.title,
                  style: AppTheme.nanum(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                    shadows: AppTheme.textShadowStrong,
                  ),
                ),
                const SizedBox(height: 8),

                // Message
                Text(
                  result.message,
                  style: AppTheme.nanum(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                // Buyer info (이름 + 전화번호 뒷4자리)
                if (result.isSuccess && (result.buyerName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.cardElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_rounded,
                          color: AppTheme.gold,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          result.buyerName!,
                          style: AppTheme.nanum(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                            shadows: AppTheme.textShadow,
                          ),
                        ),
                        if ((result.phoneLast4 ?? '').isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(
                            '(${result.phoneLast4})',
                            style: AppTheme.nanum(
                              fontSize: 15,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Seat info
                if (result.seatInfo != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.cardElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.event_seat_rounded,
                          color: AppTheme.gold,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          result.seatInfo!,
                          style: AppTheme.nanum(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                            shadows: AppTheme.textShadow,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Next scan button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: result.isSuccess ? null : AppTheme.goldGradient,
                      color: result.isSuccess ? AppTheme.success : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _resultDismissTimer?.cancel();
                          setState(() => _lastResult = null);
                          if (_isDeviceApproved && !_isDeviceBlocked) {
                            _controller.start();
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Center(
                          child: Text(
                            '다음 스캔',
                            style: AppTheme.nanum(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: result.isSuccess
                                  ? Colors.white
                                  : const Color(0xFFFDF3F6),
                              shadows: AppTheme.textShadowOnDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Bottom Panel
  // ──────────────────────────────────────────────

  Widget _buildBottomPanel() {
    final statusColor = _isProcessing
        ? AppTheme.gold
        : (_lastResult != null
              ? (_lastResult!.isSuccess ? AppTheme.success : AppTheme.error)
              : (_isDeviceApproved ? AppTheme.success : AppTheme.warning));

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.goldSubtle,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.confirmation_number_rounded,
                  color: AppTheme.gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_stageHeadline 스캔',
                      style: AppTheme.nanum(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _stageModeDescription,
                      style: AppTheme.nanum(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: statusColor.withAlpha(100), blurRadius: 8),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ─── 오프라인 캐시 상태 바 ───
          if (_selectedEventId != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _isOfflineMode
                    ? AppTheme.warning.withAlpha(26)
                    : AppTheme.success.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isOfflineMode ? AppTheme.warning : AppTheme.success,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isOfflineMode ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                    size: 16,
                    color: _isOfflineMode ? AppTheme.warning : AppTheme.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isOfflineMode
                              ? '오프라인 모드 · $_selectedEventTitle'
                              : '캐시 준비 · $_selectedEventTitle',
                          style: AppTheme.nanum(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isOfflineMode ? AppTheme.warning : AppTheme.success,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$_cachedTicketCount장 캐시됨${_pendingSyncCount > 0 ? ' · 동기화 대기 ${_pendingSyncCount}건' : ''}',
                          style: AppTheme.nanum(
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_pendingSyncCount > 0)
                    InkWell(
                      onTap: _syncOfflineCheckins,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.gold, width: 0.5),
                        ),
                        child: Text(
                          '동기화',
                          style: AppTheme.nanum(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.gold),
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: () => _downloadCache(_selectedEventId!, _selectedEventTitle ?? ''),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: _isOfflineMode ? AppTheme.warning : AppTheme.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment<String>(value: 'entry', label: Text('1차 입장')),
                    ButtonSegment<String>(
                      value: 'intermission',
                      label: Text('인터미션 확인'),
                    ),
                  ],
                  selected: {_checkinStage},
                  onSelectionChanged: (value) {
                    final nextStage = value.first;
                    setState(() => _checkinStage = nextStage);
                    if (nextStage == 'intermission') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '인터미션은 기본적으로 티켓 화면 확인만 하고, 재입장 처리 시에만 QR을 스캔하세요.',
                            style: AppTheme.nanum(fontSize: 13),
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppTheme.goldSubtle;
                      }
                      return AppTheme.card;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppTheme.gold;
                      }
                      return AppTheme.textSecondary;
                    }),
                    side: WidgetStateProperty.resolveWith((states) {
                      return BorderSide(
                        color: states.contains(WidgetState.selected)
                            ? AppTheme.gold
                            : AppTheme.border,
                        width: 0.8,
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isCacheDownloading ? null : _showEventSelector,
                style: FilledButton.styleFrom(
                  backgroundColor: _selectedEventId != null
                      ? AppTheme.success.withAlpha(30)
                      : AppTheme.cardElevated,
                  foregroundColor: _selectedEventId != null
                      ? AppTheme.success
                      : AppTheme.textPrimary,
                  minimumSize: const Size(92, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: _selectedEventId != null ? AppTheme.success : AppTheme.border,
                    ),
                  ),
                ),
                child: _isCacheDownloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _selectedEventId != null
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_download_rounded,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _selectedEventId != null ? '캐시됨' : '캐시',
                            style: AppTheme.nanum(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border, width: 0.8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _isIntermissionStage
                      ? Icons.visibility_rounded
                      : Icons.qr_code_scanner_rounded,
                  size: 16,
                  color: _isIntermissionStage
                      ? AppTheme.gold
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isIntermissionStage
                        ? '인터미션은 화면 확인이 기본입니다. 재입장 기록이 필요할 때만 QR을 스캔하세요.'
                        : '1차 입장은 QR 스캔으로 기록되며, 승인된 기기에서만 처리됩니다.',
                    style: AppTheme.nanum(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_scannerDeviceId != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_scannerDeviceLabel.isEmpty ? 'Scanner' : _scannerDeviceLabel} · '
                '${_isDeviceBlocked ? '차단됨' : (_isDeviceApproved ? '승인됨' : '승인대기')}',
                style: GoogleFonts.robotoMono(
                  fontSize: 11,
                  color: _isDeviceBlocked
                      ? AppTheme.error
                      : (_isDeviceApproved
                            ? AppTheme.success
                            : AppTheme.warning),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Scan Result Data Model (local)
// ──────────────────────────────────────────────

class _ScanResultData {
  final bool isSuccess;
  final String title;
  final String message;
  final String? seatInfo;
  final String? buyerName;
  final String? phoneLast4;

  const _ScanResultData({
    required this.isSuccess,
    required this.title,
    required this.message,
    this.seatInfo,
    this.buyerName,
    this.phoneLast4,
  });
}

// ──────────────────────────────────────────────
//  Viewfinder Painter
// ──────────────────────────────────────────────

class _ViewfinderPainter extends CustomPainter {
  final Color cornerColor;
  final Color borderColor;

  _ViewfinderPainter({required this.cornerColor, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    const cornerLength = 32.0;
    const cornerRadius = 16.0;
    const strokeWidth = 3.5;

    // Draw subtle border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final borderRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(cornerRadius),
    );
    canvas.drawRRect(borderRect, borderPaint);

    // Draw gold corner lines
    final cornerPaint = Paint()
      ..color = cornerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Top-left corner
    _drawCorner(
      canvas,
      cornerPaint,
      0,
      0,
      cornerLength,
      cornerRadius,
      true,
      true,
    );
    // Top-right corner
    _drawCorner(
      canvas,
      cornerPaint,
      size.width,
      0,
      cornerLength,
      cornerRadius,
      false,
      true,
    );
    // Bottom-left corner
    _drawCorner(
      canvas,
      cornerPaint,
      0,
      size.height,
      cornerLength,
      cornerRadius,
      true,
      false,
    );
    // Bottom-right corner
    _drawCorner(
      canvas,
      cornerPaint,
      size.width,
      size.height,
      cornerLength,
      cornerRadius,
      false,
      false,
    );
  }

  void _drawCorner(
    Canvas canvas,
    Paint paint,
    double x,
    double y,
    double length,
    double radius,
    bool isLeft,
    bool isTop,
  ) {
    final path = Path();
    final dx = isLeft ? 1.0 : -1.0;
    final dy = isTop ? 1.0 : -1.0;

    // Horizontal line
    path.moveTo(x + dx * length, y);
    path.lineTo(x + dx * radius, y);

    // Arc
    path.arcToPoint(
      Offset(x, y + dy * radius),
      radius: Radius.circular(radius),
      clockwise: isLeft == isTop,
    );

    // Vertical line
    path.lineTo(x, y + dy * length);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) {
    return oldDelegate.cornerColor != cornerColor ||
        oldDelegate.borderColor != borderColor;
  }
}
