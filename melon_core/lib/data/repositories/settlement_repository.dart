import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firestore_service.dart';
import '../models/settlement.dart';
import '../models/escrow.dart';

final settlementRepositoryProvider = Provider<SettlementRepository>((ref) {
  return SettlementRepository(ref.watch(firestoreServiceProvider));
});

/// 정산 목록 스트림
final settlementsStreamProvider = StreamProvider<List<Settlement>>((ref) {
  return ref.watch(settlementRepositoryProvider).getAllSettlements();
});

/// 에스크로 트랜잭션 스트림
final escrowTransactionsProvider =
    StreamProvider.family<List<EscrowTransaction>, String>((ref, sellerId) {
  return ref.watch(settlementRepositoryProvider).getTransactions(sellerId);
});

class SettlementRepository {
  final FirestoreService _fs;

  SettlementRepository(this._fs);

  CollectionReference get _settlements => _fs.instance.collection('settlements');
  CollectionReference get _escrowAccounts => _fs.instance.collection('escrowAccounts');
  CollectionReference get _escrowTransactions => _fs.instance.collection('escrowTransactions');

  // ── Settlements ──

  Stream<List<Settlement>> getAllSettlements() {
    return _settlements
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Settlement.fromFirestore(d)).toList());
  }

  Stream<List<Settlement>> getSettlementsByEvent(String eventId) {
    return _settlements
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .map((s) => s.docs.map((d) => Settlement.fromFirestore(d)).toList());
  }

  Future<String> createSettlement(Settlement settlement) async {
    final ref = await _settlements.add(settlement.toMap());
    return ref.id;
  }

  Future<void> updateSettlementStatus(
      String id, SettlementStatus status) async {
    final data = <String, dynamic>{'status': status.name};
    if (status == SettlementStatus.approved) {
      data['approvedAt'] = FieldValue.serverTimestamp();
    } else if (status == SettlementStatus.transferred) {
      data['transferredAt'] = FieldValue.serverTimestamp();
    }
    await _settlements.doc(id).update(data);
  }

  // ── Escrow Accounts ──

  Future<EscrowAccount?> getEscrowAccount(String sellerId) async {
    final doc = await _escrowAccounts.doc(sellerId).get();
    if (!doc.exists) return null;
    return EscrowAccount.fromFirestore(doc);
  }

  Future<void> ensureEscrowAccount(String sellerId) async {
    final doc = await _escrowAccounts.doc(sellerId).get();
    if (!doc.exists) {
      await _escrowAccounts.doc(sellerId).set({
        'balance': 0,
        'pendingAmount': 0,
        'totalDeposited': 0,
        'totalWithdrawn': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Escrow Transactions ──

  Stream<List<EscrowTransaction>> getTransactions(String sellerId) {
    return _escrowTransactions
        .where('sellerId', isEqualTo: sellerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => EscrowTransaction.fromFirestore(d)).toList());
  }

  Stream<List<EscrowTransaction>> getAllTransactions() {
    return _escrowTransactions
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => EscrowTransaction.fromFirestore(d)).toList());
  }

  /// 정산 요청 생성 (이벤트 기반)
  Future<void> requestSettlement({
    required String eventId,
    required String sellerId,
    required int totalSales,
    required int refundAmount,
    double feeRate = 0.10,
    Map<String, String>? bankInfo,
  }) async {
    final net = totalSales - refundAmount;
    final feeAmount = (net * feeRate).round();
    final settlementAmount = net - feeAmount;

    final settlement = Settlement(
      id: '',
      sellerId: sellerId,
      eventId: eventId,
      totalSales: totalSales,
      refundAmount: refundAmount,
      platformFeeRate: feeRate,
      platformFeeAmount: feeAmount,
      settlementAmount: settlementAmount,
      bankInfo: bankInfo,
      status: SettlementStatus.pending,
      requestedAt: DateTime.now(),
    );

    await _settlements.add(settlement.toMap());
  }

  /// 정산 승인 + 에스크로 트랜잭션 기록
  Future<void> approveSettlement(String settlementId) async {
    final doc = await _settlements.doc(settlementId).get();
    if (!doc.exists) return;
    final settlement = Settlement.fromFirestore(doc);

    await _fs.instance.runTransaction((tx) async {
      // 정산 승인
      tx.update(_settlements.doc(settlementId), {
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // 에스크로 잔액 차감
      final accountRef = _escrowAccounts.doc(settlement.sellerId);
      final accountDoc = await tx.get(accountRef);

      if (accountDoc.exists) {
        final balance = (accountDoc.data() as Map<String, dynamic>)['balance'] ?? 0;

        // 수수료 트랜잭션
        if (settlement.platformFeeAmount > 0) {
          final feeRef = _escrowTransactions.doc();
          tx.set(feeRef, {
            'sellerId': settlement.sellerId,
            'eventId': settlement.eventId,
            'type': 'platformFee',
            'amount': -settlement.platformFeeAmount,
            'balanceBefore': balance,
            'balanceAfter': balance - settlement.platformFeeAmount,
            'description': '플랫폼 수수료 (${(settlement.platformFeeRate * 100).round()}%)',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        final afterFee = balance - settlement.platformFeeAmount;

        // 정산 트랜잭션
        final settleTxRef = _escrowTransactions.doc();
        tx.set(settleTxRef, {
          'sellerId': settlement.sellerId,
          'eventId': settlement.eventId,
          'type': 'settlement',
          'amount': -settlement.settlementAmount,
          'balanceBefore': afterFee,
          'balanceAfter': afterFee - settlement.settlementAmount,
          'description': '정산 출금',
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 계정 잔액 업데이트
        tx.update(accountRef, {
          'balance': FieldValue.increment(
              -(settlement.platformFeeAmount + settlement.settlementAmount)),
          'pendingAmount':
              FieldValue.increment(-settlement.settlementAmount),
          'totalWithdrawn': FieldValue.increment(
              settlement.platformFeeAmount + settlement.settlementAmount),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// 입금 완료 처리
  Future<void> markTransferred(String settlementId) async {
    await _settlements.doc(settlementId).update({
      'status': 'transferred',
      'transferredAt': FieldValue.serverTimestamp(),
    });
  }
}
