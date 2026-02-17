import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:melon_core/app/theme.dart';

/// 웹에서만 표시되는 앱 다운로드 유도 배너
class AppDownloadBanner extends StatefulWidget {
  const AppDownloadBanner({super.key});

  @override
  State<AppDownloadBanner> createState() => _AppDownloadBannerState();
}

class _AppDownloadBannerState extends State<AppDownloadBanner> {
  bool _dismissed = false;

  // TODO: 실제 스토어 URL로 교체
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.melonticket.app';
  static const _appStoreUrl =
      'https://apps.apple.com/app/melonticket/id0000000000';

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _dismissed) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.gold.withValues(alpha: 0.12),
            AppTheme.goldDark.withValues(alpha: 0.08),
          ],
        ),
        border: const Border(
          bottom: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 앱 아이콘
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppTheme.goldGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(Icons.music_note_rounded,
                  size: 20, color: AppTheme.onAccent),
            ),
          ),
          const SizedBox(width: 10),

          // 텍스트
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '멜론티켓 앱으로 더 편하게!',
                  style: GoogleFonts.notoSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'QR 티켓 · 푸시 알림 · 빠른 예매',
                  style: GoogleFonts.notoSans(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // 다운로드 버튼
          GestureDetector(
            onTap: () => _showStoreDialog(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '열기',
                style: GoogleFonts.notoSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onAccent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // 닫기
          GestureDetector(
            onTap: () => setState(() => _dismissed = true),
            child: const Icon(Icons.close_rounded,
                size: 18, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  void _showStoreDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '앱 다운로드',
          style: GoogleFonts.notoSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StoreButton(
              icon: Icons.android_rounded,
              label: 'Google Play',
              color: Color(0xFF34A853),
              url: _playStoreUrl,
            ),
            SizedBox(height: 10),
            _StoreButton(
              icon: Icons.apple_rounded,
              label: 'App Store',
              color: AppTheme.textPrimary,
              url: _appStoreUrl,
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String url;

  const _StoreButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        // 실제로는 url_launcher로 열기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label 스토어로 이동합니다 (준비 중)')),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.notoSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
