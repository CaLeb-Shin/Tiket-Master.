import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:melon_core/app/theme.dart';

// 조건부 임포트: 웹에서만 dart:html 사용
import 'panorama_web_view_stub.dart'
    if (dart.library.html) 'panorama_web_view_web.dart' as platform;

/// 플랫폼별 파노라마 뷰어 (2-4b)
/// - 웹: pannellum.js (HtmlElementView)
/// - 모바일: Flutter PanoramaViewer 패키지
class PanoramaWebView extends StatelessWidget {
  final String imageUrl;
  final bool is180;
  final String viewerId;

  const PanoramaWebView({
    super.key,
    required this.imageUrl,
    this.is180 = false,
    this.viewerId = 'pannellum-default',
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return platform.buildWebPanorama(
        imageUrl: imageUrl,
        is180: is180,
        viewerId: viewerId,
      );
    }

    // 모바일: Flutter PanoramaViewer (기존 패키지)
    return platform.buildNativePanorama(
      imageUrl: imageUrl,
      is180: is180,
    );
  }
}
