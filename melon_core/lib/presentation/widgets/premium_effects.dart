import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:melon_core/app/theme.dart';

// ─────────────────────────────────────────────
// 1. ShimmerButton — Editorial CTA with subtle shimmer
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
    this.borderRadius = 4,
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
      duration: const Duration(milliseconds: 3000),
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
          scale: _isPressed ? 0.98 : 1.0,
          duration: Duration(milliseconds: _isPressed ? 80 : 300),
          curve: _isPressed ? Curves.easeIn : Curves.easeOutCubic,
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
                    color: AppTheme.gold.withValues(alpha: _isHovered ? 0.15 : 0.08),
                    blurRadius: _isHovered ? 20 : 12,
                    offset: const Offset(0, 4),
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
                                    Colors.white.withValues(alpha: 0.08),
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
                            GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: enabled
                                  ? AppTheme.onAccent
                                  : AppTheme.textTertiary,
                              letterSpacing: 2.0,
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
// 2. GlowCard — Editorial card with subtle hover
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
    this.borderRadius = 2,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.blurSigma = 0,
    this.onTap,
  });

  @override
  State<GlowCard> createState() => _GlowCardState();
}

class _GlowCardState extends State<GlowCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? AppTheme.card;
    final borderColor =
        widget.borderColor ?? AppTheme.sage.withValues(alpha: 0.15);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.onTap,
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
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.gold
                    .withValues(alpha: _isHovered ? 0.06 : 0.03),
                blurRadius: _isHovered ? 16 : 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: widget.child,
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
    this.pressedScale = 0.98,
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
        curve: _pressed ? Curves.easeIn : Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 4. AnimatedDialog — Editorial dialog
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
    barrierColor: Colors.black38,
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
          sigmaX: 16 * anim.value,
          sigmaY: 16 * anim.value,
        ),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
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
    this.borderRadius = 4,
    this.padding = const EdgeInsets.all(28),
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
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: AppTheme.sage.withValues(alpha: 0.15),
              width: 0.5,
            ),
            boxShadow: AppShadows.elevated,
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 5. SlideUpSheet — Editorial bottom sheet
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

class _SlideUpSheetPage extends StatefulWidget {
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
  State<_SlideUpSheetPage> createState() => _SlideUpSheetPageState();
}

class _SlideUpSheetPageState extends State<_SlideUpSheetPage> {
  double _dragOffset = 0;
  double _sheetHeight = 0;
  bool _isDragging = false;

  void _onVerticalDragStart(DragStartDetails details) {
    if (!widget.isDismissible) return;
    _isDragging = true;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, double.infinity);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final threshold = _sheetHeight > 0 ? _sheetHeight * 0.25 : 100;

    if (velocity > 700 || _dragOffset > threshold) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Stack(
      children: [
        // Dim backdrop
        AnimatedBuilder(
          animation: widget.animation,
          builder: (ctx, _) {
            final opacity = _sheetHeight > 0 && _dragOffset > 0
                ? (1.0 - (_dragOffset / _sheetHeight).clamp(0.0, 1.0))
                : 1.0;
            return GestureDetector(
              onTap: widget.isDismissible ? () => Navigator.of(ctx).pop() : null,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 8 * widget.animation.value * opacity,
                  sigmaY: 8 * widget.animation.value * opacity,
                ),
                child: Container(
                  color: Colors.black
                      .withValues(alpha: 0.25 * widget.animation.value * opacity),
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
            child: AnimatedContainer(
              duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, _dragOffset, 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.of(context).size.height * widget.maxHeightFraction,
                ),
                child: _SheetMeasurer(
                  onSized: (height) {
                    if (_sheetHeight != height) _sheetHeight = height;
                  },
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                      border: Border(
                        top: BorderSide(
                          color: AppTheme.sage.withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 30,
                          offset: const Offset(0, -10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle — swipeable area
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: _onVerticalDragStart,
                          onVerticalDragUpdate: _onVerticalDragUpdate,
                          onVerticalDragEnd: _onVerticalDragEnd,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 2,
                                color: AppTheme.sage.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                        Flexible(child: widget.builder(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetMeasurer extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onSized;

  const _SheetMeasurer({required this.onSized, required Widget child})
      : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SheetMeasurerRenderObject(onSized);

  @override
  void updateRenderObject(
      BuildContext context, _SheetMeasurerRenderObject renderObject) {
    renderObject.onSized = onSized;
  }
}

class _SheetMeasurerRenderObject extends RenderProxyBox {
  ValueChanged<double> onSized;

  _SheetMeasurerRenderObject(this.onSized);

  @override
  void performLayout() {
    super.performLayout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasSize) onSized(size.height);
    });
  }
}

// ─────────────────────────────────────────────
// 6. ShimmerLoading — Editorial skeleton loading
// ─────────────────────────────────────────────

class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    this.height = 20,
    this.borderRadius = 2,
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
                AppTheme.cardElevated,
                AppTheme.sage.withValues(alpha: 0.08),
                AppTheme.cardElevated,
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
