// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:melon_core/app/theme.dart';

/// 웹 전용: pannellum.js 기반 360° 뷰어
Widget buildWebPanorama({
  required String imageUrl,
  required bool is180,
  required String viewerId,
}) {
  return _PannellumWidget(
    imageUrl: imageUrl,
    is180: is180,
    viewerId: viewerId,
  );
}

/// 웹에서도 폴백으로 Image.network 사용 (PanoramaViewer 웹 미지원 시)
Widget buildNativePanorama({
  required String imageUrl,
  required bool is180,
}) {
  return buildWebPanorama(
    imageUrl: imageUrl,
    is180: is180,
    viewerId: 'pannellum-native-${imageUrl.hashCode}',
  );
}

class _PannellumWidget extends StatefulWidget {
  final String imageUrl;
  final bool is180;
  final String viewerId;

  const _PannellumWidget({
    required this.imageUrl,
    required this.is180,
    required this.viewerId,
  });

  @override
  State<_PannellumWidget> createState() => _PannellumWidgetState();
}

class _PannellumWidgetState extends State<_PannellumWidget> {
  late String _elementId;

  @override
  void initState() {
    super.initState();
    _elementId = 'pannellum-${widget.viewerId}-${DateTime.now().millisecondsSinceEpoch}';

    // HtmlElementView 팩토리 등록
    ui_web.platformViewRegistry.registerViewFactory(_elementId, (int viewId) {
      final div = html.DivElement()
        ..id = _elementId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.background = '#0B0B0F';

      // DOM 삽입 후 pannellum 초기화 (약간의 딜레이 필요)
      Future.delayed(const Duration(milliseconds: 100), () {
        js.context.callMethod('createPannellumViewer', [
          _elementId,
          widget.imageUrl,
          widget.is180,
        ]);
      });

      return div;
    });
  }

  @override
  void dispose() {
    js.context.callMethod('destroyPannellumViewer', [_elementId]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _elementId);
  }
}
