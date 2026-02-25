import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/services/auth_service.dart';

// =============================================================================
// 티켓 어드민 승인 관리 (Editorial / Luxury Magazine Admin Design)
// =============================================================================

class AdminSetupScreen extends ConsumerStatefulWidget {
  const AdminSetupScreen({super.key});

  @override
  ConsumerState<AdminSetupScreen> createState() => _AdminSetupScreenState();
}

class _AdminSetupScreenState extends ConsumerState<AdminSetupScreen> {
  bool _isSubmitting = false;
  String? _actionTargetUid;

  Future<void> _submitApprovalRequest() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(authServiceProvider).submitAdminApprovalRequest(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('관리자 승인 요청이 접수되었습니다.'),
          backgroundColor: AdminTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('요청 실패: $e'),
          backgroundColor: AdminTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _approve(String userId) async {
    setState(() => _actionTargetUid = userId);
    try {
      await ref.read(authServiceProvider).approveAdminApprovalRequest(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('관리자 승인 완료'),
          backgroundColor: AdminTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('승인 실패: $e'),
          backgroundColor: AdminTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _actionTargetUid = null);
      }
    }
  }

  Future<void> _reject(String userId) async {
    setState(() => _actionTargetUid = userId);
    try {
      await ref.read(authServiceProvider).rejectAdminApprovalRequest(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('요청을 거절했습니다'),
          backgroundColor: AdminTheme.warning,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('거절 실패: $e'),
          backgroundColor: AdminTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _actionTargetUid = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final appUser = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AdminTheme.background,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: authState.when(
              data: (firebaseUser) {
                if (firebaseUser == null) {
                  return _buildLoginPrompt();
                }

                final isOwner = (firebaseUser.email ?? '').toLowerCase() ==
                    AuthService.ownerEmail;

                if (isOwner) {
                  return _buildOwnerApprovalPanel();
                }

                return _buildRequestPanel(
                  user: firebaseUser,
                  isAlreadyAdmin: appUser?.isAdmin == true,
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AdminTheme.gold),
              ),
              error: (error, _) => Center(
                child: Text('오류: $error',
                    style: AdminTheme.sans(color: AdminTheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── App Bar ──
  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 4,
        right: 16,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: AdminTheme.surface,
        border:
            Border(bottom: BorderSide(color: AdminTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/');
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AdminTheme.textPrimary, size: 20),
          ),
          Expanded(
            child: Text(
              '어드민 승인 관리',
              style: AdminTheme.serif(fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }

  // ── Login Prompt ──
  Widget _buildLoginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AdminTheme.goldSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Icon(Icons.lock_outline,
                  size: 28, color: AdminTheme.gold),
            ),
            const SizedBox(height: 20),
            Text(
              '로그인이 필요합니다',
              style: AdminTheme.serif(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              '관리자 승인 관리는 로그인 후 이용할 수 있습니다.',
              style: AdminTheme.sans(
                  color: AdminTheme.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go('/login'),
                child: Text('로그인하기',
                    style: AdminTheme.sans(
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.onAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Request Panel (일반 사용자) ──
  Widget _buildRequestPanel({
    required User user,
    required bool isAlreadyAdmin,
  }) {
    final requestStream = FirebaseFirestore.instance
        .collection('adminApprovalRequests')
        .doc(user.uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: requestStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final status = (data?['status'] as String?) ?? '';

        final isPending = status == 'pending';
        final isApproved = status == 'approved';
        final isRejected = status == 'rejected';

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 12),
            // Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AdminTheme.goldSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.manage_accounts_rounded,
                  size: 28, color: AdminTheme.gold),
            ),
            const SizedBox(height: 20),
            Text(
              '관리자 승인 요청',
              style: AdminTheme.serif(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isAlreadyAdmin
                  ? '이미 관리자 권한이 활성화된 계정입니다.'
                  : '요청을 보내면 오너(${AuthService.ownerEmail})가 승인 후\n관리자 권한을 부여합니다.',
              style: AdminTheme.sans(
                  color: AdminTheme.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Account info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AdminTheme.surface,
                borderRadius: BorderRadius.circular(2),
                border:
                    Border.all(color: AdminTheme.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ACCOUNT',
                      style: AdminTheme.label()),
                  const SizedBox(height: 12),
                  _infoRow('이메일', user.email ?? '-'),
                  const SizedBox(height: 8),
                  _infoRow('상태', _statusLabel(status, isAlreadyAdmin)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (isAlreadyAdmin || isPending || _isSubmitting)
                    ? null
                    : _submitApprovalRequest,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AdminTheme.onAccent,
                        ),
                      )
                    : Text(
                        isRejected ? '관리자 승인 재요청' : '관리자 승인 요청 보내기',
                        style: AdminTheme.sans(
                            fontWeight: FontWeight.w700,
                            color: AdminTheme.onAccent),
                      ),
              ),
            ),
            if (isApproved && !isAlreadyAdmin) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await ref.read(authServiceProvider).signOut();
                    if (!context.mounted) return;
                    context.go('/login');
                  },
                  child: Text(
                    '다시 로그인하여 권한 반영',
                    style: AdminTheme.sans(
                        fontWeight: FontWeight.w500,
                        color: AdminTheme.gold),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label,
              style: AdminTheme.sans(
                  fontSize: 12, color: AdminTheme.textTertiary)),
        ),
        Expanded(
          child: Text(value,
              style: AdminTheme.sans(
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  // ── Owner Approval Panel ──
  Widget _buildOwnerApprovalPanel() {
    final pendingStream = FirebaseFirestore.instance
        .collection('adminApprovalRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: pendingStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('요청 목록 조회 실패: ${snapshot.error}',
                style: AdminTheme.sans(color: AdminTheme.error)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AdminTheme.gold),
          );
        }

        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aTs = a.data()['requestedAt'] as Timestamp?;
            final bTs = b.data()['requestedAt'] as Timestamp?;
            final aMs = aTs?.millisecondsSinceEpoch ?? 0;
            final bMs = bTs?.millisecondsSinceEpoch ?? 0;
            return aMs.compareTo(bMs);
          });

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('PENDING REQUESTS',
                style: AdminTheme.label()),
            const SizedBox(height: 8),
            Text(
              '관리자 승인 대기 목록',
              style: AdminTheme.serif(fontSize: 22),
            ),
            const SizedBox(height: 6),
            Text(
              '오너 계정(${AuthService.ownerEmail})만 승인/거절할 수 있습니다.',
              style: AdminTheme.sans(
                  color: AdminTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            if (docs.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 32),
                decoration: BoxDecoration(
                  color: AdminTheme.surface,
                  borderRadius: BorderRadius.circular(2),
                  border:
                      Border.all(color: AdminTheme.border, width: 0.5),
                ),
                child: Center(
                  child: Text(
                    '현재 승인 대기 요청이 없습니다.',
                    style: AdminTheme.sans(color: AdminTheme.textTertiary),
                  ),
                ),
              )
            else
              ...docs.map((doc) {
                final data = doc.data();
                final uid = doc.id;
                final email = data['email'] ?? '-';
                final displayName = data['displayName'] ?? '-';
                final requestedAt = data['requestedAt'] as Timestamp?;
                final requestedLabel = requestedAt == null
                    ? '시간 미기록'
                    : requestedAt.toDate().toLocal().toString();
                final isActing = _actionTargetUid == uid;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminTheme.surface,
                    borderRadius: BorderRadius.circular(2),
                    border:
                        Border.all(color: AdminTheme.border, width: 0.5),
                    boxShadow: AdminShadows.small,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: AdminTheme.serif(fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(email,
                          style: AdminTheme.sans(
                              fontSize: 13,
                              color: AdminTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text('요청 시각: $requestedLabel',
                          style: AdminTheme.sans(
                              fontSize: 12,
                              color: AdminTheme.textTertiary)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed:
                                  isActing ? null : () => _approve(uid),
                              child: isActing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AdminTheme.onAccent,
                                      ),
                                    )
                                  : Text('승인',
                                      style: AdminTheme.sans(
                                          fontWeight: FontWeight.w700,
                                          color: AdminTheme.onAccent)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  isActing ? null : () => _reject(uid),
                              child: Text(
                                '거절',
                                style: AdminTheme.sans(
                                    fontWeight: FontWeight.w500,
                                    color: AdminTheme.error),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  String _statusLabel(String status, bool isAlreadyAdmin) {
    if (isAlreadyAdmin) return '승인 완료 (관리자)';
    switch (status) {
      case 'pending':
        return '승인 대기 중';
      case 'approved':
        return '승인 완료 (다시 로그인 시 반영)';
      case 'rejected':
        return '거절됨';
      default:
        return '요청 없음';
    }
  }
}
