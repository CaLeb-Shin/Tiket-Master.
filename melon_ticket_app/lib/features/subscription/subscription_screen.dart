import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/melon_core.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _isActivating = false;
  bool _isApplying = false;
  SubscriptionPlan? _selectedPlan;
  String? _selectedGrade;
  String? _selectedEventId;

  static const _gradeColors = {
    'VIP': Color(0xFFC9A84C),
    'R': Color(0xFF30D158),
    'S': Color(0xFF0A84FF),
    'A': Color(0xFFFF9F0A),
  };

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _buildAppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('로그인이 필요합니다',
                  style: AppTheme.sans(color: AppTheme.textPrimary)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.push('/login'),
                child: const Text('로그인하기'),
              ),
            ],
          ),
        ),
      );
    }

    final subAsync = ref.watch(activeSubscriptionProvider(user.id));
    final entriesAsync = ref.watch(userEntriesProvider(user.id));
    final eventsAsync = ref.watch(eventsStreamProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: subAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (sub) {
          if (sub == null || !sub.isActive) {
            return _buildPlanSelection(user);
          }
          return _buildActiveSubscription(
            user,
            sub,
            entriesAsync.value ?? [],
            eventsAsync.value ?? [],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, size: 20),
        onPressed: () => context.pop(),
      ),
      title: Text(
        'MELTING',
        style: AppTheme.label(fontSize: 12, color: AppTheme.gold),
      ),
      centerTitle: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAN SELECTION (구독 전)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPlanSelection(AppUser user) {
    final fmt = NumberFormat('#,###');
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '멜팅 구독',
          style: AppTheme.serif(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '매달 구독으로 특별한 공연 좌석을\n응모를 통해 만나보세요.',
          style: AppTheme.sans(
            fontSize: 14,
            color: AppTheme.sage,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),

        for (final plan in SubscriptionPlan.values) ...[
          _buildPlanCard(plan, fmt),
          const SizedBox(height: 16),
        ],

        const SizedBox(height: 16),

        // Activate button
        if (_selectedPlan != null)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isActivating ? null : () => _activate(user.id),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: AppTheme.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(2),
                ),
                elevation: 0,
              ),
              child: _isActivating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '${_selectedPlan!.displayName} 구독 시작 — ${fmt.format(_selectedPlan!.monthlyPrice)}원/월',
                      style: AppTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onAccent,
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan, NumberFormat fmt) {
    final isSelected = _selectedPlan == plan;
    final tierName = plan.tierGrant[0].toUpperCase() + plan.tierGrant.substring(1);

    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = plan),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isSelected ? AppTheme.gold : AppTheme.border,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  plan.displayName,
                  style: AppTheme.serif(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? AppTheme.gold : AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${fmt.format(plan.monthlyPrice)}원/월',
                  style: AppTheme.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _planFeature(
              Icons.confirmation_number_outlined,
              '월 ${plan.monthlyEntries >= 999 ? "무제한" : "${plan.monthlyEntries}회"} 응모',
            ),
            const SizedBox(height: 6),
            _planFeature(
              Icons.verified_outlined,
              plan.monthlyGuarantees > 0
                  ? '월 ${plan.monthlyGuarantees}회 당첨 보장'
                  : '당첨 보장 없음',
              dim: plan.monthlyGuarantees == 0,
            ),
            const SizedBox(height: 6),
            _planFeature(
              Icons.workspace_premium_outlined,
              '$tierName 등급 자동 부여',
            ),
          ],
        ),
      ),
    );
  }

  Widget _planFeature(IconData icon, String text, {bool dim = false}) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: dim ? AppTheme.sage.withValues(alpha: 0.4) : AppTheme.sage,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: AppTheme.sans(
            fontSize: 13,
            color: dim
                ? AppTheme.sage.withValues(alpha: 0.4)
                : AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIVE SUBSCRIPTION (구독 중)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActiveSubscription(
    AppUser user,
    Subscription sub,
    List<SubscriptionEntry> entries,
    List<Event> events,
  ) {
    final fmt = NumberFormat('#,###');
    final dateFmt = DateFormat('yyyy.MM.dd');

    // 구독 좌석이 있는 이벤트만 필터
    final lotteryEvents = events
        .where(
          (e) =>
              e.subscriptionSeats != null &&
              e.subscriptionSeats!.isNotEmpty &&
              e.status == EventStatus.active,
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── 구독 상태 카드 ──
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppTheme.gold, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      sub.plan.displayName.toUpperCase(),
                      style: AppTheme.label(
                        fontSize: 9,
                        color: AppTheme.onAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      sub.status.displayName,
                      style: AppTheme.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2D6A4F),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _statItem(
                    '남은 응모권',
                    sub.plan == SubscriptionPlan.premium
                        ? '무제한'
                        : '${sub.entriesRemaining}회',
                  ),
                  const SizedBox(width: 24),
                  _statItem('보장 잔여', '${sub.guaranteesRemaining}회'),
                  const SizedBox(width: 24),
                  _statItem('구독 만료', dateFmt.format(sub.endDate)),
                ],
              ),
              if (sub.consecutiveLosses > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '연속 ${sub.consecutiveLosses}회 미당첨 — ${3 - sub.consecutiveLosses}회 더 미당첨 시 보장 당첨',
                    style: AppTheme.sans(
                      fontSize: 11,
                      color: AppTheme.gold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 32),

        // ── 응모 가능한 공연 ──
        Text(
          'LOTTERY',
          style: AppTheme.label(fontSize: 10, color: AppTheme.sage),
        ),
        const SizedBox(height: 4),
        Text(
          '응모 가능한 공연',
          style: AppTheme.serif(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),

        if (lotteryEvents.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: AppTheme.border, width: 0.5),
            ),
            child: Center(
              child: Text(
                '현재 응모 가능한 공연이 없습니다',
                style: AppTheme.sans(fontSize: 13, color: AppTheme.sage),
              ),
            ),
          ),

        for (final event in lotteryEvents) ...[
          _buildEventLotteryCard(event, sub, entries, fmt),
          const SizedBox(height: 12),
        ],

        const SizedBox(height: 32),

        // ── 응모 내역 ──
        if (entries.isNotEmpty) ...[
          Text(
            'HISTORY',
            style: AppTheme.label(fontSize: 10, color: AppTheme.sage),
          ),
          const SizedBox(height: 4),
          Text(
            '응모 내역',
            style: AppTheme.serif(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          for (final entry in entries) ...[
            _buildEntryItem(entry),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.sans(fontSize: 10, color: AppTheme.sage),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.sans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildEventLotteryCard(
    Event event,
    Subscription sub,
    List<SubscriptionEntry> entries,
    NumberFormat fmt,
  ) {
    final alreadyApplied = entries.any(
      (e) => e.eventId == event.id && e.status == SubscriptionEntryStatus.pending,
    );
    final subSeats = event.subscriptionSeats ?? {};
    final dateFmt = DateFormat('MM.dd (E)', 'ko');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event title + date
          Text(
            event.title,
            style: AppTheme.sans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${dateFmt.format(event.startAt)} · ${event.venueName ?? ""}',
            style: AppTheme.sans(fontSize: 12, color: AppTheme.sage),
          ),
          const SizedBox(height: 12),

          // Grade buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final grade in ['VIP', 'R', 'S', 'A'])
                if (subSeats.containsKey(grade) && subSeats[grade]! > 0)
                  _buildGradeChip(
                    grade,
                    subSeats[grade]!,
                    event.id,
                    alreadyApplied,
                    sub,
                  ),
            ],
          ),

          if (alreadyApplied) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2D6A4F).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 14, color: Color(0xFF2D6A4F)),
                  const SizedBox(width: 6),
                  Text(
                    '응모 완료 — 추첨 대기 중',
                    style: AppTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2D6A4F),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGradeChip(
    String grade,
    int seats,
    String eventId,
    bool alreadyApplied,
    Subscription sub,
  ) {
    final color = _gradeColors[grade] ?? AppTheme.sage;
    final isThisSelected =
        _selectedGrade == grade && _selectedEventId == eventId;

    return GestureDetector(
      onTap: alreadyApplied || !sub.hasEntries
          ? null
          : () {
              if (isThisSelected) {
                _applyForLottery(eventId, grade);
              } else {
                setState(() {
                  _selectedGrade = grade;
                  _selectedEventId = eventId;
                });
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isThisSelected
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: alreadyApplied
                ? AppTheme.sage.withValues(alpha: 0.2)
                : isThisSelected
                    ? color
                    : AppTheme.border,
            width: isThisSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              grade,
              style: AppTheme.label(
                fontSize: 10,
                color: alreadyApplied
                    ? AppTheme.sage.withValues(alpha: 0.4)
                    : color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${seats}석',
              style: AppTheme.sans(
                fontSize: 11,
                color: alreadyApplied
                    ? AppTheme.sage.withValues(alpha: 0.4)
                    : AppTheme.textPrimary,
              ),
            ),
            if (isThisSelected && !_isApplying) ...[
              const SizedBox(height: 4),
              Text(
                '탭하여 응모',
                style: AppTheme.sans(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
            if (isThisSelected && _isApplying)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryItem(SubscriptionEntry entry) {
    final dateFmt = DateFormat('MM.dd HH:mm');
    final statusColor = switch (entry.status) {
      SubscriptionEntryStatus.pending => AppTheme.sage,
      SubscriptionEntryStatus.won => const Color(0xFF2D6A4F),
      SubscriptionEntryStatus.lost => const Color(0xFFC42A4D),
      SubscriptionEntryStatus.refunded => AppTheme.sage,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (_gradeColors[entry.seatGrade] ?? AppTheme.sage)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              entry.seatGrade,
              style: AppTheme.label(
                fontSize: 9,
                color: _gradeColors[entry.seatGrade] ?? AppTheme.sage,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              dateFmt.format(entry.createdAt),
              style: AppTheme.sans(fontSize: 12, color: AppTheme.sage),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              entry.status.displayName,
              style: AppTheme.sans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _activate(String userId) async {
    if (_selectedPlan == null || _isActivating) return;
    setState(() => _isActivating = true);
    try {
      await ref.read(functionsServiceProvider).activateSubscription(
            userId: userId,
            plan: _selectedPlan!.name,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedPlan!.displayName} 구독이 시작되었습니다!'),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('구독 활성화 실패: $e'),
            backgroundColor: const Color(0xFFC42A4D),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActivating = false);
    }
  }

  Future<void> _applyForLottery(String eventId, String grade) async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    try {
      await ref.read(functionsServiceProvider).applyForSubscriptionLottery(
            eventId: eventId,
            seatGrade: grade,
          );
      if (mounted) {
        setState(() {
          _selectedGrade = null;
          _selectedEventId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$grade석 응모 완료!'),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('응모 실패: $e'),
            backgroundColor: const Color(0xFFC42A4D),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }
}
