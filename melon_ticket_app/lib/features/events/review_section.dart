import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/review.dart';
import 'package:melon_core/data/repositories/review_repository.dart';
import 'package:melon_core/services/auth_service.dart';

// =============================================================================
// Review Section (이벤트 상세 화면 내 리뷰 영역)
// =============================================================================

class ReviewSection extends ConsumerWidget {
  final String eventId;
  const ReviewSection({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(eventReviewsProvider(eventId));
    final ratingAsync = ref.watch(eventRatingProvider(eventId));
    final authState = ref.watch(authStateProvider);
    final isLoggedIn = authState.value != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 0.5, color: AppTheme.border),
          const SizedBox(height: 20),

          // ── 헤더: 제목 + 평균 별점 + 리뷰 쓰기 버튼 ──
          Row(
            children: [
              Text(
                '관람 후기',
                style: AppTheme.nanum(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  shadows: AppTheme.textShadow,
                ),
              ),
              const SizedBox(width: 8),
              ratingAsync.when(
                data: (rating) => rating > 0
                    ? Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 16, color: Color(0xFFFFD700)),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: AppTheme.nanum(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFFFD700),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const Spacer(),
              if (isLoggedIn)
                GestureDetector(
                  onTap: () => _showWriteReviewSheet(context, ref),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: AppTheme.goldGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_rounded,
                            size: 14, color: AppTheme.onAccent),
                        const SizedBox(width: 4),
                        Text(
                          '후기 쓰기',
                          style: AppTheme.nanum(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.onAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── 리뷰 목록 ──
          reviewsAsync.when(
            data: (reviews) {
              if (reviews.isEmpty) {
                return _EmptyReviews(isLoggedIn: isLoggedIn);
              }
              return Column(
                children: reviews
                    .take(5)
                    .map((review) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ReviewCard(
                            review: review,
                            currentUserId: authState.value?.uid,
                            onEdit: () => _showWriteReviewSheet(
                              context,
                              ref,
                              existingReview: review,
                            ),
                            onDelete: () =>
                                _confirmDelete(context, ref, review.id),
                          ),
                        ))
                    .toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.gold),
                ),
              ),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '리뷰를 불러올 수 없습니다',
                  style: AppTheme.nanum(
                      fontSize: 13, color: AppTheme.textTertiary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWriteReviewSheet(
    BuildContext context,
    WidgetRef ref, {
    Review? existingReview,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WriteReviewSheet(
        eventId: eventId,
        existingReview: existingReview,
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String reviewId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '후기 삭제',
          style: AppTheme.nanum(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            shadows: AppTheme.textShadow,
          ),
        ),
        content: Text(
          '이 후기를 삭제하시겠습니까?',
          style: AppTheme.nanum(
              fontSize: 14, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소',
                style: AppTheme.nanum(color: AppTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(reviewRepositoryProvider)
                  .deleteReview(reviewId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('후기가 삭제되었습니다')),
                );
              }
            },
            child: Text('삭제',
                style: AppTheme.nanum(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Empty Reviews Placeholder
// =============================================================================

class _EmptyReviews extends StatelessWidget {
  final bool isLoggedIn;
  const _EmptyReviews({required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.rate_review_outlined,
              size: 36, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            '아직 후기가 없습니다',
            style: AppTheme.nanum(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.textTertiary,
            ),
          ),
          if (isLoggedIn) ...[
            const SizedBox(height: 4),
            Text(
              '첫 번째 후기를 남겨보세요!',
              style: AppTheme.nanum(
                fontSize: 12,
                color: AppTheme.textTertiary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Review Card
// =============================================================================

class _ReviewCard extends StatelessWidget {
  final Review review;
  final String? currentUserId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ReviewCard({
    required this.review,
    required this.currentUserId,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOwner = currentUserId == review.userId;
    final dateFormat = DateFormat('yyyy.MM.dd', 'ko_KR');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단: 사용자 정보 + 별점 + 메뉴 ──
          Row(
            children: [
              // 프로필
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppTheme.goldSubtle,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: review.userPhotoUrl != null
                    ? Image.network(review.userPhotoUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback())
                    : _avatarFallback(),
              ),
              const SizedBox(width: 10),

              // 이름 + 날짜
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userDisplayName,
                      style: AppTheme.nanum(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      dateFormat.format(review.createdAt),
                      style: AppTheme.nanum(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),

              // 별점
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final filled = i < review.rating.round();
                  return Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 16,
                    color: filled
                        ? const Color(0xFFFFD700)
                        : AppTheme.textTertiary.withValues(alpha: 0.3),
                  );
                }),
              ),

              // 수정/삭제 메뉴
              if (isOwner) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 18,
                  icon: const Icon(Icons.more_vert_rounded,
                      size: 18, color: AppTheme.textTertiary),
                  color: AppTheme.cardElevated,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('수정',
                          style: AppTheme.nanum(
                              fontSize: 13, color: AppTheme.textPrimary)),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('삭제',
                          style: AppTheme.nanum(
                              fontSize: 13, color: AppTheme.error)),
                    ),
                  ],
                ),
              ],
            ],
          ),

          // ── 좌석 정보 ──
          if (review.seatInfo != null && review.seatInfo!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.goldSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                review.seatInfo!,
                style: AppTheme.nanum(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.gold,
                ),
              ),
            ),
          ],

          // ── 리뷰 내용 ──
          const SizedBox(height: 10),
          Text(
            review.content,
            style: AppTheme.nanum(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    return Center(
      child: Text(
        review.userDisplayName.isNotEmpty
            ? review.userDisplayName[0].toUpperCase()
            : '?',
        style: AppTheme.nanum(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppTheme.gold,
        ),
      ),
    );
  }
}

// =============================================================================
// Write Review Bottom Sheet
// =============================================================================

class _WriteReviewSheet extends ConsumerStatefulWidget {
  final String eventId;
  final Review? existingReview;

  const _WriteReviewSheet({
    required this.eventId,
    this.existingReview,
  });

  @override
  ConsumerState<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends ConsumerState<_WriteReviewSheet> {
  late double _rating;
  late TextEditingController _contentCtrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.existingReview?.rating ?? 5.0;
    _contentCtrl =
        TextEditingController(text: widget.existingReview?.content ?? '');
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.existingReview != null;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 핸들 바 ──
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── 제목 ──
          Text(
            isEdit ? '후기 수정' : '후기 작성',
            style: AppTheme.nanum(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              shadows: AppTheme.textShadow,
            ),
          ),
          const SizedBox(height: 20),

          // ── 별점 선택 ──
          Text(
            '별점을 선택하세요',
            style: AppTheme.nanum(
                fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starValue = (i + 1).toDouble();
              return GestureDetector(
                onTap: () => setState(() => _rating = starValue),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    i < _rating.round()
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 40,
                    color: i < _rating.round()
                        ? const Color(0xFFFFD700)
                        : AppTheme.textTertiary.withValues(alpha: 0.3),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            _ratingLabel(_rating.round()),
            style: AppTheme.nanum(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFFD700),
            ),
          ),
          const SizedBox(height: 20),

          // ── 내용 입력 ──
          TextField(
            controller: _contentCtrl,
            maxLines: 4,
            maxLength: 500,
            style: AppTheme.nanum(
                fontSize: 14, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: '공연은 어떠셨나요? 솔직한 후기를 남겨주세요',
              hintStyle: AppTheme.nanum(
                  fontSize: 14, color: AppTheme.textTertiary),
              filled: true,
              fillColor: AppTheme.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.gold, width: 1.5),
              ),
              counterStyle:
                  AppTheme.nanum(fontSize: 11, color: AppTheme.textTertiary),
            ),
          ),
          const SizedBox(height: 16),

          // ── 제출 버튼 ──
          SizedBox(
            width: double.infinity,
            height: 50,
            child: Container(
              decoration: BoxDecoration(
                gradient: _contentCtrl.text.trim().isNotEmpty && !_submitting
                    ? AppTheme.goldGradient
                    : null,
                color: _contentCtrl.text.trim().isEmpty || _submitting
                    ? AppTheme.border
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _contentCtrl.text.trim().isEmpty || _submitting
                      ? null
                      : _submit,
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.onAccent),
                          )
                        : Text(
                            isEdit ? '수정 완료' : '후기 등록',
                            style: AppTheme.nanum(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _contentCtrl.text.trim().isNotEmpty
                                  ? AppTheme.onAccent
                                  : AppTheme.textTertiary,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return '별로예요';
      case 2:
        return '그저 그래요';
      case 3:
        return '괜찮아요';
      case 4:
        return '좋아요!';
      case 5:
        return '최고예요!';
      default:
        return '';
    }
  }

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) return;

    setState(() => _submitting = true);

    try {
      final repo = ref.read(reviewRepositoryProvider);
      final user = ref.read(authStateProvider).value;

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('로그인이 필요합니다')),
          );
        }
        return;
      }

      if (widget.existingReview != null) {
        // 수정
        await repo.updateReview(
          widget.existingReview!.id,
          content,
          _rating,
        );
      } else {
        // 신규 작성 - 중복 체크
        final existing =
            await repo.getUserReviewForEvent(user.uid, widget.eventId);
        if (existing != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('이미 후기를 작성하셨습니다. 수정해주세요.')),
            );
          }
          setState(() => _submitting = false);
          return;
        }

        await repo.createReview(Review(
          id: '',
          eventId: widget.eventId,
          userId: user.uid,
          userDisplayName: user.displayName ?? user.email?.split('@').first ?? '익명',
          userPhotoUrl: user.photoURL,
          rating: _rating,
          content: content,
          createdAt: DateTime.now(),
        ));
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingReview != null
                ? '후기가 수정되었습니다'
                : '후기가 등록되었습니다'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
