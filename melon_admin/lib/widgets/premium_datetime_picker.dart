import 'package:flutter/material.dart';
import '../app/admin_theme.dart';

/// 프리미엄 DateTime 피커 — AdminTheme 다크 골드 스타일
/// 캘린더 + 시간 휠을 하나의 다이얼로그에 통합
Future<DateTime?> showPremiumDateTimePicker({
  required BuildContext context,
  required DateTime initialDateTime,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showGeneralDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'DateTimePicker',
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (context, anim, secondAnim, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
    pageBuilder: (context, anim, secondAnim) {
      return Center(
        child: _PremiumDateTimePicker(
          initialDateTime: initialDateTime,
          firstDate:
              firstDate ?? DateTime.now().subtract(const Duration(days: 1)),
          lastDate:
              lastDate ?? DateTime.now().add(const Duration(days: 730)),
        ),
      );
    },
  );
}

class _PremiumDateTimePicker extends StatefulWidget {
  final DateTime initialDateTime;
  final DateTime firstDate;
  final DateTime lastDate;

  const _PremiumDateTimePicker({
    required this.initialDateTime,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_PremiumDateTimePicker> createState() => _PremiumDateTimePickerState();
}

class _PremiumDateTimePickerState extends State<_PremiumDateTimePicker> {
  late DateTime _selectedDate;
  late int _selectedHour;
  late int _selectedMinute;
  late DateTime _displayMonth;

  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  static const _weekDays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.initialDateTime.year,
      widget.initialDateTime.month,
      widget.initialDateTime.day,
    );
    _selectedHour = widget.initialDateTime.hour;
    _selectedMinute = widget.initialDateTime.minute;
    _displayMonth = DateTime(_selectedDate.year, _selectedDate.month);
    _hourController = FixedExtentScrollController(initialItem: _selectedHour);
    _minuteController =
        FixedExtentScrollController(initialItem: _selectedMinute);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _prevMonth() {
    setState(() {
      _displayMonth = DateTime(
        _displayMonth.year,
        _displayMonth.month - 1,
      );
    });
  }

  void _nextMonth() {
    setState(() {
      _displayMonth = DateTime(
        _displayMonth.year,
        _displayMonth.month + 1,
      );
    });
  }

  int _daysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  /// 월요일 = 0 ~ 일요일 = 6 (한국식)
  int _firstWeekdayOffset(DateTime month) {
    final wd = DateTime(month.year, month.month, 1).weekday; // 1=Mon, 7=Sun
    return wd - 1;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime d) => _isSameDay(d, DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          color: AdminTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AdminTheme.gold.withValues(alpha: 0.15),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: AdminTheme.gold.withValues(alpha: 0.05),
              blurRadius: 60,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildCalendar(),
            _buildTimePicker(),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  // ─── Header: Selected date summary ───
  Widget _buildHeader() {
    final result = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedHour,
      _selectedMinute,
    );
    final weekDay = ['', '월', '화', '수', '목', '금', '토', '일'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AdminTheme.gold.withValues(alpha: 0.12),
            AdminTheme.gold.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(
            color: AdminTheme.gold.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SELECT DATE & TIME',
            style: AdminTheme.label(fontSize: 9, color: AdminTheme.gold),
          ),
          const SizedBox(height: 8),
          Text(
            '${result.year}년 ${result.month}월 ${result.day}일 (${weekDay[result.weekday]})',
            style: AdminTheme.serif(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: AdminTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')}',
            style: AdminTheme.sans(
              fontSize: 28,
              fontWeight: FontWeight.w300,
              color: AdminTheme.gold,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Calendar grid ───
  Widget _buildCalendar() {
    final daysInMonth = _daysInMonth(_displayMonth);
    final offset = _firstWeekdayOffset(_displayMonth);
    final prevMonth = DateTime(_displayMonth.year, _displayMonth.month - 1);
    final prevDays = _daysInMonth(prevMonth);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          // Month navigation
          Row(
            children: [
              _monthNavButton(Icons.chevron_left, _prevMonth),
              Expanded(
                child: Text(
                  '${_displayMonth.year}년 ${_displayMonth.month}월',
                  textAlign: TextAlign.center,
                  style: AdminTheme.serif(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              _monthNavButton(Icons.chevron_right, _nextMonth),
            ],
          ),
          const SizedBox(height: 12),
          // Weekday headers
          Row(
            children: _weekDays.map((d) {
              final isWeekend = d == '토' || d == '일';
              return Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: AdminTheme.label(
                      fontSize: 9,
                      color: isWeekend
                          ? AdminTheme.gold.withValues(alpha: 0.5)
                          : AdminTheme.textTertiary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          // Day grid
          _buildDayGrid(daysInMonth, offset, prevDays),
        ],
      ),
    );
  }

  Widget _monthNavButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AdminTheme.border,
            width: 0.5,
          ),
        ),
        child: Icon(icon, size: 16, color: AdminTheme.textSecondary),
      ),
    );
  }

  Widget _buildDayGrid(int daysInMonth, int offset, int prevDays) {
    final rows = <Widget>[];
    var dayIndex = 1;
    var nextMonthDay = 1;

    for (var row = 0; row < 6; row++) {
      if (dayIndex > daysInMonth && row > 0) break;
      final cells = <Widget>[];
      for (var col = 0; col < 7; col++) {
        final idx = row * 7 + col;
        if (idx < offset) {
          // Previous month
          final d = prevDays - offset + idx + 1;
          cells.add(_dayCell(d, isOtherMonth: true));
        } else if (dayIndex <= daysInMonth) {
          final day = dayIndex;
          final date =
              DateTime(_displayMonth.year, _displayMonth.month, day);
          final isSelected = _isSameDay(date, _selectedDate);
          final isToday = _isToday(date);
          cells.add(_dayCell(
            day,
            isSelected: isSelected,
            isToday: isToday,
            onTap: () => setState(() => _selectedDate = date),
          ));
          dayIndex++;
        } else {
          // Next month
          cells.add(_dayCell(nextMonthDay, isOtherMonth: true));
          nextMonthDay++;
        }
      }
      rows.add(Row(children: cells));
    }

    return Column(children: rows);
  }

  Widget _dayCell(
    int day, {
    bool isSelected = false,
    bool isToday = false,
    bool isOtherMonth = false,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? AdminTheme.gold
                  : isToday
                      ? AdminTheme.gold.withValues(alpha: 0.1)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(isSelected ? 16 : 4),
              border: isToday && !isSelected
                  ? Border.all(
                      color: AdminTheme.gold.withValues(alpha: 0.3),
                      width: 0.5,
                    )
                  : null,
            ),
            child: Text(
              '$day',
              style: AdminTheme.sans(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AdminTheme.onAccent
                    : isOtherMonth
                        ? AdminTheme.textTertiary
                        : AdminTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Time Picker Wheels ───
  Widget _buildTimePicker() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AdminTheme.border,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            'TIME',
            style: AdminTheme.label(fontSize: 9, color: AdminTheme.textTertiary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Hour wheel
                SizedBox(
                  width: 64,
                  child: _buildWheel(
                    controller: _hourController,
                    itemCount: 24,
                    onChanged: (v) => setState(() => _selectedHour = v),
                    labelBuilder: (i) => i.toString().padLeft(2, '0'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    ':',
                    style: AdminTheme.sans(
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                      color: AdminTheme.gold,
                    ),
                  ),
                ),
                // Minute wheel
                SizedBox(
                  width: 64,
                  child: _buildWheel(
                    controller: _minuteController,
                    itemCount: 60,
                    onChanged: (v) => setState(() => _selectedMinute = v),
                    labelBuilder: (i) => i.toString().padLeft(2, '0'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required ValueChanged<int> onChanged,
    required String Function(int) labelBuilder,
  }) {
    return Stack(
      children: [
        // Selection highlight
        Positioned.fill(
          child: Align(
            alignment: Alignment.center,
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AdminTheme.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AdminTheme.gold.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
            ),
          ),
        ),
        // Wheel
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: 36,
          diameterRatio: 1.5,
          perspective: 0.003,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: onChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: itemCount,
            builder: (context, index) {
              final isSelected = (controller.hasClients &&
                      controller.selectedItem == index) ||
                  (!controller.hasClients &&
                      controller.initialItem == index);
              return Center(
                child: Text(
                  labelBuilder(index),
                  style: AdminTheme.sans(
                    fontSize: isSelected ? 20 : 14,
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.w300,
                    color: isSelected
                        ? AdminTheme.gold
                        : AdminTheme.textTertiary,
                    letterSpacing: 2,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Action buttons ───
  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(null),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AdminTheme.border,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  '취소',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AdminTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () {
                final result = DateTime(
                  _selectedDate.year,
                  _selectedDate.month,
                  _selectedDate.day,
                  _selectedHour,
                  _selectedMinute,
                );
                Navigator.of(context).pop(result);
              },
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AdminTheme.goldGradient,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: AdminTheme.gold.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  '확인',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.onAccent,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
