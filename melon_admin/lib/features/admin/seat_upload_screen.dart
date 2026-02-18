import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shad;
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/repositories/event_repository.dart';

// =============================================================================
// 좌석 등록 화면 (Editorial / Luxury Magazine Admin Design)
// =============================================================================

class SeatUploadScreen extends ConsumerStatefulWidget {
  final String eventId;

  const SeatUploadScreen({super.key, required this.eventId});

  @override
  ConsumerState<SeatUploadScreen> createState() => _SeatUploadScreenState();
}

class _SeatUploadScreenState extends ConsumerState<SeatUploadScreen> {
  final _csvController = TextEditingController();
  bool _isLoading = false;
  String? _previewText;
  List<Map<String, dynamic>> _previewSeats = [];

  @override
  void initState() {
    super.initState();
    _csvController.text = '''block,floor,row,number
A,1층,1,1
A,1층,1,2
A,1층,1,3
A,1층,1,4
A,1층,1,5
A,1층,2,1
A,1층,2,2
A,1층,2,3
A,1층,2,4
A,1층,2,5
B,1층,1,1
B,1층,1,2
B,1층,1,3
B,1층,1,4
B,1층,1,5''';
  }

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _parseCsv(String csv) {
    final lines = csv.trim().split('\n');
    if (lines.length < 2) return [];

    final headers = lines[0].split(',').map((h) => h.trim()).toList();
    final seats = <Map<String, dynamic>>[];

    for (var i = 1; i < lines.length; i++) {
      final values = lines[i].split(',').map((v) => v.trim()).toList();
      if (values.length != headers.length) continue;

      final seat = <String, dynamic>{};
      for (var j = 0; j < headers.length; j++) {
        final key = headers[j];
        final value = values[j];
        if (key == 'number') {
          seat[key] = int.tryParse(value) ?? 0;
        } else {
          seat[key] = value;
        }
      }
      seats.add(seat);
    }

    return seats;
  }

  void _preview() {
    final seats = _parseCsv(_csvController.text);
    setState(() {
      _previewSeats = seats;
      _previewText = '총 ${seats.length}개 좌석\n\n'
          '처음 5개:\n${seats.take(5).map((s) => '${s['block']}구역 ${s['floor']} ${s['row'] ?? ''}열 ${s['number']}번').join('\n')}';
    });
  }

  Future<void> _uploadSeats() async {
    final seats = _parseCsv(_csvController.text);
    if (seats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효한 좌석 데이터가 없습니다')),
      );
      return;
    }

    if (seats.length > 1500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최대 1500석까지만 등록 가능합니다')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final count = await ref
          .read(seatRepositoryProvider)
          .createSeatsFromCsv(widget.eventId, seats);

      await ref.read(eventRepositoryProvider).updateEvent(widget.eventId, {
        'totalSeats': count,
        'availableSeats': count,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count개 좌석이 등록되었습니다')),
        );
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal:
                    MediaQuery.of(context).size.width >= 900 ? 40 : 20,
                vertical: 32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: _buildContent(),
                ),
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APP BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 4,
        right: 16,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.95),
        border: const Border(
          bottom: BorderSide(
            color: AppTheme.border,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/');
              }
            },
            icon: const Icon(Icons.west,
                color: AppTheme.textPrimary, size: 20),
          ),
          const SizedBox(width: 4),
          Text(
            'Editorial Admin',
            style: AppTheme.serif(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _uploadSeats,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: AppTheme.onAccent,
            disabledBackgroundColor: AppTheme.sage.withValues(alpha: 0.3),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.onAccent,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'UPLOAD SEATS',
                      style: AppTheme.serif(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onAccent,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Page Title ──
        Text(
          '좌석 등록',
          style: AppTheme.serif(
            fontSize: 28,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 12,
          height: 1,
          color: AppTheme.gold,
        ),
        const SizedBox(height: 40),

        // ── Section 1: CSV 형식 안내 ──
        _sectionHeader('형식 안내'),
        const SizedBox(height: 20),
        shad.Card(
          padding: const EdgeInsets.all(20),
          borderRadius: BorderRadius.circular(2),
          borderWidth: 0.5,
          borderColor: AppTheme.sage.withValues(alpha: 0.15),
          fillColor: AppTheme.surface,
          filled: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: AppTheme.sage.withValues(alpha: 0.6)),
                  const SizedBox(width: 8),
                  Text(
                    'CSV FORMAT',
                    style: AppTheme.label(
                      fontSize: 10,
                      color: AppTheme.sage,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 0.5,
                color: AppTheme.sage.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 12),
              Text(
                '첫 줄: block,floor,row,number (헤더)',
                style: AppTheme.sans(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.8,
                ),
              ),
              Text(
                '데이터: A,1층,1,1 (구역,층,열,번호)',
                style: AppTheme.sans(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.8,
                ),
              ),
              Text(
                'row는 생략 가능 (A,1층,,1)',
                style: AppTheme.sans(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),

        // ── Section 2: CSV 데이터 입력 ──
        _sectionHeader('CSV 데이터'),
        const SizedBox(height: 20),
        Text(
          'CSV DATA',
          style: AppTheme.label(
            fontSize: 10,
            color: AppTheme.sage,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: AppTheme.sage.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: TextFormField(
            controller: _csvController,
            decoration: InputDecoration(
              hintText: 'CSV 데이터를 붙여넣으세요',
              hintStyle: AppTheme.sans(
                fontSize: 13,
                color: AppTheme.sage.withValues(alpha: 0.5),
              ),
              filled: false,
              contentPadding: const EdgeInsets.all(16),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            maxLines: 15,
            style: AppTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Preview Button ──
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _preview,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.gold,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
                side: BorderSide(
                  color: AppTheme.gold.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
            ),
            child: Text(
              'PREVIEW',
              style: AppTheme.label(
                fontSize: 10,
                color: AppTheme.gold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Section 3: 미리보기 결과 ──
        if (_previewText != null) ...[
          _sectionHeader('미리보기'),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: AppTheme.sage.withValues(alpha: 0.15),
                width: 0.5,
              ),
              boxShadow: AppShadows.small,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        '${_previewSeats.length} SEATS',
                        style: AppTheme.label(
                          fontSize: 10,
                          color: AppTheme.gold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'PREVIEW RESULT',
                      style: AppTheme.label(
                        fontSize: 9,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  height: 0.5,
                  color: AppTheme.sage.withValues(alpha: 0.15),
                ),
                const SizedBox(height: 16),

                // ── Preview table ──
                if (_previewSeats.isNotEmpty) ...[
                  // Table header
                  Row(
                    children: [
                      _tableHeader('BLOCK', flex: 2),
                      _tableHeader('FLOOR', flex: 2),
                      _tableHeader('ROW', flex: 1),
                      _tableHeader('NO.', flex: 1),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    height: 0.5,
                    color: AppTheme.sage.withValues(alpha: 0.1),
                  ),
                  // Table rows (first 5)
                  ..._previewSeats.take(5).map((seat) => Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: AppTheme.sage.withValues(alpha: 0.08),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            _tableCell('${seat['block']}', flex: 2),
                            _tableCell('${seat['floor']}', flex: 2),
                            _tableCell('${seat['row'] ?? '-'}', flex: 1),
                            _tableCell('${seat['number']}', flex: 1),
                          ],
                        ),
                      )),
                  if (_previewSeats.length > 5) ...[
                    const SizedBox(height: 12),
                    Text(
                      '... 외 ${_previewSeats.length - 5}개',
                      style: AppTheme.sans(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 100),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION HEADER — Serif italic + thin line
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Text(
          title,
          style: AppTheme.serif(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            height: 0.5,
            color: AppTheme.sage.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TABLE HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _tableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: AppTheme.label(
          fontSize: 9,
          color: AppTheme.sage,
        ),
      ),
    );
  }

  Widget _tableCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: AppTheme.sans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}
