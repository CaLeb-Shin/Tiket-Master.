import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/data/models/hall.dart';
import 'package:melon_core/data/repositories/hall_repository.dart';
import 'package:melon_core/services/auth_service.dart';

class HallScreen extends ConsumerStatefulWidget {
  final String hallId;
  const HallScreen({super.key, required this.hallId});

  @override
  ConsumerState<HallScreen> createState() => _HallScreenState();
}

class _HallScreenState extends ConsumerState<HallScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hallAsync = ref.watch(hallStreamProvider(widget.hallId));

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: hallAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.gold)),
        error: (e, _) => Center(
            child: Text('오류: $e',
                style: AppTheme.sans(color: AppTheme.error))),
        data: (hall) {
          if (hall == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forum_outlined,
                      size: 48,
                      color: AppTheme.sage.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('Hall을 찾을 수 없습니다',
                      style: AppTheme.sans(color: AppTheme.textSecondary)),
                ],
              ),
            );
          }

          return NestedScrollView(
            headerSliverBuilder: (context, _) => [
              _HallHeader(hall: hall, hallId: widget.hallId),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  tabBar: TabBar(
                    controller: _tabCtrl,
                    indicatorColor: AppTheme.gold,
                    indicatorWeight: 2,
                    labelColor: AppTheme.gold,
                    unselectedLabelColor: AppTheme.textSecondary,
                    labelStyle: AppTheme.sans(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    unselectedLabelStyle:
                        AppTheme.sans(fontSize: 13),
                    dividerHeight: 0,
                    tabs: const [
                      Tab(text: '리뷰'),
                      Tab(text: '토론'),
                      Tab(text: '사진'),
                      Tab(text: '공지'),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabCtrl,
              children: [
                _PostList(
                    hallId: widget.hallId, type: 'review', hall: hall),
                _PostList(
                    hallId: widget.hallId,
                    type: 'discussion',
                    hall: hall),
                _PostList(
                    hallId: widget.hallId, type: 'photo', hall: hall),
                _PostList(
                    hallId: widget.hallId, type: 'notice', hall: hall),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Hall Header ───
class _HallHeader extends ConsumerWidget {
  final Hall hall;
  final String hallId;
  const _HallHeader({required this.hall, required this.hallId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return SliverToBoxAdapter(
      child: Stack(
        children: [
          // 커버 이미지
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.gold.withValues(alpha: 0.15),
                  AppTheme.background,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: hall.coverImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: hall.coverImageUrl!,
                    fit: BoxFit.cover,
                    color: Colors.black.withValues(alpha: 0.3),
                    colorBlendMode: BlendMode.darken,
                  )
                : null,
          ),

          // 뒤로 가기
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: Colors.white),
              ),
            ),
          ),

          // Hall 정보
          Positioned(
            left: 20,
            right: 20,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hall.name,
                  style: AppTheme.serif(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // 평균 별점
                    if (hall.reviewCount > 0) ...[
                      Icon(Icons.star_rounded,
                          size: 16, color: AppTheme.gold),
                      const SizedBox(width: 4),
                      Text(
                        hall.averageRating.toStringAsFixed(1),
                        style: AppTheme.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.gold),
                      ),
                      Text(
                        ' (${hall.reviewCount})',
                        style: AppTheme.sans(
                            fontSize: 12,
                            color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 16),
                    ],
                    // 팔로워
                    Icon(Icons.people_outline_rounded,
                        size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${hall.followerCount}',
                      style: AppTheme.sans(
                          fontSize: 13,
                          color: AppTheme.textSecondary),
                    ),
                    const Spacer(),
                    // 팔로우 버튼
                    if (userId != null)
                      _FollowButton(hallId: hallId, userId: userId),
                  ],
                ),
                if (hall.description != null &&
                    hall.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    hall.description!,
                    style: AppTheme.sans(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowButton extends ConsumerStatefulWidget {
  final String hallId;
  final String userId;
  const _FollowButton({required this.hallId, required this.userId});

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool _following = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkFollowing();
  }

  Future<void> _checkFollowing() async {
    final result = await ref
        .read(hallRepositoryProvider)
        .isFollowing(widget.hallId, widget.userId);
    if (mounted) setState(() {
      _following = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(width: 70, height: 30);

    return GestureDetector(
      onTap: () async {
        await ref
            .read(hallRepositoryProvider)
            .toggleFollow(widget.hallId, widget.userId);
        setState(() => _following = !_following);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _following
              ? AppTheme.sage.withValues(alpha: 0.2)
              : AppTheme.gold,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _following ? '팔로잉' : '팔로우',
          style: AppTheme.sans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _following ? AppTheme.textSecondary : AppTheme.background,
          ),
        ),
      ),
    );
  }
}

// ─── Tab Bar Delegate ───
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabBarDelegate({required this.tabBar});

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppTheme.background,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}

// ─── 게시글 목록 ───
class _PostList extends ConsumerWidget {
  final String hallId;
  final String type;
  final Hall hall;
  const _PostList(
      {required this.hallId, required this.type, required this.hall});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(
        hallPostsProvider((hallId: hallId, type: type)));

    return postsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.gold)),
      error: (e, _) => Center(
          child:
              Text('오류: $e', style: AppTheme.sans(color: AppTheme.error))),
      data: (posts) {
        final userId = FirebaseAuth.instance.currentUser?.uid;

        return Column(
          children: [
            // 글쓰기 버튼 (리뷰/토론)
            if (userId != null &&
                (type == 'review' || type == 'discussion' || type == 'photo'))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: GestureDetector(
                  onTap: () => _showWriteSheet(context, ref, userId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.sage.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.sage.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_note_rounded,
                            size: 20, color: AppTheme.textSecondary),
                        const SizedBox(width: 10),
                        Text(
                          type == 'review'
                              ? '관람 후기를 남겨보세요'
                              : type == 'photo'
                                  ? '사진을 공유해보세요'
                                  : '이야기를 나눠보세요',
                          style: AppTheme.sans(
                              fontSize: 13,
                              color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 게시글
            if (posts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Column(
                  children: [
                    Icon(
                      type == 'review'
                          ? Icons.rate_review_outlined
                          : type == 'photo'
                              ? Icons.photo_library_outlined
                              : type == 'notice'
                                  ? Icons.campaign_outlined
                                  : Icons.forum_outlined,
                      size: 48,
                      color: AppTheme.sage.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '아직 ${HallPostType.fromString(type).displayName}이 없습니다',
                      style: AppTheme.sans(
                          fontSize: 14, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: posts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      _PostCard(post: posts[i], hallId: hallId),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showWriteSheet(
      BuildContext context, WidgetRef ref, String userId) {
    final contentCtrl = TextEditingController();
    double rating = 5.0;
    final postType = HallPostType.fromString(type);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${postType.displayName} 작성',
                style: AppTheme.serif(
                    fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),

              // 별점 (리뷰만)
              if (type == 'review') ...[
                Row(
                  children: [
                    Text('별점',
                        style: AppTheme.sans(
                            fontSize: 13,
                            color: AppTheme.textSecondary)),
                    const SizedBox(width: 12),
                    for (int s = 1; s <= 5; s++)
                      GestureDetector(
                        onTap: () =>
                            setSheetState(() => rating = s.toDouble()),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(
                            s <= rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 28,
                            color: AppTheme.gold,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      rating.toStringAsFixed(0),
                      style: AppTheme.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.gold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // 내용
              TextField(
                controller: contentCtrl,
                maxLines: 5,
                style: AppTheme.sans(fontSize: 14),
                decoration: InputDecoration(
                  hintText: type == 'review'
                      ? '관람 후기를 작성해 주세요...'
                      : '내용을 입력해 주세요...',
                  hintStyle: AppTheme.sans(
                      fontSize: 13, color: AppTheme.textTertiary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: AppTheme.sage.withValues(alpha: 0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: AppTheme.sage.withValues(alpha: 0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppTheme.gold, width: 1),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 작성 버튼
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    if (contentCtrl.text.trim().isEmpty) return;

                    final user =
                        await ref.read(authServiceProvider).getAppUser(userId);

                    final post = HallPost(
                      id: '',
                      hallId: hallId,
                      userId: userId,
                      userDisplayName: user?.displayName ?? '익명',
                      userPhotoUrl: null,
                      type: postType,
                      content: contentCtrl.text.trim(),
                      rating: type == 'review' ? rating : null,
                      createdAt: DateTime.now(),
                    );

                    await ref
                        .read(hallRepositoryProvider)
                        .createPost(hallId, post);

                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: AppTheme.background,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('작성하기',
                      style: AppTheme.sans(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 게시글 카드 ───
class _PostCard extends ConsumerWidget {
  final HallPost post;
  final String hallId;
  const _PostCard({required this.post, required this.hallId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppTheme.sage.withValues(alpha: 0.1), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 작성자 정보
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor:
                    AppTheme.sage.withValues(alpha: 0.15),
                child: Text(
                  (post.userDisplayName).substring(0, 1),
                  style: AppTheme.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(post.userDisplayName,
                            style: AppTheme.sans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        if (post.type == HallPostType.notice) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('공지',
                                style: AppTheme.sans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.gold)),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          _formatDate(post.createdAt),
                          style: AppTheme.sans(
                              fontSize: 11,
                              color: AppTheme.textTertiary),
                        ),
                        if (post.eventTitle != null) ...[
                          Text(' · ',
                              style: AppTheme.sans(
                                  fontSize: 11,
                                  color: AppTheme.textTertiary)),
                          Text(post.eventTitle!,
                              style: AppTheme.sans(
                                  fontSize: 11,
                                  color: AppTheme.gold
                                      .withValues(alpha: 0.7))),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 별점 (리뷰)
              if (post.type == HallPostType.review &&
                  post.rating != null) ...[
                Icon(Icons.star_rounded,
                    size: 14, color: AppTheme.gold),
                const SizedBox(width: 2),
                Text(
                  post.rating!.toStringAsFixed(0),
                  style: AppTheme.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // 내용
          Text(
            post.content,
            style: AppTheme.sans(
                fontSize: 13,
                color: AppTheme.textPrimary,
                height: 1.5),
          ),

          // 이미지
          if (post.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: post.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: post.imageUrls[i],
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // 좋아요 + 댓글
          Row(
            children: [
              GestureDetector(
                onTap: () async {
                  if (userId == null) return;
                  await ref
                      .read(hallRepositoryProvider)
                      .toggleLike(hallId, post.id, userId);
                },
                child: Row(
                  children: [
                    Icon(Icons.favorite_border_rounded,
                        size: 18,
                        color: AppTheme.sage.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text('${post.likeCount}',
                        style: AppTheme.sans(
                            fontSize: 12,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () => _showComments(context, ref),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded,
                        size: 16,
                        color: AppTheme.sage.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text('${post.commentCount}',
                        style: AppTheme.sans(
                            fontSize: 12,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return DateFormat('MM.dd').format(dt);
  }

  void _showComments(BuildContext context, WidgetRef ref) {
    final commentCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final commentsAsync = ref.watch(
            hallCommentsProvider((hallId: hallId, postId: post.id)));

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (ctx, scrollCtrl) => Column(
            children: [
              // 핸들
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.sage.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('댓글',
                  style: AppTheme.sans(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),

              // 댓글 목록
              Expanded(
                child: commentsAsync.when(
                  loading: () => const Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.gold)),
                  error: (e, _) => Center(child: Text('오류: $e')),
                  data: (comments) {
                    if (comments.isEmpty) {
                      return Center(
                        child: Text('아직 댓글이 없습니다',
                            style: AppTheme.sans(
                                fontSize: 13,
                                color: AppTheme.textSecondary)),
                      );
                    }
                    return ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: comments.length,
                      itemBuilder: (context, i) {
                        final c = comments[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppTheme.sage
                                    .withValues(alpha: 0.15),
                                child: Text(
                                  c.userDisplayName.substring(0, 1),
                                  style: AppTheme.sans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.gold),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(c.userDisplayName,
                                            style: AppTheme.sans(
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight.w600)),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatDate(c.createdAt),
                                          style: AppTheme.sans(
                                              fontSize: 10,
                                              color:
                                                  AppTheme.textTertiary),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(c.content,
                                        style: AppTheme.sans(
                                            fontSize: 13,
                                            height: 1.4)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // 댓글 입력
              Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 8,
                  top: 8,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  border: Border(
                    top: BorderSide(
                        color: AppTheme.sage.withValues(alpha: 0.15)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: commentCtrl,
                        style: AppTheme.sans(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '댓글을 입력하세요...',
                          hintStyle: AppTheme.sans(
                              fontSize: 13,
                              color: AppTheme.textTertiary),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final uid =
                            FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null ||
                            commentCtrl.text.trim().isEmpty) return;

                        final user = await ref
                            .read(authServiceProvider)
                            .getAppUser(uid);

                        await ref.read(hallRepositoryProvider).addComment(
                              hallId,
                              post.id,
                              HallComment(
                                id: '',
                                postId: post.id,
                                userId: uid,
                                userDisplayName:
                                    user?.displayName ?? '익명',
                                content: commentCtrl.text.trim(),
                                createdAt: DateTime.now(),
                              ),
                            );

                        commentCtrl.clear();
                      },
                      icon: const Icon(Icons.send_rounded,
                          color: AppTheme.gold, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
