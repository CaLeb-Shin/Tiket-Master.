import 'dart:convert';
import 'dart:js_interop';

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

  /// 도로명 주소 + 건물명
  String get fullAddress {
    final road = roadAddress.isNotEmpty ? roadAddress : address;
    if (buildingName.isNotEmpty) return '$road ($buildingName)';
    return road;
  }
}

@JS('openKakaoPostcode')
external JSPromise<JSString> _openKakaoPostcode();

/// 카카오 주소 검색 팝업을 열고 결과를 반환한다.
/// 사용자가 취소하면 null을 반환한다.
Future<KakaoAddressResult?> openKakaoPostcode() async {
  try {
    final result = (await _openKakaoPostcode().toDart).toDart;
    if (result.isEmpty) return null;

    final data = jsonDecode(result) as Map<String, dynamic>;
    return KakaoAddressResult(
      zonecode: data['zonecode'] ?? '',
      address: data['address'] ?? '',
      roadAddress: data['roadAddress'] ?? '',
      jibunAddress: data['jibunAddress'] ?? '',
      buildingName: data['buildingName'] ?? '',
      sido: data['sido'] ?? '',
      sigungu: data['sigungu'] ?? '',
      bname: data['bname'] ?? '',
    );
  } catch (_) {
    return null;
  }
}
