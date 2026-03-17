import 'package:flutter/material.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:melon_core/app/theme.dart';

/// 모바일/데스크톱 구현 (기본 폴백)
Widget buildWebPanorama({
  required String imageUrl,
  required bool is180,
  required String viewerId,
}) {
  // 모바일에서도 PanoramaViewer 사용
  return buildNativePanorama(imageUrl: imageUrl, is180: is180);
}

Widget buildNativePanorama({
  required String imageUrl,
  required bool is180,
}) {
  return PanoramaViewer(
    sensorControl: SensorControl.orientation,
    animSpeed: 1.0,
    minLongitude: is180 ? -90.0 : -180.0,
    maxLongitude: is180 ? 90.0 : 180.0,
    child: Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: AppTheme.background,
        child: const Center(
          child: Icon(Icons.image_not_supported_rounded,
              size: 48, color: AppTheme.textTertiary),
        ),
      ),
    ),
  );
}
