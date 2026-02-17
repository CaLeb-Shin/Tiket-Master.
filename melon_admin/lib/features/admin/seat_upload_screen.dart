import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shad;
import 'package:melon_core/data/repositories/seat_repository.dart';
import 'package:melon_core/data/repositories/event_repository.dart';

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

  @override
  void initState() {
    super.initState();
    // 샘플 CSV 데이터
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

      // 이벤트의 totalSeats, availableSeats 업데이트
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('좌석 등록'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안내
            shad.Card(
              padding: const EdgeInsets.all(16),
              filled: true,
              fillColor: Colors.blue[50],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        'CSV 형식 안내',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '첫 줄: block,floor,row,number (헤더)\n'
                    '데이터: A,1층,1,1 (구역,층,열,번호)\n'
                    'row는 생략 가능 (A,1층,,1)',
                    style: TextStyle(color: Colors.blue[700], fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // CSV 입력
            Text(
              'CSV 데이터',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _csvController,
              decoration: const InputDecoration(
                hintText: 'CSV 데이터를 붙여넣으세요',
                border: OutlineInputBorder(),
              ),
              maxLines: 15,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),

            // 버튼들
            Row(
              children: [
                Expanded(
                  child: shad.Button.outline(
                    onPressed: _preview,
                    child: const Text('미리보기'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: shad.Button.primary(
                    onPressed: _isLoading ? null : _uploadSeats,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('좌석 등록'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 미리보기 결과
            if (_previewText != null)
              shad.Card(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '미리보기',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(_previewText!),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
