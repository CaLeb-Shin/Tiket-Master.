import 'package:cloud_firestore/cloud_firestore.dart';

/// 에스크로 계정
class EscrowAccount {
  final String id; // = sellerId
  final int balance; // 예치 잔액
  final int pendingAmount; // 정산 대기금
  final int totalDeposited; // 총 입금액
  final int totalWithdrawn; // 총 출금액
  final DateTime updatedAt;

  EscrowAccount({
    required this.id,
    this.balance = 0,
    this.pendingAmount = 0,
    this.totalDeposited = 0,
    this.totalWithdrawn = 0,
    required this.updatedAt,
  });

  factory EscrowAccount.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EscrowAccount(
      id: doc.id,
      balance: data['balance'] ?? 0,
      pendingAmount: data['pendingAmount'] ?? 0,
      totalDeposited: data['totalDeposited'] ?? 0,
      totalWithdrawn: data['totalWithdrawn'] ?? 0,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'balance': balance,
      'pendingAmount': pendingAmount,
      'totalDeposited': totalDeposited,
      'totalWithdrawn': totalWithdrawn,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}

/// 에스크로 트랜잭션
class EscrowTransaction {
  final String id;
  final String sellerId;
  final String? orderId;
  final String? eventId;
  final EscrowTxType type;
  final int amount; // 양수 = 입금, 음수 = 출금
  final int balanceBefore;
  final int balanceAfter;
  final String? description;
  final DateTime createdAt;

  EscrowTransaction({
    required this.id,
    required this.sellerId,
    this.orderId,
    this.eventId,
    required this.type,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    this.description,
    required this.createdAt,
  });

  factory EscrowTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EscrowTransaction(
      id: doc.id,
      sellerId: data['sellerId'] ?? '',
      orderId: data['orderId'],
      eventId: data['eventId'],
      type: EscrowTxType.fromString(data['type']),
      amount: data['amount'] ?? 0,
      balanceBefore: data['balanceBefore'] ?? 0,
      balanceAfter: data['balanceAfter'] ?? 0,
      description: data['description'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sellerId': sellerId,
      if (orderId != null) 'orderId': orderId,
      if (eventId != null) 'eventId': eventId,
      'type': type.name,
      'amount': amount,
      'balanceBefore': balanceBefore,
      'balanceAfter': balanceAfter,
      'description': description,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

enum EscrowTxType {
  deposit,     // 결제 입금
  refund,      // 환불 출금
  settlement,  // 정산 출금
  platformFee, // 수수료 차감
  topup;       // 수동 충전

  static EscrowTxType fromString(String? value) {
    return EscrowTxType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => EscrowTxType.deposit,
    );
  }

  String get displayName {
    switch (this) {
      case EscrowTxType.deposit:
        return '입금';
      case EscrowTxType.refund:
        return '환불';
      case EscrowTxType.settlement:
        return '정산';
      case EscrowTxType.platformFee:
        return '수수료';
      case EscrowTxType.topup:
        return '충전';
    }
  }
}
