import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melon_core/data/models/app_user.dart';
import 'package:melon_core/services/auth_service.dart';
import '../../../app/admin_theme.dart';

/// 테스트용 역할 전환 플로팅 바
/// superAdmin에게만 표시되며, 즉시 역할 전환이 가능합니다.
class RoleSwitcherWidget extends ConsumerWidget {
  const RoleSwitcherWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 실제(원본) 사용자 정보 — override 전
    final realUser = ref.watch(currentUserProvider).value;
    if (realUser == null || !realUser.isSuperAdmin) {
      return const SizedBox.shrink();
    }

    final override = ref.watch(roleOverrideProvider);
    final isTestMode = override != null;
    final activeRole = override ?? realUser.role;

    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Center(
        child: _RoleSwitcherBar(
          activeRole: activeRole,
          isTestMode: isTestMode,
          onRoleSelected: (role) {
            if (role == UserRole.superAdmin) {
              // Master 선택 → 오버라이드 해제 (원래 역할 복귀)
              ref.read(roleOverrideProvider.notifier).state = null;
            } else {
              ref.read(roleOverrideProvider.notifier).state = role;
            }
          },
        ),
      ),
    );
  }
}

class _RoleSwitcherBar extends StatelessWidget {
  final UserRole activeRole;
  final bool isTestMode;
  final ValueChanged<UserRole> onRoleSelected;

  const _RoleSwitcherBar({
    required this.activeRole,
    required this.isTestMode,
    required this.onRoleSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTestMode
              ? AdminTheme.warning.withValues(alpha: 0.6)
              : AdminTheme.border,
          width: isTestMode ? 1.5 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          if (isTestMode)
            BoxShadow(
              color: AdminTheme.warning.withValues(alpha: 0.1),
              blurRadius: 30,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 테스트 모드 인디케이터
          if (isTestMode) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AdminTheme.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AdminTheme.warning,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AdminTheme.warning.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '테스트 모드',
                    style: AdminTheme.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.warning,
                      noShadow: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 14,
                    color: AdminTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '역할 전환',
                    style: AdminTheme.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.textSecondary,
                      noShadow: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
          ],

          // 역할 버튼들
          _RoleButton(
            label: '관객',
            icon: Icons.person_outline_rounded,
            role: UserRole.user,
            isActive: activeRole == UserRole.user,
            color: const Color(0xFF60A5FA), // blue
            onTap: () => onRoleSelected(UserRole.user),
          ),
          const SizedBox(width: 4),
          _RoleButton(
            label: 'Seller',
            icon: Icons.storefront_outlined,
            role: UserRole.seller,
            isActive: activeRole == UserRole.seller,
            color: const Color(0xFF4ADE80), // green
            onTap: () => onRoleSelected(UserRole.seller),
          ),
          const SizedBox(width: 4),
          _RoleButton(
            label: 'Master',
            icon: Icons.shield_outlined,
            role: UserRole.superAdmin,
            isActive: activeRole == UserRole.superAdmin,
            color: AdminTheme.gold,
            onTap: () => onRoleSelected(UserRole.superAdmin),
          ),
        ],
      ),
    );
  }
}

class _RoleButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final UserRole role;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _RoleButton({
    required this.label,
    required this.icon,
    required this.role,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  State<_RoleButton> createState() => _RoleButtonState();
}

class _RoleButtonState extends State<_RoleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.color.withValues(alpha: 0.15)
                : _isHovered
                    ? AdminTheme.cardElevated
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isActive
                  ? widget.color.withValues(alpha: 0.4)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isActive
                    ? widget.color
                    : AdminTheme.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: AdminTheme.sans(
                  fontSize: 11,
                  fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w500,
                  color: widget.isActive
                      ? widget.color
                      : AdminTheme.textSecondary,
                  noShadow: true,
                ),
              ),
              if (widget.isActive) ...[
                const SizedBox(width: 5),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
