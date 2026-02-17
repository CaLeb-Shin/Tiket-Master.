import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:melon_core/app/theme.dart';

// ─────────────────────────────────────────────
// 1. ShimmerButton — CTA 버튼에 빛 스윕 애니메이션
// ─────────────────────────────────────────────

class ShimmerButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final double height;
  final double? width;
  final double borderRadius;
  final TextStyle? textStyle;
  final Widget? icon;
  final Gradient? gradient;

  const ShimmerButton({
    super.key,
    required this.text,
    this.onPressed,
    this.height = 56,
    this.width,
    this.borderRadius = 14,
    this.textStyle,
    this.icon,
    this.gradient,
  });

  @override
  State<ShimmerButton> createState() => _ShimmerButtonState();
}

class _ShimmerButtonState extends State<ShimmerButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerCtrl;
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final gradient = widget.gradient ?? AppTheme.goldGradient;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _isPressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: enabled ? () => setState(() => _isPressed = false) : null,
        child: AnimatedScale(
          scale: _isPressed
              ? 0.95
              : _isHovered
                  ? 1.02
                  : 1.0,
          duration: Duration(milliseconds: _isPressed ? 100 : 300),
          curve: _isPressed ? Curves.easeIn : Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: widget.height,
            width: widget.width ?? double.infinity,
            decoration: BoxDecoration(
              gradient: enabled ? gradient : null,
              color: enabled ? null : AppTheme.border,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                if (enabled)
                  BoxShadow(
                    color: AppTheme.gold.withValues(alpha: _isHovered ? 0.5 : 0.3),
                    blurRadius: _isHovered ? 24 : 12,
                    offset: const Offset(0, 4),
                    spreadRadius: _isHovered ? 2 : 0,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Shimmer sweep
                  if (enabled)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _shimmerCtrl,
                          builder: (context, _) {
                            final p = _shimmerCtrl.value;
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.18),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                  stops: [
                                    (p - 0.3).clamp(0.0, 1.0),
                                    p,
                                    (p + 0.3).clamp(0.0, 1.0),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  // Content
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        widget.icon!,
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.text,
                        style: widget.textStyle ??
                            TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: enabled
                                  ? AppTheme.onAccent
                                  : AppTheme.textTertiary,
                              letterSpacing: -0.2,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────
// 2. GlowCard — 글래스모피즘 카드
// ─────────────────────────────────────────────

class GlowCard extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double blurSigma;
  final VoidCallback? onTap;

  const GlowCard({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.blurSigma = 12,
    this.onTap,
  });

  @override
  State<GlowCard> createState() => _GlowCardState();
}

class _GlowCardState extends State<GlowCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.backgroundColor ?? AppTheme.card.withValues(alpha: 0.7);
    final borderColor =
        widget.borderColor ?? AppTheme.gold.withValues(alpha: 0.15);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.01 : 1.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.gold
                      .withValues(alpha: _isHovered ? 0.12 : 0.05),
                  blurRadius: _isHovered ? 20 : 8,
                  spreadRadius: _isHovered ? 1 : 0,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: widget.blurSigma,
                  sigmaY: widget.blurSigma,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: widget.padding ?? const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    border: Border.all(
                      color: _isHovered
                          ? borderColor.withValues(alpha: 0.35)
                          : borderColor,
                      width: 1,
                    ),
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 3. PressableScale — 범용 탭 스케일 래퍼
// ─────────────────────────────────────────────

class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: Duration(milliseconds: _pressed ? 80 : 250),
        curve: _pressed ? Curves.easeIn : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 4. AnimatedDialog — 프리미엄 다이얼로그
// ─────────────────────────────────────────────

Future<T?> showAnimatedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (ctx, anim, secondAnim) => builder(ctx),
    transitionBuilder: (ctx, anim, secondAnim, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeIn,
      );
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 20 * anim.value,
          sigmaY: 20 * anim.value,
        ),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class AnimatedDialogContent extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const AnimatedDialogContent({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: padding,
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: AppTheme.gold.withValues(alpha: 0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: AppTheme.gold.withValues(alpha: 0.08),
                blurRadius: 60,
                spreadRadius: -4,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 5. SlideUpSheet — 바텀시트 대체
// ─────────────────────────────────────────────

Future<T?> showSlideUpSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  double maxHeightFraction = 0.85,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (ctx, anim, secondAnim) {
      return _SlideUpSheetPage(
        animation: anim,
        builder: builder,
        isDismissible: isDismissible,
        maxHeightFraction: maxHeightFraction,
      );
    },
    transitionBuilder: (ctx, anim, secondAnim, child) => child,
  );
}

class _SlideUpSheetPage extends StatelessWidget {
  final Animation<double> animation;
  final WidgetBuilder builder;
  final bool isDismissible;
  final double maxHeightFraction;

  const _SlideUpSheetPage({
    required this.animation,
    required this.builder,
    required this.isDismissible,
    required this.maxHeightFraction,
  });

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Stack(
      children: [
        // Blur + dim backdrop
        AnimatedBuilder(
          animation: animation,
          builder: (ctx, _) {
            return GestureDetector(
              onTap: isDismissible ? () => Navigator.of(ctx).pop() : null,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 12 * animation.value,
                  sigmaY: 12 * animation.value,
                ),
                child: Container(
                  color: Colors.black
                      .withValues(alpha: 0.5 * animation.value),
                ),
              ),
            );
          },
        ),
        // Sheet
        Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.of(context).size.height * maxHeightFraction,
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.gold.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 30,
                      offset: const Offset(0, -10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.textTertiary.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Flexible(child: builder(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 6. ShimmerLoading — 스켈레톤 로딩
// ─────────────────────────────────────────────

class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    this.height = 20,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppTheme.card,
                AppTheme.gold.withValues(alpha: 0.08),
                AppTheme.card,
              ],
              stops: [
                math.max(0.0, _ctrl.value - 0.3),
                _ctrl.value,
                math.min(1.0, _ctrl.value + 0.3),
              ],
            ),
          ),
        );
      },
    );
  }
}
