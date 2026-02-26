/// 사용자 마일리지 (users 문서 내 mileage 서브필드)
class Mileage {
  final int balance;
  final MileageTier tier;
  final int totalEarned;

  Mileage({
    this.balance = 0,
    this.tier = MileageTier.bronze,
    this.totalEarned = 0,
  });

  factory Mileage.fromMap(Map<String, dynamic>? data) {
    if (data == null) return Mileage();
    return Mileage(
      balance: data['balance'] ?? 0,
      tier: MileageTier.fromString(data['tier']),
      totalEarned: data['totalEarned'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'balance': balance,
      'tier': tier.name,
      'totalEarned': totalEarned,
    };
  }
}

/// 마일리지 등급
enum MileageTier {
  bronze,   // 0~4999
  silver,   // 5000~14999
  gold,     // 15000~29999
  platinum; // 30000~

  static MileageTier fromString(String? value) {
    return MileageTier.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MileageTier.bronze,
    );
  }

  String get displayName {
    switch (this) {
      case MileageTier.bronze:
        return 'Bronze';
      case MileageTier.silver:
        return 'Silver';
      case MileageTier.gold:
        return 'Gold';
      case MileageTier.platinum:
        return 'Platinum';
    }
  }

  /// 등급 진입 최소 마일리지
  int get minPoints {
    switch (this) {
      case MileageTier.bronze:
        return 0;
      case MileageTier.silver:
        return 5000;
      case MileageTier.gold:
        return 15000;
      case MileageTier.platinum:
        return 30000;
    }
  }

  /// 구매 마일리지 적립률 (등급별 차등)
  double get earnRate {
    switch (this) {
      case MileageTier.bronze:
        return 0.03; // 3%
      case MileageTier.silver:
        return 0.05; // 5%
      case MileageTier.gold:
        return 0.07; // 7%
      case MileageTier.platinum:
        return 0.10; // 10%
    }
  }

  /// 다음 등급 (Platinum이면 null)
  MileageTier? get next {
    switch (this) {
      case MileageTier.bronze:
        return MileageTier.silver;
      case MileageTier.silver:
        return MileageTier.gold;
      case MileageTier.gold:
        return MileageTier.platinum;
      case MileageTier.platinum:
        return null;
    }
  }

  /// totalEarned 기반 등급 계산
  static MileageTier fromTotalEarned(int totalEarned) {
    if (totalEarned >= 30000) return MileageTier.platinum;
    if (totalEarned >= 15000) return MileageTier.gold;
    if (totalEarned >= 5000) return MileageTier.silver;
    return MileageTier.bronze;
  }
}
