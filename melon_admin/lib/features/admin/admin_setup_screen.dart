import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:melon_core/services/auth_service.dart';

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
        const SnackBar(
          content: Text('관리자 승인 요청이 접수되었습니다.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('요청 실패: $e'),
          backgroundColor: Colors.red,
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
        const SnackBar(
          content: Text('관리자 승인 완료'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('승인 실패: $e'),
          backgroundColor: Colors.red,
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
        const SnackBar(
          content: Text('요청을 거절했습니다'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('거절 실패: $e'),
          backgroundColor: Colors.red,
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
      appBar: AppBar(
        title: const Text('티켓 어드민 승인 관리'),
      ),
      body: authState.when(
        data: (firebaseUser) {
          if (firebaseUser == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('로그인 후 이용할 수 있습니다.'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.push('/login'),
                      child: const Text('로그인하기'),
                    ),
                  ],
                ),
              ),
            );
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('오류: $error')),
      ),
    );
  }

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
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(
              Icons.manage_accounts_rounded,
              size: 62,
              color: Colors.amber,
            ),
            const SizedBox(height: 14),
            const Text(
              '티켓 어드민 승인 요청',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isAlreadyAdmin
                  ? '이미 관리자 권한이 활성화된 계정입니다.'
                  : '요청을 보내면 오너(${AuthService.ownerEmail})가 승인 후 관리자 권한을 부여합니다.',
              style: TextStyle(color: Colors.grey[700], height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueGrey.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('신청 계정: ${user.email ?? '-'}'),
                  const SizedBox(height: 6),
                  Text('현재 상태: ${_statusLabel(status, isAlreadyAdmin)}'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (isAlreadyAdmin || isPending || _isSubmitting)
                  ? null
                  : _submitApprovalRequest,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isRejected ? '관리자 승인 재요청' : '관리자 승인 요청 보내기'),
            ),
            if (isApproved && !isAlreadyAdmin) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  if (!context.mounted) return;
                  context.go('/login');
                },
                child: const Text('다시 로그인하여 권한 반영'),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildOwnerApprovalPanel() {
    final pendingStream = FirebaseFirestore.instance
        .collection('adminApprovalRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: pendingStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('요청 목록 조회 실패: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
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
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '관리자 승인 대기 목록',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '오너 계정(${AuthService.ownerEmail})만 승인/거절할 수 있습니다.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            if (docs.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('현재 승인 대기 요청이 없습니다.'),
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

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(email),
                        const SizedBox(height: 4),
                        Text('요청 시각: $requestedLabel'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed:
                                    isActing ? null : () => _approve(uid),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: isActing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('승인'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isActing ? null : () => _reject(uid),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('거절'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
