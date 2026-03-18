import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:melon_core/melon_core.dart';

class SellerRegisterScreen extends ConsumerStatefulWidget {
  const SellerRegisterScreen({super.key});

  @override
  ConsumerState<SellerRegisterScreen> createState() =>
      _SellerRegisterScreenState();
}

class _SellerRegisterScreenState extends ConsumerState<SellerRegisterScreen> {
  final _businessNameCtrl = TextEditingController();
  final _businessNumberCtrl = TextEditingController();
  final _representativeCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _businessNumberCtrl.dispose();
    _representativeCtrl.dispose();
    _contactCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'SELLER',
          style: AppTheme.label(fontSize: 12, color: AppTheme.gold),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '공연사 등록',
            style: AppTheme.serif(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '공연사로 등록하면 직접 공연을 등록하고\n판매 현황을 관리할 수 있습니다.',
            style: AppTheme.sans(
              fontSize: 14,
              color: AppTheme.sage,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // 이미 셀러인 경우
          if (user?.isSeller == true) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: user?.sellerProfile?.sellerStatus == 'active'
                      ? const Color(0xFF2D6A4F)
                      : AppTheme.gold,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    user?.sellerProfile?.sellerStatus == 'active'
                        ? Icons.check_circle_outline
                        : Icons.hourglass_top_outlined,
                    size: 40,
                    color: user?.sellerProfile?.sellerStatus == 'active'
                        ? const Color(0xFF2D6A4F)
                        : AppTheme.gold,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.sellerProfile?.sellerStatus == 'active'
                        ? '공연사 승인 완료'
                        : '승인 대기 중',
                    style: AppTheme.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.sellerProfile?.sellerStatus == 'active'
                        ? '어드민에서 공연을 등록할 수 있습니다.'
                        : '관리자 승인 후 공연 등록이 가능합니다.',
                    style: AppTheme.sans(
                      fontSize: 13,
                      color: AppTheme.sage,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // 등록 폼
            _buildField('상호명 *', _businessNameCtrl, '공연사/단체명'),
            const SizedBox(height: 16),
            _buildField('사업자등록번호', _businessNumberCtrl, '000-00-00000'),
            const SizedBox(height: 16),
            _buildField('대표자명', _representativeCtrl, '홍길동'),
            const SizedBox(height: 16),
            _buildField('연락처', _contactCtrl, '010-0000-0000'),
            const SizedBox(height: 16),
            _buildField('소개', _descriptionCtrl, '공연사 소개글', maxLines: 3),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: AppTheme.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        '공연사 등록 신청',
                        style: AppTheme.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onAccent,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          style: AppTheme.sans(fontSize: 14, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTheme.sans(
              fontSize: 14,
              color: AppTheme.sage.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: AppTheme.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(2),
              borderSide: BorderSide(color: AppTheme.border, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(2),
              borderSide: BorderSide(color: AppTheme.border, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(2),
              borderSide: const BorderSide(color: AppTheme.gold, width: 1),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name = _businessNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('상호명을 입력해주세요'),
          backgroundColor: Color(0xFFC42A4D),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(functionsServiceProvider).registerAsSeller(
            businessName: name,
            businessNumber: _businessNumberCtrl.text.trim(),
            representativeName: _representativeCtrl.text.trim(),
            contactNumber: _contactCtrl.text.trim(),
            description: _descriptionCtrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('공연사 등록 신청 완료! 관리자 승인을 기다려주세요.'),
            backgroundColor: Color(0xFF2D6A4F),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('등록 실패: $e'),
            backgroundColor: const Color(0xFFC42A4D),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
