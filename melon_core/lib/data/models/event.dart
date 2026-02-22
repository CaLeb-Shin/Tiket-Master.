import 'package:cloud_firestore/cloud_firestore.dart';
import 'discount_policy.dart';

/// 공연 이벤트 모델
class Event {
  final String id;
  final String venueId;
  final String title;
  final String description;
  final String? imageUrl;
  final DateTime startAt; // 공연 시작 시간
  final DateTime revealAt; // 좌석 공개 시간 (시작 1시간 전)
  final DateTime saleStartAt; // 판매 시작
  final DateTime saleEndAt; // 판매 종료
  final int price; // 기본 가격 (원)
  final int maxTicketsPerOrder; // 1회 최대 구매 수량
  final int totalSeats; // 총 좌석 수
  final int availableSeats; // 남은 좌석 수
  final EventStatus status;
  final DateTime createdAt;
  
  // 추가 상세 정보
  final String? category; // 카테고리 (콘서트, 뮤지컬, 연극 등)
  final String? venueName; // 공연장 이름
  final String? venueAddress; // 공연장 주소
  final int? runningTime; // 러닝타임 (분)
  final String? ageLimit; // 관람등급
  final String? cast; // 출연진
  final String? organizer; // 주최
  final String? planner; // 기획
  final String? notice; // 예매 유의사항
  final String? discount; // 할인정보 (레거시 텍스트)
  final Map<String, int>? priceByGrade; // 등급별 가격 (VIP, R, S, A 등)
  final List<DiscountPolicy>? discountPolicies; // 구조화된 할인 정책
  final bool showRemainingSeats; // 잔여석 표시 여부
  final List<String>? pamphletUrls; // 팜플렛 이미지 URL 목록 (최대 8장)
  final String? inquiryInfo; // 예매 관련 문의 (예: 전화번호, 담당자 등)
  final bool has360View; // 360° 좌석뷰 보유 여부
  final List<String> tags; // 커스텀 태그 목록 (예: 내한, 단독, 앵콜 등)
  final String? seriesId; // 시리즈(다회공연) ID — 같은 시리즈에 속하는 이벤트는 동일
  final int sessionNumber; // 회차 번호 (1부터 시작, 단일 공연이면 1)
  final int totalSessions; // 총 회차 수
  final bool isStanding; // 비지정석(스탠딩) 공연 여부

  Event({
    required this.id,
    required this.venueId,
    required this.title,
    required this.description,
    this.imageUrl,
    required this.startAt,
    required this.revealAt,
    required this.saleStartAt,
    required this.saleEndAt,
    required this.price,
    required this.maxTicketsPerOrder,
    required this.totalSeats,
    required this.availableSeats,
    required this.status,
    required this.createdAt,
    this.category,
    this.venueName,
    this.venueAddress,
    this.runningTime,
    this.ageLimit,
    this.cast,
    this.organizer,
    this.planner,
    this.notice,
    this.discount,
    this.priceByGrade,
    this.discountPolicies,
    this.showRemainingSeats = true,
    this.pamphletUrls,
    this.inquiryInfo,
    this.has360View = false,
    this.tags = const [],
    this.seriesId,
    this.sessionNumber = 1,
    this.totalSessions = 1,
    this.isStanding = false,
  });

  /// 좌석 공개 여부
  bool get isSeatsRevealed => DateTime.now().isAfter(revealAt);

  /// 판매 중 여부
  bool get isOnSale {
    final now = DateTime.now();
    return now.isAfter(saleStartAt) && now.isBefore(saleEndAt) && status == EventStatus.active;
  }

  factory Event.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Event(
      id: doc.id,
      venueId: data['venueId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      imageUrl: data['imageUrl'],
      startAt: (data['startAt'] as Timestamp).toDate(),
      revealAt: (data['revealAt'] as Timestamp).toDate(),
      saleStartAt: (data['saleStartAt'] as Timestamp).toDate(),
      saleEndAt: (data['saleEndAt'] as Timestamp).toDate(),
      price: data['price'] ?? 0,
      maxTicketsPerOrder: data['maxTicketsPerOrder'] ?? 4,
      totalSeats: data['totalSeats'] ?? 0,
      availableSeats: data['availableSeats'] ?? 0,
      status: EventStatus.fromString(data['status']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category: data['category'],
      venueName: data['venueName'],
      venueAddress: data['venueAddress'],
      runningTime: data['runningTime'],
      ageLimit: data['ageLimit'],
      cast: data['cast'],
      organizer: data['organizer'],
      planner: data['planner'],
      notice: data['notice'],
      discount: data['discount'],
      priceByGrade: data['priceByGrade'] != null
          ? Map<String, int>.from(data['priceByGrade'])
          : null,
      discountPolicies: data['discountPolicies'] != null
          ? (data['discountPolicies'] as List)
              .map((e) => DiscountPolicy.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : null,
      showRemainingSeats: data['showRemainingSeats'] ?? true,
      pamphletUrls: data['pamphletUrls'] != null
          ? List<String>.from(data['pamphletUrls'])
          : null,
      inquiryInfo: data['inquiryInfo'],
      has360View: data['has360View'] ?? false,
      tags: data['tags'] != null ? List<String>.from(data['tags']) : const [],
      seriesId: data['seriesId'],
      sessionNumber: data['sessionNumber'] ?? 1,
      totalSessions: data['totalSessions'] ?? 1,
      isStanding: data['isStanding'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'venueId': venueId,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'startAt': Timestamp.fromDate(startAt),
      'revealAt': Timestamp.fromDate(revealAt),
      'saleStartAt': Timestamp.fromDate(saleStartAt),
      'saleEndAt': Timestamp.fromDate(saleEndAt),
      'price': price,
      'maxTicketsPerOrder': maxTicketsPerOrder,
      'totalSeats': totalSeats,
      'availableSeats': availableSeats,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'category': category,
      'venueName': venueName,
      'venueAddress': venueAddress,
      'runningTime': runningTime,
      'ageLimit': ageLimit,
      'cast': cast,
      'organizer': organizer,
      'planner': planner,
      'notice': notice,
      'discount': discount,
      'priceByGrade': priceByGrade,
      'discountPolicies': discountPolicies?.map((e) => e.toMap()).toList(),
      'showRemainingSeats': showRemainingSeats,
      'pamphletUrls': pamphletUrls,
      'inquiryInfo': inquiryInfo,
      'has360View': has360View,
      if (tags.isNotEmpty) 'tags': tags,
      if (seriesId != null) 'seriesId': seriesId,
      'sessionNumber': sessionNumber,
      'totalSessions': totalSessions,
      'isStanding': isStanding,
    };
  }

  /// 다회 공연 여부
  bool get isMultiSession => totalSessions > 1;
}

enum EventStatus {
  draft,
  active,
  soldOut,
  canceled,
  completed;

  static EventStatus fromString(String? value) {
    return EventStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => EventStatus.draft,
    );
  }
}
