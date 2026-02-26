/// 모바일(dart:io) 환경용 스텁 - 카카오 주소 검색은 웹에서만 지원
class KakaoAddressResult {
  final String zonecode;
  final String address;
  final String roadAddress;
  final String jibunAddress;
  final String buildingName;
  final String sido;
  final String sigungu;
  final String bname;

  const KakaoAddressResult({
    required this.zonecode,
    required this.address,
    required this.roadAddress,
    required this.jibunAddress,
    required this.buildingName,
    required this.sido,
    required this.sigungu,
    required this.bname,
  });

  String get fullAddress {
    final road = roadAddress.isNotEmpty ? roadAddress : address;
    if (buildingName.isNotEmpty) return '$road ($buildingName)';
    return road;
  }
}

Future<KakaoAddressResult?> openKakaoPostcode() async => null;
