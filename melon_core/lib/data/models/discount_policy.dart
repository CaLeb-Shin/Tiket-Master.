/// 할인 정책 모델 (놀티켓 스타일)
class DiscountPolicy {
  /// 정책 이름 (e.g. "2매 이상 구매시 20%", "국가유공자(동반1인) 50%")
  final String name;

  /// 할인 유형: "bulk" (수량 할인) | "special" (대상 할인)
  final String type;

  /// 최소 수량 (bulk: 2,3,4… / special: 1)
  final int minQuantity;

  /// 할인율 0.0 ~ 1.0 (20% = 0.2)
  final double discountRate;

  /// 부가 설명 (e.g. "2매 이상만 예매 가능. 전체취소만 가능.")
  final String? description;

  /// 적용 좌석 등급 (null = 전체 등급 적용)
  final List<String>? applicableGrades;

  const DiscountPolicy({
    required this.name,
    required this.type,
    required this.minQuantity,
    required this.discountRate,
    this.description,
    this.applicableGrades,
  });

  /// 할인 적용 가격 계산
  int discountedPrice(int basePrice) {
    return (basePrice * (1 - discountRate)).round();
  }

  factory DiscountPolicy.fromMap(Map<String, dynamic> map) {
    return DiscountPolicy(
      name: map['name'] ?? '',
      type: map['type'] ?? 'bulk',
      minQuantity: map['minQuantity'] ?? 1,
      discountRate: (map['discountRate'] as num?)?.toDouble() ?? 0.0,
      description: map['description'],
      applicableGrades: map['applicableGrades'] != null
          ? List<String>.from(map['applicableGrades'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'minQuantity': minQuantity,
      'discountRate': discountRate,
      if (description != null) 'description': description,
      if (applicableGrades != null) 'applicableGrades': applicableGrades,
    };
  }
}
