import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/domain/catalog/event.dart';

import '../../app/admin_theme.dart';

class EventPhaseControlScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventPhaseControlScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventPhaseControlScreen> createState() =>
      _EventPhaseControlScreenState();
}

class _EventPhaseControlScreenState
    extends ConsumerState<EventPhaseControlScreen> {
  bool _isUpdating = false;

  static const _phases = [
    LivePhase.pre,
    LivePhase.seatReveal,
    LivePhase.entry,
    LivePhase.intermission,
    LivePhase.part2,
    LivePhase.ended,
  ];

  IconData _iconFor(LivePhase phase) => switch (phase) {
        LivePhase.pre => Icons.schedule_rounded,
        LivePhase.seatReveal => Icons.visibility_rounded,
        LivePhase.entry => Icons.login_rounded,
        LivePhase.intermission => Icons.coffee_rounded,
        LivePhase.part2 => Icons.play_arrow_rounded,
        LivePhase.ended => Icons.flag_rounded,
      };

  Color _colorFor(LivePhase phase, LivePhase current) {
    if (phase == current) {
      return switch (phase) {
        LivePhase.pre => AdminTheme.textSecondary,
        LivePhase.seatReveal => const Color(0xFFA78BFA),
        LivePhase.entry => const Color(0xFF4ADE80),
        LivePhase.intermission => AdminTheme.gold,
        LivePhase.part2 => const Color(0xFF60A5FA),
        LivePhase.ended => const Color(0xFFF87171),
      };
    }
    return AdminTheme.textTertiary;
  }

  Future<void> _revealNow(Event event) async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    try {
      final repo = ref.read(eventRepositoryProvider);
      await repo.updateEvent(widget.eventId, {
        'revealAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 1))),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('좌석 + QR이 즉시 공개되었습니다'),
          backgroundColor: Color(0xFF4ADE80),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('오류: $e'),
          backgroundColor: AdminTheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _setPhase(LivePhase phase, Event event) async {
    if (phase == event.livePhase || _isUpdating) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '단계 전환',
          style: AdminTheme.serif(fontSize: 18, color: AdminTheme.textPrimary),
        ),
        content: Text(
          '"${event.livePhase.label}" → "${phase.label}"(으)로 전환합니다.\n\n모바일 티켓 화면이 즉시 변경됩니다.',
          style: AdminTheme.sans(color: AdminTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: AdminTheme.sans(color: AdminTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _colorFor(phase, phase),
              foregroundColor: AdminTheme.onAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('전환',
                style: AdminTheme.sans(
                    fontWeight: FontWeight.w600, color: AdminTheme.onAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      final repo = ref.read(eventRepositoryProvider);
      final updates = <String, dynamic>{
        'livePhase': phase.name,
        'livePhaseUpdatedAt': FieldValue.serverTimestamp(),
      };
      // 좌석 공개 단계 전환 시 자동으로 revealAt 트리거
      if (phase == LivePhase.seatReveal && !event.isSeatsRevealed) {
        updates['revealAt'] = Timestamp.fromDate(
            DateTime.now().subtract(const Duration(minutes: 1)));
      }
      await repo.updateEvent(widget.eventId, updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${phase.label} 단계로 전환되었습니다'),
          backgroundColor: _colorFor(phase, phase),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('오류: $e'),
          backgroundColor: AdminTheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));

    return Scaffold(
      backgroundColor: AdminTheme.background,
      appBar: AppBar(
        backgroundColor: AdminTheme.surface,
        foregroundColor: AdminTheme.textPrimary,
        title: Text('공연 진행 제어',
            style: AdminTheme.serif(fontSize: 18, color: AdminTheme.gold)),
      ),
      body: eventAsync.when(
        data: (event) {
          if (event == null) {
            return Center(
              child: Text('공연을 찾을 수 없습니다',
                  style: AdminTheme.sans(color: AdminTheme.error)),
            );
          }
          return _buildBody(event);
        },
        loading: () => const Center(
            child: CircularProgressIndicator(color: AdminTheme.gold)),
        error: (e, _) => Center(
          child:
              Text('오류: $e', style: AdminTheme.sans(color: AdminTheme.error)),
        ),
      ),
    );
  }

  Widget _buildBody(Event event) {
    final current = event.livePhase;
    final currentIdx = _phases.indexOf(current);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 공연 정보 헤더 ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AdminTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: AdminTheme.serif(
                      fontSize: 20, color: AdminTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 14, color: AdminTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '${event.startAt.month}/${event.startAt.day} ${event.startAt.hour.toString().padLeft(2, '0')}:${event.startAt.minute.toString().padLeft(2, '0')}',
                      style: AdminTheme.sans(color: AdminTheme.textSecondary),
                    ),
                    const SizedBox(width: 16),
                    if (event.venueName != null) ...[
                      Icon(Icons.location_on_outlined,
                          size: 14, color: AdminTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        event.venueName!,
                        style:
                            AdminTheme.sans(color: AdminTheme.textSecondary),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // ── 즉시 공개 버튼 (아직 공개 전이면) ──
          if (!event.isSeatsRevealed) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isUpdating ? null : () => _revealNow(event),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: Text('좌석 + QR 지금 공개',
                    style: AdminTheme.sans(
                        fontWeight: FontWeight.w600,
                        color: AdminTheme.onAccent,
                        noShadow: true)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTheme.gold,
                  foregroundColor: AdminTheme.onAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // ── 현재 단계 표시 ──
          Center(
            child: Column(
              children: [
                Text('현재 단계',
                    style: AdminTheme.label(
                        fontSize: 11, color: AdminTheme.textTertiary)),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: _colorFor(current, current).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(
                      color: _colorFor(current, current).withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconFor(current),
                          color: _colorFor(current, current), size: 22),
                      const SizedBox(width: 10),
                      Text(
                        current.label,
                        style: AdminTheme.serif(
                          fontSize: 22,
                          color: _colorFor(current, current),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // ── 단계 타임라인 버튼 ──
          ...List.generate(_phases.length, (i) {
            final phase = _phases[i];
            final isActive = phase == current;
            final isPast = i < currentIdx;
            final isNext = i == currentIdx + 1;
            final color = _colorFor(phase, current);

            return Column(
              children: [
                // 연결선
                if (i > 0)
                  Container(
                    width: 2,
                    height: 24,
                    color: isPast || isActive
                        ? _colorFor(_phases[i - 1], _phases[i - 1])
                            .withValues(alpha: 0.4)
                        : AdminTheme.border,
                  ),

                // 단계 카드
                GestureDetector(
                  onTap: _isUpdating ? null : () => _setPhase(phase, event),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: isActive
                          ? color.withValues(alpha: 0.12)
                          : AdminTheme.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isActive
                            ? color.withValues(alpha: 0.5)
                            : isNext
                                ? color.withValues(alpha: 0.25)
                                : AdminTheme.border,
                        width: isActive ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // 상태 아이콘
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isActive
                                ? color.withValues(alpha: 0.2)
                                : isPast
                                    ? color.withValues(alpha: 0.1)
                                    : AdminTheme.cardElevated,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isPast ? Icons.check_rounded : _iconFor(phase),
                            color: isActive || isPast
                                ? color
                                : AdminTheme.textTertiary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 16),

                        // 텍스트
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                phase.label,
                                style: AdminTheme.sans(
                                  fontSize: 16,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isActive || isPast
                                      ? AdminTheme.textPrimary
                                      : AdminTheme.textSecondary,
                                  noShadow: true,
                                ),
                              ),
                              Text(
                                _descriptionFor(phase),
                                style: AdminTheme.sans(
                                  fontSize: 12,
                                  color: AdminTheme.textTertiary,
                                  noShadow: true,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 현재/다음 표시
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('현재',
                                style: AdminTheme.sans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AdminTheme.onAccent,
                                    noShadow: true)),
                          )
                        else if (isNext)
                          Icon(Icons.arrow_forward_rounded,
                              color: color, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),

          if (_isUpdating) ...[
            const SizedBox(height: 24),
            const Center(
              child: CircularProgressIndicator(color: AdminTheme.gold),
            ),
          ],
        ],
      ),
    );
  }

  String _descriptionFor(LivePhase phase) => switch (phase) {
        LivePhase.pre => '공연 시작 전 대기 상태',
        LivePhase.seatReveal => '좌석 + QR 공개, 좌석 배정 확인',
        LivePhase.entry => 'QR 스캔 입장 진행 중',
        LivePhase.intermission => '설문지 표시, 재입장 준비',
        LivePhase.part2 => '2부 공연 진행 중',
        LivePhase.ended => '네이버 리뷰 유도 표시',
      };
}
