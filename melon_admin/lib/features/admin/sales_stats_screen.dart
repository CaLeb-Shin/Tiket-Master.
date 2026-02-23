import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/event.dart';
import 'package:melon_core/data/models/order.dart' as app;
import 'package:melon_core/data/repositories/event_repository.dart';
import 'package:melon_core/data/repositories/order_repository.dart';

// ─── Period Filter ───
enum _PeriodFilter { week, month, all }

extension _PeriodFilterExt on _PeriodFilter {
  String get label => switch (this) {
        _PeriodFilter.week => '7일',
        _PeriodFilter.month => '30일',
        _PeriodFilter.all => '전체',
      };

  int? get days => switch (this) {
        _PeriodFilter.week => 7,
        _PeriodFilter.month => 30,
        _PeriodFilter.all => null,
      };
}

// ─── Daily Aggregate Model ───
class _DailyStats {
  final DateTime date;
  final int sales; // paid quantity
  final int cancels; // refunded + canceled quantity
  final int revenue; // net revenue

  _DailyStats({
    required this.date,
    required this.sales,
    required this.cancels,
    required this.revenue,
  });

  int get net => sales - cancels;
}

// ─────────────────────────────────────────────
// MT-044  Sales Stats Screen
// ─────────────────────────────────────────────
class SalesStatsScreen extends ConsumerStatefulWidget {
  const SalesStatsScreen({super.key});

  @override
  ConsumerState<SalesStatsScreen> createState() => _SalesStatsScreenState();
}

class _SalesStatsScreenState extends ConsumerState<SalesStatsScreen> {
  final _fmt = NumberFormat('#,###');
  final _dateFmt = DateFormat('MM.dd');
  final _fullDateFmt = DateFormat('yyyy.MM.dd');

  String? _selectedEventId;
  _PeriodFilter _period = _PeriodFilter.month;

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(allEventsStreamProvider);

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            _buildHeader(),
            const SizedBox(height: 8),
            Text(
              '공연별 일간 티켓 판매 추이 및 통계를 확인하세요.',
              style: AdminTheme.sans(
                fontSize: 14,
                color: AdminTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 28),

            // ── Controls: Event selector + Period filter ──
            eventsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('이벤트 로드 실패: $e',
                  style: AdminTheme.sans(color: AdminTheme.error)),
              data: (events) {
                // Sort by startAt descending for dropdown
                final sorted = [...events]
                  ..sort((a, b) => b.startAt.compareTo(a.startAt));
                // Auto-select first if nothing chosen
                if (_selectedEventId == null && sorted.isNotEmpty) {
                  _selectedEventId = sorted.first.id;
                }
                return _buildControls(sorted);
              },
            ),
            const SizedBox(height: 28),

            // ── Body ──
            Expanded(
              child: _selectedEventId == null
                  ? Center(
                      child: Text(
                        '공연을 선택해 주세요.',
                        style: AdminTheme.sans(
                          color: AdminTheme.textTertiary,
                          fontSize: 15,
                        ),
                      ),
                    )
                  : _OrdersDataView(
                      eventId: _selectedEventId!,
                      period: _period,
                      fmt: _fmt,
                      dateFmt: _dateFmt,
                      fullDateFmt: _fullDateFmt,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──
  Widget _buildHeader() {
    return Row(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => context.go('/'),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AdminTheme.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AdminTheme.border, width: 0.5),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  size: 18, color: AdminTheme.textSecondary),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(Icons.bar_chart_rounded, size: 28, color: AdminTheme.gold),
        const SizedBox(width: 12),
        Text(
          '일별 판매 통계',
          style: AdminTheme.serif(fontSize: 24, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  // ── Controls row ──
  Widget _buildControls(List<Event> events) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Event dropdown
        Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AdminTheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AdminTheme.border, width: 0.5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedEventId,
              isExpanded: true,
              dropdownColor: AdminTheme.card,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AdminTheme.textSecondary, size: 20),
              style: AdminTheme.sans(fontSize: 14),
              hint: Text('공연 선택',
                  style: AdminTheme.sans(color: AdminTheme.textTertiary)),
              items: events.map((e) {
                final dateStr = DateFormat('yy.MM.dd').format(e.startAt);
                return DropdownMenuItem<String>(
                  value: e.id,
                  child: Text(
                    '${e.title}  ($dateStr)',
                    overflow: TextOverflow.ellipsis,
                    style: AdminTheme.sans(fontSize: 13),
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedEventId = val),
            ),
          ),
        ),

        // Period filter chips
        Row(
          mainAxisSize: MainAxisSize.min,
          children: _PeriodFilter.values.map((f) {
            final active = _period == f;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _period = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active
                          ? AdminTheme.gold.withValues(alpha: 0.15)
                          : AdminTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: active
                            ? AdminTheme.gold.withValues(alpha: 0.5)
                            : AdminTheme.border,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      f.label,
                      style: AdminTheme.sans(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? AdminTheme.gold
                            : AdminTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── Orders data view (loads orders for a single event) ───
class _OrdersDataView extends ConsumerWidget {
  final String eventId;
  final _PeriodFilter period;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  final DateFormat fullDateFmt;

  const _OrdersDataView({
    required this.eventId,
    required this.period,
    required this.fmt,
    required this.dateFmt,
    required this.fullDateFmt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(_eventOrdersProvider(eventId));
    final eventAsync = ref.watch(eventStreamProvider(eventId));

    return ordersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AdminTheme.gold),
      ),
      error: (e, _) => Center(
        child: Text('주문 로드 실패: $e',
            style: AdminTheme.sans(color: AdminTheme.error)),
      ),
      data: (orders) {
        final totalSeats =
            eventAsync.valueOrNull?.totalSeats ?? 0;
        final dailyStats = _computeDailyStats(orders, period);
        return _StatsBody(
          dailyStats: dailyStats,
          totalSeats: totalSeats,
          period: period,
          fmt: fmt,
          dateFmt: dateFmt,
          fullDateFmt: fullDateFmt,
        );
      },
    );
  }

  /// Group orders by date and aggregate
  List<_DailyStats> _computeDailyStats(
      List<app.Order> orders, _PeriodFilter period) {
    // Build map: dateKey -> { sales, cancels, revenue }
    final Map<String, _MutableDay> dayMap = {};
    final df = DateFormat('yyyy-MM-dd');

    for (final o in orders) {
      final date = o.paidAt ?? o.createdAt;
      final key = df.format(date);
      dayMap.putIfAbsent(key, () => _MutableDay());

      if (o.status == app.OrderStatus.paid) {
        dayMap[key]!.sales += o.quantity;
        dayMap[key]!.revenue += o.totalAmount;
      } else if (o.status == app.OrderStatus.refunded ||
          o.status == app.OrderStatus.canceled) {
        dayMap[key]!.cancels += o.canceledCount > 0 ? o.canceledCount : o.quantity;
      }
    }

    // Sort by date ascending
    final sortedKeys = dayMap.keys.toList()..sort();

    // Filter by period
    final cutoff = period.days != null
        ? DateTime.now().subtract(Duration(days: period.days!))
        : null;

    final result = <_DailyStats>[];
    for (final key in sortedKeys) {
      final date = df.parse(key);
      if (cutoff != null && date.isBefore(cutoff)) continue;
      final d = dayMap[key]!;
      result.add(_DailyStats(
        date: date,
        sales: d.sales,
        cancels: d.cancels,
        revenue: d.revenue,
      ));
    }
    return result;
  }
}

class _MutableDay {
  int sales = 0;
  int cancels = 0;
  int revenue = 0;
}

// ── Provider: all orders for a given event ──
final _eventOrdersProvider =
    StreamProvider.family<List<app.Order>, String>((ref, eventId) {
  return ref.watch(orderRepositoryProvider).getOrdersByEvent(eventId);
});

// ─── Stats body: summary cards + bar chart + table ───
class _StatsBody extends StatelessWidget {
  final List<_DailyStats> dailyStats;
  final int totalSeats;
  final _PeriodFilter period;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  final DateFormat fullDateFmt;

  const _StatsBody({
    required this.dailyStats,
    required this.totalSeats,
    required this.period,
    required this.fmt,
    required this.dateFmt,
    required this.fullDateFmt,
  });

  @override
  Widget build(BuildContext context) {
    // Aggregates
    final totalSales = dailyStats.fold<int>(0, (s, d) => s + d.sales);
    final totalCancels = dailyStats.fold<int>(0, (s, d) => s + d.cancels);
    final totalRevenue = dailyStats.fold<int>(0, (s, d) => s + d.revenue);
    final avgDaily =
        dailyStats.isNotEmpty ? (totalSales / dailyStats.length) : 0.0;
    final salesRate =
        totalSeats > 0 ? ((totalSales - totalCancels) / totalSeats * 100) : 0.0;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Summary cards ──
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _SummaryCard(
                icon: Icons.confirmation_number_rounded,
                label: '총 판매',
                value: '${fmt.format(totalSales)}매',
                subtext: '취소 ${fmt.format(totalCancels)}매',
                color: AdminTheme.gold,
              ),
              _SummaryCard(
                icon: Icons.payments_rounded,
                label: '총 매출',
                value: '${fmt.format(totalRevenue)}원',
                subtext: '순 ${fmt.format(totalSales - totalCancels)}매',
                color: AdminTheme.success,
              ),
              _SummaryCard(
                icon: Icons.trending_up_rounded,
                label: '일 평균 판매',
                value: '${avgDaily.toStringAsFixed(1)}매',
                subtext: '${dailyStats.length}일 기준',
                color: AdminTheme.info,
              ),
              _SummaryCard(
                icon: Icons.pie_chart_rounded,
                label: '판매율',
                value: '${salesRate.toStringAsFixed(1)}%',
                subtext: totalSeats > 0
                    ? '${fmt.format(totalSales - totalCancels)} / ${fmt.format(totalSeats)}'
                    : '-',
                color: salesRate >= 80
                    ? AdminTheme.success
                    : salesRate >= 50
                        ? AdminTheme.warning
                        : AdminTheme.error,
              ),
            ],
          ),
          const SizedBox(height: 32),

          // ── Bar Chart ──
          if (dailyStats.isNotEmpty) ...[
            Text('DAILY SALES',
                style: AdminTheme.label(
                    fontSize: 10, color: AdminTheme.textTertiary)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 220,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              decoration: BoxDecoration(
                color: AdminTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminTheme.border, width: 0.5),
              ),
              child: _BarChart(
                dailyStats: dailyStats,
                dateFmt: dateFmt,
              ),
            ),
            const SizedBox(height: 32),
          ],

          // ── Data table ──
          Text('DAILY BREAKDOWN',
              style: AdminTheme.label(
                  fontSize: 10, color: AdminTheme.textTertiary)),
          const SizedBox(height: 12),
          _buildTable(),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildTable() {
    // Cumulative calculation (top = oldest)
    final rows = <_DailyStats>[...dailyStats];
    int cumulative = 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AdminTheme.card,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                _tableHeader('날짜', flex: 2),
                _tableHeader('판매', flex: 1),
                _tableHeader('취소', flex: 1),
                _tableHeader('순 판매', flex: 1),
                _tableHeader('누적', flex: 1),
                _tableHeader('매출', flex: 2, align: TextAlign.right),
              ],
            ),
          ),
          // Data rows
          ...rows.map((day) {
            cumulative += day.net;
            return _buildTableRow(day, cumulative);
          }),
          // Totals row
          _buildTotalsRow(rows),
        ],
      ),
    );
  }

  Widget _tableHeader(String text,
      {int flex = 1, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        style: AdminTheme.label(fontSize: 10, color: AdminTheme.textTertiary),
      ),
    );
  }

  Widget _buildTableRow(_DailyStats day, int cumulative) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AdminTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              fullDateFmt.format(day.date),
              style: AdminTheme.sans(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '+${day.sales}',
              style: AdminTheme.sans(
                fontSize: 13,
                color: AdminTheme.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              day.cancels > 0 ? '-${day.cancels}' : '0',
              style: AdminTheme.sans(
                fontSize: 13,
                color: day.cancels > 0
                    ? AdminTheme.error
                    : AdminTheme.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${day.net}',
              style: AdminTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: day.net >= 0 ? AdminTheme.textPrimary : AdminTheme.error,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '$cumulative',
              style: AdminTheme.sans(
                fontSize: 13,
                color: AdminTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${fmt.format(day.revenue)}원',
              textAlign: TextAlign.right,
              style: AdminTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsRow(List<_DailyStats> rows) {
    final totalSales = rows.fold<int>(0, (s, d) => s + d.sales);
    final totalCancels = rows.fold<int>(0, (s, d) => s + d.cancels);
    final totalNet = totalSales - totalCancels;
    final totalRevenue = rows.fold<int>(0, (s, d) => s + d.revenue);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '합계',
              style: AdminTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AdminTheme.gold,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '+$totalSales',
              style: AdminTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AdminTheme.success,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              totalCancels > 0 ? '-$totalCancels' : '0',
              style: AdminTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: totalCancels > 0
                    ? AdminTheme.error
                    : AdminTheme.textTertiary,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '$totalNet',
              style: AdminTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AdminTheme.gold,
              ),
            ),
          ),
          const Expanded(flex: 1, child: SizedBox.shrink()),
          Expanded(
            flex: 2,
            child: Text(
              '${fmt.format(totalRevenue)}원',
              textAlign: TextAlign.right,
              style: AdminTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AdminTheme.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Summary Card ───
class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtext;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtext,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: AdminTheme.sans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: AdminTheme.sans(
              fontSize: 12,
              color: AdminTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bar Chart (Container-based) ───
class _BarChart extends StatelessWidget {
  final List<_DailyStats> dailyStats;
  final DateFormat dateFmt;

  const _BarChart({
    required this.dailyStats,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    if (dailyStats.isEmpty) {
      return Center(
        child: Text('데이터 없음',
            style: AdminTheme.sans(color: AdminTheme.textTertiary)),
      );
    }

    final maxSales =
        dailyStats.map((d) => d.sales).reduce(math.max).toDouble();
    final maxVal = maxSales > 0 ? maxSales : 1.0;

    // Show max ~30 bars to avoid overcrowding
    final displayData = dailyStats.length > 30
        ? dailyStats.sublist(dailyStats.length - 30)
        : dailyStats;

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartHeight = constraints.maxHeight - 28; // bottom label space
        final chartWidth = constraints.maxWidth;
        final barCount = displayData.length;
        final gapRatio = 0.3;
        final totalBarWidth =
            chartWidth / (barCount + barCount * gapRatio + gapRatio);
        final barWidth = totalBarWidth;
        final gap = totalBarWidth * gapRatio;

        return Column(
          children: [
            // Bars
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(displayData.length, (i) {
                  final d = displayData[i];
                  final ratio = d.sales / maxVal;
                  final barH =
                      math.max(2.0, ratio * chartHeight);
                  final cancelRatio =
                      maxVal > 0 ? d.cancels / maxVal : 0.0;
                  final cancelH =
                      math.max(0.0, cancelRatio * chartHeight);

                  return Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? gap : gap / 2,
                      right: i == displayData.length - 1 ? gap : gap / 2,
                    ),
                    child: SizedBox(
                      width: barWidth,
                      child: Tooltip(
                        message:
                            '${dateFmt.format(d.date)}\n판매: ${d.sales}  취소: ${d.cancels}\n매출: ${NumberFormat('#,###').format(d.revenue)}원',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Cancel bar (red, stacked on top)
                            if (d.cancels > 0)
                              Container(
                                width: barWidth,
                                height: cancelH.clamp(0.0, chartHeight * 0.8),
                                decoration: BoxDecoration(
                                  color: AdminTheme.error
                                      .withValues(alpha: 0.5),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(2)),
                                ),
                              ),
                            // Sales bar (gold)
                            Container(
                              width: barWidth,
                              height: barH.clamp(2.0, chartHeight * 0.95),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    AdminTheme.gold
                                        .withValues(alpha: 0.8),
                                    AdminTheme.gold
                                        .withValues(alpha: 0.4),
                                  ],
                                ),
                                borderRadius: BorderRadius.vertical(
                                  top: d.cancels > 0
                                      ? Radius.zero
                                      : const Radius.circular(2),
                                  bottom: const Radius.circular(0),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 6),
            // Date labels (show every Nth to avoid overlap)
            SizedBox(
              height: 22,
              child: Row(
                children: List.generate(displayData.length, (i) {
                  final showLabel = displayData.length <= 14
                      ? true
                      : i % (displayData.length ~/ 7 + 1) == 0 ||
                          i == displayData.length - 1;
                  return Expanded(
                    child: showLabel
                        ? Text(
                            dateFmt.format(displayData[i].date),
                            textAlign: TextAlign.center,
                            style: AdminTheme.sans(
                              fontSize: 9,
                              color: AdminTheme.textTertiary,
                            ),
                          )
                        : const SizedBox.shrink(),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }
}
