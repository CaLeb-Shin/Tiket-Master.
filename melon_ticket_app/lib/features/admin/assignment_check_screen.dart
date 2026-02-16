import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/seat_repository.dart';
import '../../data/models/order.dart';
import '../../data/models/seat_block.dart';
import '../../services/functions_service.dart';

class AssignmentCheckScreen extends ConsumerWidget {
  final String eventId;

  const AssignmentCheckScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(eventId));
    final ordersAsync = ref.watch(orderRepositoryProvider).getPaidOrdersByEvent(eventId);
    final seatBlocksAsync = ref.watch(seatRepositoryProvider).getSeatBlocksByEvent(eventId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('배정 현황'),
        actions: [
          // 좌석 공개 버튼 (테스트용)
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: '좌석 공개 (테스트)',
            onPressed: () => _revealSeats(context, ref),
          ),
        ],
      ),
      body: eventAsync.when(
        data: (event) {
          if (event == null) {
            return const Center(child: Text('공연을 찾을 수 없습니다'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 공연 정보 카드
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(
                          label: '총 좌석',
                          value: '${event.totalSeats}석',
                        ),
                        _InfoRow(
                          label: '잔여 좌석',
                          value: '${event.availableSeats}석',
                        ),
                        _InfoRow(
                          label: '좌석 공개',
                          value: event.isSeatsRevealed ? '공개됨' : '비공개',
                          valueColor:
                              event.isSeatsRevealed ? Colors.green : Colors.orange,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 주문/배정 목록
                Text(
                  '결제 완료 주문 (배정 현황)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),

                StreamBuilder<List<Order>>(
                  stream: ordersAsync,
                  builder: (context, orderSnapshot) {
                    if (orderSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final orders = orderSnapshot.data ?? [];
                    if (orders.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('결제 완료된 주문이 없습니다')),
                        ),
                      );
                    }

                    return StreamBuilder<List<SeatBlock>>(
                      stream: seatBlocksAsync,
                      builder: (context, blockSnapshot) {
                        final seatBlocks = blockSnapshot.data ?? [];

                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: orders.length,
                          itemBuilder: (context, index) {
                            final order = orders[index];
                            final block = seatBlocks.firstWhere(
                              (b) => b.orderId == order.id,
                              orElse: () => SeatBlock(
                                id: '',
                                eventId: eventId,
                                orderId: order.id,
                                quantity: 0,
                                seatIds: [],
                                hidden: true,
                                assignedAt: DateTime.now(),
                              ),
                            );

                            return _OrderAssignmentCard(
                              order: order,
                              seatBlock: block,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('오류: $error')),
      ),
    );
  }

  Future<void> _revealSeats(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('좌석 공개'),
        content: const Text('모든 좌석을 공개하시겠습니까?\n(테스트용 - 실제로는 자동 실행됩니다)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('공개'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(functionsServiceProvider).revealSeatsForEvent(
            eventId: eventId,
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('좌석이 공개되었습니다')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
      }
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderAssignmentCard extends ConsumerWidget {
  final Order order;
  final SeatBlock seatBlock;

  const _OrderAssignmentCard({
    required this.order,
    required this.seatBlock,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('MM.dd HH:mm');
    final priceFormat = NumberFormat('#,###', 'ko_KR');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          '주문 #${order.id.substring(0, 8)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${order.quantity}매 | ${priceFormat.format(order.totalAmount)}원 | ${dateFormat.format(order.createdAt)}',
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: seatBlock.hidden ? Colors.orange : Colors.green,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            seatBlock.hidden ? '비공개' : '공개',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('사용자: ${order.userId}'),
                const SizedBox(height: 8),
                const Text(
                  '배정된 좌석:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                if (seatBlock.seatIds.isEmpty)
                  const Text('배정 정보 없음', style: TextStyle(color: Colors.red))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: seatBlock.seatIds
                        .map(
                          (seatId) => Chip(
                            label: Text(
                              seatId.substring(0, 8),
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
