import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../app/admin_theme.dart';
import 'package:melon_core/data/models/venue.dart';
import 'package:melon_core/data/models/venue_request.dart';
import 'package:melon_core/data/repositories/venue_repository.dart';
import 'package:melon_core/data/repositories/venue_request_repository.dart';
import 'package:melon_core/services/auth_service.dart';
import 'package:melon_core/services/storage_service.dart';
import 'excel_seat_upload_helper.dart';
import 'widgets/seat_map_picker.dart';

/// 공연장 관리 화면 (역할 기반: superAdmin=관리+요청처리, seller=열람+요청)
class VenueManageScreen extends ConsumerStatefulWidget {
  const VenueManageScreen({super.key});

  @override
  ConsumerState<VenueManageScreen> createState() => _VenueManageScreenState();
}

class _VenueManageScreenState extends ConsumerState<VenueManageScreen>
    with SingleTickerProviderStateMixin {
  bool _showCreateForm = false;
  bool _showRequestForm = false;
  late TabController _tabController;
  bool _isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(effectiveUserProvider);
    final venuesAsync = ref.watch(venuesStreamProvider);

    return userAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AdminTheme.background,
        body: Center(
            child: CircularProgressIndicator(color: AdminTheme.gold)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AdminTheme.background,
        body: Center(
            child: Text('오류: $e',
                style: AdminTheme.sans(color: AdminTheme.error))),
      ),
      data: (user) {
        _isSuperAdmin = user?.isAdmin ?? false;
        final isSeller = user?.isSeller ?? false;

        return Scaffold(
          backgroundColor: AdminTheme.background,
          body: Column(
            children: [
              _buildAppBar(isSeller: isSeller),
              // superAdmin: tabs (공연장 목록 | 요청 관리)
              if (_isSuperAdmin && !_showCreateForm)
                _buildTabBar(),
              Expanded(
                child: venuesAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AdminTheme.gold)),
                  error: (e, _) => Center(
                      child: Text('오류: $e',
                          style:
                              AdminTheme.sans(color: AdminTheme.error))),
                  data: (venues) {
                    // superAdmin: 공연장 등록 폼
                    if (_showCreateForm && _isSuperAdmin) {
                      return _VenueCreateForm(
                        existingVenues: venues,
                        onBack: () =>
                            setState(() => _showCreateForm = false),
                        onCreated: () =>
                            setState(() => _showCreateForm = false),
                      );
                    }
                    // seller: 공연장 요청 폼
                    if (_showRequestForm && isSeller) {
                      return _VenueRequestForm(
                        sellerId: user!.id,
                        sellerName: user.sellerProfile?.businessName ??
                            user.displayName ??
                            user.email,
                        onBack: () =>
                            setState(() => _showRequestForm = false),
                        onSubmitted: () =>
                            setState(() => _showRequestForm = false),
                      );
                    }
                    // superAdmin: tab view
                    if (_isSuperAdmin) {
                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _buildVenueList(venues,
                              isSuperAdmin: true),
                          const _VenueRequestManageTab(),
                        ],
                      );
                    }
                    // seller: venue list (읽기 전용) + 내 요청 목록
                    return _SellerVenueView(
                      venues: venues,
                      sellerId: user?.id ?? '',
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AdminTheme.surface,
        border: Border(
            bottom: BorderSide(color: AdminTheme.border, width: 0.5)),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: AdminTheme.gold,
        indicatorWeight: 2,
        labelColor: AdminTheme.gold,
        unselectedLabelColor: AdminTheme.textSecondary,
        labelStyle: AdminTheme.sans(
            fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: AdminTheme.sans(
            fontSize: 13, fontWeight: FontWeight.w500),
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_city_rounded, size: 16),
                const SizedBox(width: 6),
                Text('공연장 목록',
                    style: AdminTheme.sans(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Tab(
            child: Consumer(builder: (context, ref, _) {
              final pendingAsync =
                  ref.watch(pendingVenueRequestsProvider);
              final count = pendingAsync.valueOrNull?.length ?? 0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pending_actions_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text('요청 관리',
                      style: AdminTheme.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AdminTheme.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: AdminTheme.sans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar({required bool isSeller}) {
    String title;
    if (_showCreateForm) {
      title = '공연장 등록';
    } else if (_showRequestForm) {
      title = '공연장 요청';
    } else {
      title = '공연장 관리';
    }

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 4,
        right: 16,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: AdminTheme.surface,
        border: Border(
            bottom:
                BorderSide(color: AdminTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (_showCreateForm) {
                setState(() => _showCreateForm = false);
              } else if (_showRequestForm) {
                setState(() => _showRequestForm = false);
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/');
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AdminTheme.textPrimary, size: 20),
          ),
          Expanded(
            child: Text(title, style: AdminTheme.serif(fontSize: 17)),
          ),
          // superAdmin: 공연장 등록 버튼
          if (!_showCreateForm &&
              !_showRequestForm &&
              _isSuperAdmin)
            GestureDetector(
              onTap: () => setState(() => _showCreateForm = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  gradient: AdminTheme.goldGradient,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded,
                        size: 16, color: AdminTheme.onAccent),
                    const SizedBox(width: 4),
                    Text(
                      '공연장 등록',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.onAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // seller: 공연장 요청 버튼
          if (!_showCreateForm &&
              !_showRequestForm &&
              isSeller &&
              !_isSuperAdmin)
            GestureDetector(
              onTap: () => setState(() => _showRequestForm = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  gradient: AdminTheme.goldGradient,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.send_rounded,
                        size: 14, color: AdminTheme.onAccent),
                    const SizedBox(width: 4),
                    Text(
                      '새 공연장 요청',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.onAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVenueList(List<Venue> venues,
      {bool isSuperAdmin = false}) {
    if (venues.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AdminTheme.gold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_city_rounded,
                  size: 36, color: AdminTheme.gold),
            ),
            const SizedBox(height: 16),
            Text(
              '등록된 공연장이 없습니다',
              style: AdminTheme.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AdminTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSuperAdmin
                  ? '공연장을 등록하면 공연 등록 시 선택할 수 있습니다'
                  : '아직 등록된 공연장이 없습니다',
              style: AdminTheme.sans(
                fontSize: 13,
                color: AdminTheme.textTertiary,
              ),
            ),
            if (isSuperAdmin) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () =>
                    setState(() => _showCreateForm = true),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('첫 공연장 등록하기',
                    style: AdminTheme.sans(
                        fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTheme.gold,
                  foregroundColor: AdminTheme.onAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final fmt = NumberFormat('#,###');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: venues.length,
      itemBuilder: (context, index) {
        final venue = venues[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.surface,
              border: Border.all(
                  color: AdminTheme.sage.withValues(alpha: 0.15),
                  width: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
            child: InkWell(
              onTap: () => _showVenueDetail(venue),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color:
                          AdminTheme.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                        Icons.location_city_rounded,
                        size: 24,
                        color: AdminTheme.gold),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                venue.name,
                                style: AdminTheme.sans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      AdminTheme.textPrimary,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (venue.seatMapImageUrl !=
                                        null &&
                                    venue.seatMapImageUrl!
                                        .isNotEmpty)
                                  Container(
                                    margin:
                                        const EdgeInsets.only(
                                            right: 4),
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 6,
                                        vertical: 2),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: AdminTheme
                                              .sage
                                              .withValues(
                                                  alpha: 0.4),
                                          width: 0.5),
                                      borderRadius:
                                          BorderRadius
                                              .circular(2),
                                    ),
                                    child: Text('2D VIEW',
                                        style:
                                            AdminTheme.label(
                                          fontSize: 8,
                                          color: AdminTheme
                                              .textSecondary,
                                        )),
                                  ),
                                if (venue.hasSeatView)
                                  Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 6,
                                        vertical: 2),
                                    decoration: BoxDecoration(
                                      gradient: AdminTheme
                                          .goldGradient,
                                      borderRadius:
                                          BorderRadius
                                              .circular(2),
                                    ),
                                    child: Text('3D VIEW',
                                        style:
                                            AdminTheme.label(
                                          fontSize: 8,
                                          color: AdminTheme
                                              .onAccent,
                                        )),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${fmt.format(venue.totalSeats)}석 · ${venue.floors.length}층'
                          '${venue.address != null ? ' · ${venue.address}' : ''}',
                          style: AdminTheme.sans(
                            fontSize: 12,
                            color: AdminTheme.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: venue.availableGrades
                              .map((g) => Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 6,
                                        vertical: 1),
                                    decoration: BoxDecoration(
                                      color:
                                          AdminTheme.surface,
                                      borderRadius:
                                          BorderRadius
                                              .circular(4),
                                    ),
                                    child: Text(g,
                                        style:
                                            AdminTheme.sans(
                                          fontSize: 10,
                                          color: AdminTheme
                                              .textSecondary,
                                        )),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  if (isSuperAdmin)
                    const Icon(Icons.chevron_right_rounded,
                        color: AdminTheme.textTertiary,
                        size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showVenueDetail(Venue venue) {
    context.go('/venues/${venue.id}');
  }
}

// =============================================================================
// 셀러 공연장 뷰: 공연장 목록(읽기 전용) + 내 요청 목록
// =============================================================================

class _SellerVenueView extends ConsumerWidget {
  final List<Venue> venues;
  final String sellerId;

  const _SellerVenueView({
    required this.venues,
    required this.sellerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myRequestsAsync =
        ref.watch(sellerVenueRequestsProvider(sellerId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 내 요청 현황
          myRequestsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (requests) {
              if (requests.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('내 요청 현황',
                      style: AdminTheme.label(fontSize: 11)),
                  const SizedBox(height: 10),
                  ...requests.map((r) => _buildRequestCard(r)),
                  const SizedBox(height: 20),
                  Container(
                    height: 0.5,
                    color: AdminTheme.border,
                  ),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
          // 공연장 목록 (읽기 전용)
          Text('전체 공연장', style: AdminTheme.label(fontSize: 11)),
          const SizedBox(height: 10),
          if (venues.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  '등록된 공연장이 없습니다',
                  style: AdminTheme.sans(
                    fontSize: 14,
                    color: AdminTheme.textSecondary,
                  ),
                ),
              ),
            )
          else
            ...venues.map((v) => _buildVenueReadOnlyCard(v)),
        ],
      ),
    );
  }

  Widget _buildRequestCard(VenueRequest r) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (r.status) {
      case 'approved':
        statusColor = AdminTheme.success;
        statusLabel = '승인됨';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'rejected':
        statusColor = AdminTheme.error;
        statusLabel = '거절됨';
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        statusColor = AdminTheme.warning;
        statusLabel = '대기중';
        statusIcon = Icons.hourglass_top_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        border: Border.all(
            color: statusColor.withValues(alpha: 0.3), width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 20, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.venueName,
                    style: AdminTheme.sans(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${r.address} / ${NumberFormat('#,###').format(r.seatCount)}석',
                  style: AdminTheme.sans(
                      fontSize: 12, color: AdminTheme.textTertiary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(statusLabel,
                style: AdminTheme.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildVenueReadOnlyCard(Venue venue) {
    final fmt = NumberFormat('#,###');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        border: Border.all(
            color: AdminTheme.sage.withValues(alpha: 0.15),
            width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AdminTheme.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.location_city_rounded,
                size: 20, color: AdminTheme.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(venue.name,
                    style: AdminTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${fmt.format(venue.totalSeats)}석 · ${venue.floors.length}층'
                  '${venue.address != null ? ' · ${venue.address}' : ''}',
                  style: AdminTheme.sans(
                      fontSize: 12,
                      color: AdminTheme.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 셀러 공연장 요청 폼
// =============================================================================

class _VenueRequestForm extends ConsumerStatefulWidget {
  final String sellerId;
  final String sellerName;
  final VoidCallback onBack;
  final VoidCallback onSubmitted;

  const _VenueRequestForm({
    required this.sellerId,
    required this.sellerName,
    required this.onBack,
    required this.onSubmitted,
  });

  @override
  ConsumerState<_VenueRequestForm> createState() =>
      _VenueRequestFormState();
}

class _VenueRequestFormState
    extends ConsumerState<_VenueRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _venueNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _seatCountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _venueNameCtrl.dispose();
    _addressCtrl.dispose();
    _seatCountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final repo = ref.read(venueRequestRepositoryProvider);
      await repo.createRequest(VenueRequest(
        id: '',
        sellerId: widget.sellerId,
        sellerName: widget.sellerName,
        venueName: _venueNameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        seatCount: int.tryParse(_seatCountCtrl.text.trim()) ?? 0,
        description: _descCtrl.text.trim().isNotEmpty
            ? _descCtrl.text.trim()
            : null,
        requestedAt: DateTime.now(),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공연장 요청이 제출되었습니다')),
        );
        widget.onSubmitted();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('오류: $e'),
              backgroundColor: AdminTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AdminTheme.info.withValues(alpha: 0.1),
                border: Border.all(
                    color: AdminTheme.info.withValues(alpha: 0.3),
                    width: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 18, color: AdminTheme.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '공연장 등록 요청은 슈퍼어드민의 승인 후 반영됩니다.',
                      style: AdminTheme.sans(
                          fontSize: 13, color: AdminTheme.info),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('공연장명 *',
                style: AdminTheme.label(fontSize: 11)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _venueNameCtrl,
              style: AdminTheme.sans(fontSize: 14),
              decoration: const InputDecoration(
                  hintText: '예: 세종문화회관 대극장'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? '공연장명을 입력해주세요'
                  : null,
            ),
            const SizedBox(height: 20),
            Text('주소 *',
                style: AdminTheme.label(fontSize: 11)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _addressCtrl,
              style: AdminTheme.sans(fontSize: 14),
              decoration:
                  const InputDecoration(hintText: '예: 서울특별시 종로구'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? '주소를 입력해주세요'
                  : null,
            ),
            const SizedBox(height: 20),
            Text('총 좌석 수 *',
                style: AdminTheme.label(fontSize: 11)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _seatCountCtrl,
              style: AdminTheme.sans(fontSize: 14),
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(hintText: '예: 3022'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return '좌석 수를 입력해주세요';
                }
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) return '유효한 숫자를 입력해주세요';
                return null;
              },
            ),
            const SizedBox(height: 20),
            Text('추가 설명 (선택)',
                style: AdminTheme.label(fontSize: 11)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descCtrl,
              style: AdminTheme.sans(fontSize: 14),
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '공연장에 대한 추가 정보 (층 구조, 좌석 등급 등)',
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _submitting ? null : widget.onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminTheme.textPrimary,
                      side: const BorderSide(
                          color: AdminTheme.border, width: 0.5),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(4)),
                    ),
                    child: Text('취소',
                        style: AdminTheme.sans(
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.gold,
                      foregroundColor: AdminTheme.onAccent,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(4)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AdminTheme.onAccent),
                          )
                        : Text('요청 제출',
                            style: AdminTheme.sans(
                                fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// SuperAdmin 공연장 요청 관리 탭
// =============================================================================

class _VenueRequestManageTab extends ConsumerWidget {
  const _VenueRequestManageTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(allVenueRequestsProvider);

    return requestsAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AdminTheme.gold)),
      error: (e, _) => Center(
          child: Text('오류: $e',
              style: AdminTheme.sans(color: AdminTheme.error))),
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color:
                        AdminTheme.gold.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                      Icons.pending_actions_rounded,
                      size: 36,
                      color: AdminTheme.gold),
                ),
                const SizedBox(height: 16),
                Text(
                  '공연장 요청이 없습니다',
                  style: AdminTheme.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '셀러가 공연장 등록을 요청하면 여기에 표시됩니다',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              ],
            ),
          );
        }

        // 대기중을 상단에 배치
        final pending =
            requests.where((r) => r.isPending).toList();
        final resolved =
            requests.where((r) => !r.isPending).toList();
        final sorted = [...pending, ...resolved];

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final r = sorted[index];
            return _VenueRequestCard(request: r);
          },
        );
      },
    );
  }
}

class _VenueRequestCard extends ConsumerStatefulWidget {
  final VenueRequest request;
  const _VenueRequestCard({required this.request});

  @override
  ConsumerState<_VenueRequestCard> createState() =>
      _VenueRequestCardState();
}

class _VenueRequestCardState
    extends ConsumerState<_VenueRequestCard> {
  bool _processing = false;

  Future<void> _approve() async {
    setState(() => _processing = true);
    try {
      final user = ref.read(effectiveUserProvider).value;
      final repo = ref.read(venueRequestRepositoryProvider);
      await repo.approveRequest(
        requestId: widget.request.id,
        approvedBy: user?.email ?? 'superAdmin',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${widget.request.venueName} 공연장이 승인 및 생성되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('오류: $e'),
              backgroundColor: AdminTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _processing = true);
    try {
      final user = ref.read(effectiveUserProvider).value;
      final repo = ref.read(venueRequestRepositoryProvider);
      await repo.rejectRequest(
        requestId: widget.request.id,
        rejectedBy: user?.email ?? 'superAdmin',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${widget.request.venueName} 요청이 거절되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('오류: $e'),
              backgroundColor: AdminTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final fmt = NumberFormat('#,###');
    final dateFmt = DateFormat('yyyy.MM.dd HH:mm');

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (r.status) {
      case 'approved':
        statusColor = AdminTheme.success;
        statusLabel = '승인됨';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'rejected':
        statusColor = AdminTheme.error;
        statusLabel = '거절됨';
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        statusColor = AdminTheme.warning;
        statusLabel = '대기중';
        statusIcon = Icons.hourglass_top_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        border: Border.all(
          color: r.isPending
              ? AdminTheme.warning.withValues(alpha: 0.4)
              : AdminTheme.sage.withValues(alpha: 0.15),
          width: r.isPending ? 1 : 0.5,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 이름 + 상태 뱃지
          Row(
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.venueName,
                    style: AdminTheme.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(statusLabel,
                    style: AdminTheme.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 정보
          _infoRow('요청자', r.sellerName),
          _infoRow('주소', r.address),
          _infoRow('좌석 수', '${fmt.format(r.seatCount)}석'),
          if (r.description != null && r.description!.isNotEmpty)
            _infoRow('설명', r.description!),
          _infoRow('요청일', dateFmt.format(r.requestedAt)),
          if (r.resolvedAt != null)
            _infoRow('처리일', dateFmt.format(r.resolvedAt!)),
          if (r.resolvedBy != null)
            _infoRow('처리자', r.resolvedBy!),
          // 대기중일 때 승인/거절 버튼
          if (r.isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _processing ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminTheme.error,
                      side: BorderSide(
                          color: AdminTheme.error
                              .withValues(alpha: 0.5),
                          width: 0.5),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(2)),
                    ),
                    child: _processing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AdminTheme.error))
                        : Text('거절',
                            style: AdminTheme.sans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AdminTheme.error)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _processing ? null : _approve,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(2)),
                    ),
                    child: _processing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : Text('승인',
                            style: AdminTheme.sans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textTertiary)),
          ),
          Expanded(
            child: Text(value,
                style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textPrimary)),
          ),
        ],
      ),
    );
  }
}

int _layoutDraftSeed = 0;

String _nextLayoutDraftId() =>
    'layout_${DateTime.now().microsecondsSinceEpoch}_${_layoutDraftSeed++}';

const String _stageTop = 'top';
const String _stageBottom = 'bottom';
const String _layoutHorizontal = 'horizontal';
const String _layoutVertical = 'vertical';
const int _layoutRowMin = 0;
const int _layoutRowMax = 6;
const int _layoutOffsetMin = -16;
const int _layoutOffsetMax = 16;

String _normalizeStagePosition(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  return normalized == _stageBottom ? _stageBottom : _stageTop;
}

String _stagePositionLabel(String value) {
  return _normalizeStagePosition(value) == _stageBottom ? '하단' : '상단';
}

String _normalizeLayoutDirection(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  return normalized == _layoutVertical ? _layoutVertical : _layoutHorizontal;
}

String _layoutDirectionLabel(String value) {
  return _normalizeLayoutDirection(value) == _layoutVertical ? '세로형' : '가로형';
}

Color _gradeColorForLayout(String? grade) {
  final normalized = (grade ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'VIP':
      return const Color(0xFFC9A84C);
    case 'R':
      return const Color(0xFF30D158);
    case 'S':
      return const Color(0xFF0A84FF);
    case 'A':
      return const Color(0xFFFF9F0A);
    default:
      return AdminTheme.info;
  }
}

String _displayFloorLabel(String floorName, int index) {
  final digits = RegExp(r'(\d+)').firstMatch(floorName);
  if (digits != null) {
    return '${digits.group(1)}F';
  }
  if (floorName.contains('지하')) {
    final basementDigits = RegExp(r'지하\s*(\d+)').firstMatch(floorName);
    if (basementDigits != null) {
      return 'B${basementDigits.group(1)}';
    }
    return 'B${index + 1}';
  }
  return floorName;
}

class _VenueLayoutEditorResult {
  final List<VenueFloor> floors;
  final String stagePosition;

  const _VenueLayoutEditorResult({
    required this.floors,
    required this.stagePosition,
  });
}

class _LayoutCustomRowDraft {
  final String id;
  String name;
  int seatCount;
  int offset;

  _LayoutCustomRowDraft({
    required this.id,
    required this.name,
    required this.seatCount,
    this.offset = 0,
  });
}

class _LayoutBlockDraft {
  final String id;
  String name;
  int rows;
  int seatsPerRow;
  String? grade;
  int layoutRow;
  int layoutOffset;
  String layoutDirection;
  bool useCustomRows;
  final List<_LayoutCustomRowDraft> customRows;

  _LayoutBlockDraft({
    required this.id,
    required this.name,
    required this.rows,
    required this.seatsPerRow,
    this.grade,
    this.layoutRow = 0,
    this.layoutOffset = 0,
    this.layoutDirection = 'horizontal',
    this.useCustomRows = false,
    List<_LayoutCustomRowDraft>? customRows,
  }) : customRows = customRows ?? [];
}

int _draftBlockTotalSeats(_LayoutBlockDraft block) {
  if (block.useCustomRows && block.customRows.isNotEmpty) {
    return block.customRows.fold<int>(0, (sum, row) => sum + row.seatCount);
  }
  return block.rows * block.seatsPerRow;
}

int _draftBlockRows(_LayoutBlockDraft block) {
  if (block.useCustomRows && block.customRows.isNotEmpty) {
    return block.customRows.length;
  }
  return block.rows;
}

int _draftBlockMaxSeatsPerRow(_LayoutBlockDraft block) {
  if (block.useCustomRows && block.customRows.isNotEmpty) {
    return block.customRows.fold<int>(
      0,
      (maxValue, row) => row.seatCount > maxValue ? row.seatCount : maxValue,
    );
  }
  return block.seatsPerRow;
}

List<VenueBlockCustomRow> _toCustomRows(_LayoutBlockDraft block) {
  if (!block.useCustomRows || block.customRows.isEmpty) {
    return const <VenueBlockCustomRow>[];
  }
  return block.customRows.asMap().entries.map((entry) {
    final index = entry.key;
    final row = entry.value;
    final rowName = row.name.trim().isEmpty ? '${index + 1}' : row.name.trim();
    return VenueBlockCustomRow(
      name: rowName,
      seatCount: row.seatCount,
      offset: row.offset,
    );
  }).toList();
}

class _LayoutFloorDraft {
  final String id;
  String name;
  final List<_LayoutBlockDraft> blocks;

  _LayoutFloorDraft({
    required this.id,
    required this.name,
    required this.blocks,
  });
}

List<_LayoutFloorDraft> _toLayoutDrafts(List<VenueFloor> floors) {
  return floors
      .map(
        (floor) => _LayoutFloorDraft(
          id: _nextLayoutDraftId(),
          name: floor.name,
          blocks: floor.blocks
              .map(
                (block) => _LayoutBlockDraft(
                  id: _nextLayoutDraftId(),
                  name: block.name,
                  rows: block.rows,
                  seatsPerRow: block.seatsPerRow,
                  grade: block.grade,
                  layoutRow: block.layoutRow,
                  layoutOffset: block.layoutOffset,
                  layoutDirection: _normalizeLayoutDirection(
                    block.layoutDirection,
                  ),
                  useCustomRows: block.customRows.isNotEmpty,
                  customRows: block.customRows
                      .map(
                        (row) => _LayoutCustomRowDraft(
                          id: _nextLayoutDraftId(),
                          name: row.name,
                          seatCount: row.seatCount,
                          offset: row.offset,
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
        ),
      )
      .toList();
}

List<VenueFloor> _toVenueFloors(List<_LayoutFloorDraft> drafts) {
  return drafts.map((floorDraft) {
    final blocks = floorDraft.blocks.map(
      (blockDraft) {
        final customRows = _toCustomRows(blockDraft);
        final rows =
            customRows.isNotEmpty ? customRows.length : blockDraft.rows;
        final seatsPerRow = customRows.isNotEmpty
            ? customRows.fold<int>(
                0,
                (maxValue, row) =>
                    row.seatCount > maxValue ? row.seatCount : maxValue,
              )
            : blockDraft.seatsPerRow;
        final totalSeats = customRows.isNotEmpty
            ? customRows.fold<int>(0, (sum, row) => sum + row.seatCount)
            : blockDraft.rows * blockDraft.seatsPerRow;
        return VenueBlock(
          name: blockDraft.name.trim(),
          rows: rows,
          seatsPerRow: seatsPerRow,
          totalSeats: totalSeats,
          grade: (blockDraft.grade?.trim().isNotEmpty ?? false)
              ? blockDraft.grade!.trim()
              : null,
          layoutRow: blockDraft.layoutRow,
          layoutOffset: blockDraft.layoutOffset,
          layoutDirection: _normalizeLayoutDirection(
            blockDraft.layoutDirection,
          ),
          customRows: customRows,
        );
      },
    ).toList();
    final floorTotalSeats =
        blocks.fold<int>(0, (sum, block) => sum + block.totalSeats);
    return VenueFloor(
      name: floorDraft.name.trim(),
      blocks: blocks,
      totalSeats: floorTotalSeats,
    );
  }).toList();
}

int _calcTotalSeats(List<VenueFloor> floors) {
  return floors.fold<int>(0, (sum, floor) => sum + floor.totalSeats);
}

String? _validateLayoutDrafts(List<_LayoutFloorDraft> drafts) {
  if (drafts.isEmpty) {
    return '층을 1개 이상 추가해주세요';
  }
  for (final floor in drafts) {
    if (floor.name.trim().isEmpty) {
      return '층 이름을 입력해주세요';
    }
    if (floor.blocks.isEmpty) {
      return '${floor.name}에 구역을 1개 이상 추가해주세요';
    }
    for (final block in floor.blocks) {
      if (block.name.trim().isEmpty) {
        return '${floor.name}의 구역명을 입력해주세요';
      }
      if (block.useCustomRows) {
        if (block.customRows.isEmpty) {
          return '${floor.name} ${block.name} 구역의 행 데이터를 1개 이상 추가해주세요';
        }
        for (final row in block.customRows) {
          if (row.seatCount <= 0) {
            return '${floor.name} ${block.name} 구역 행 좌석 수는 1 이상이어야 합니다';
          }
        }
      } else if (block.rows <= 0 || block.seatsPerRow <= 0) {
        return '${floor.name} ${block.name} 구역의 행/좌석 수는 1 이상이어야 합니다';
      }
    }
  }
  return null;
}

// =============================================================================
// 좌석 구조 편집 바텀시트
// =============================================================================

class _VenueLayoutEditorSheet extends StatefulWidget {
  final String venueName;
  final List<VenueFloor> initialFloors;
  final String initialStagePosition;

  const _VenueLayoutEditorSheet({
    required this.venueName,
    required this.initialFloors,
    required this.initialStagePosition,
  });

  @override
  State<_VenueLayoutEditorSheet> createState() =>
      _VenueLayoutEditorSheetState();
}

class _VenueLayoutEditorSheetState extends State<_VenueLayoutEditorSheet> {
  late List<_LayoutFloorDraft> _drafts;
  late String _stagePosition;
  final Map<String, Offset> _dragStartGlobal = <String, Offset>{};
  final Map<String, int> _dragStartRow = <String, int>{};
  final Map<String, int> _dragStartOffset = <String, int>{};

  @override
  void initState() {
    super.initState();
    _drafts = _toLayoutDrafts(widget.initialFloors);
    _stagePosition = _normalizeStagePosition(widget.initialStagePosition);
    if (_drafts.isEmpty) {
      _drafts = [
        _LayoutFloorDraft(
          id: _nextLayoutDraftId(),
          name: '1층',
          blocks: [
            _LayoutBlockDraft(
              id: _nextLayoutDraftId(),
              name: 'A',
              rows: 10,
              seatsPerRow: 10,
            ),
          ],
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktopEditor = screenSize.width >= 1100;
    final totalSeats = _toVenueFloors(_drafts)
        .fold<int>(0, (sum, floor) => sum + floor.totalSeats);
    final blockCount =
        _drafts.fold<int>(0, (sum, floor) => sum + floor.blocks.length);

    return Container(
      height: screenSize.height * (isDesktopEditor ? 0.94 : 0.88),
      decoration: const BoxDecoration(
        color: AdminTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AdminTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '좌석 구조 편집',
                        style: AdminTheme.serif(fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.venueName,
                        style: AdminTheme.sans(
                          fontSize: 12,
                          color: AdminTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AdminTheme.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Text(
                    '닫기',
                    style: AdminTheme.sans(
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AdminTheme.border, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminTheme.surface,
                      border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _metric('층', '${_drafts.length}')),
                        Expanded(child: _metric('구역', '$blockCount')),
                        Expanded(
                            child: _metric('총 좌석',
                                '${NumberFormat('#,###').format(totalSeats)}석')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminTheme.surface,
                      border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '무대 위치',
                          style: AdminTheme.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AdminTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('상단'),
                              selected: _stagePosition == _stageTop,
                              onSelected: (_) =>
                                  setState(() => _stagePosition = _stageTop),
                            ),
                            ChoiceChip(
                              label: const Text('하단'),
                              selected: _stagePosition == _stageBottom,
                              onSelected: (_) =>
                                  setState(() => _stagePosition = _stageBottom),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._drafts.map((floor) => _buildFloorCard(floor)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _addFloor,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminTheme.textPrimary,
                        side: const BorderSide(color: AdminTheme.border, width: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '층 추가',
                            style:
                                AdminTheme.sans(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            decoration: const BoxDecoration(
              color: AdminTheme.surface,
              border:
                  Border(top: BorderSide(color: AdminTheme.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminTheme.textPrimary,
                      side: const BorderSide(color: AdminTheme.border, width: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      '취소',
                      style: AdminTheme.sans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _applyLayout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.gold,
                      foregroundColor: AdminTheme.onAccent,
                    ),
                    child: Text(
                      '적용',
                      style: AdminTheme.sans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AdminTheme.sans(
            fontSize: 11,
            color: AdminTheme.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AdminTheme.sans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AdminTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildFloorCard(_LayoutFloorDraft floor) {
    final floorSeatCount = floor.blocks.fold<int>(
      0,
      (sum, block) => sum + _draftBlockTotalSeats(block),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AdminTheme.surface,
          border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('${floor.id}-name'),
                  initialValue: floor.name,
                  onChanged: (value) => floor.name = value,
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: '층 이름',
                    labelStyle: AdminTheme.sans(
                      color: AdminTheme.textTertiary,
                      fontSize: 12,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AdminTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide:
                          const BorderSide(color: AdminTheme.border, width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide:
                          const BorderSide(color: AdminTheme.border, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide:
                          const BorderSide(color: AdminTheme.gold, width: 1),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AdminTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${NumberFormat('#,###').format(floorSeatCount)}석',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.gold,
                  ),
                ),
              ),
              IconButton(
                onPressed:
                    _drafts.length == 1 ? null : () => _removeFloor(floor),
                icon: const Icon(Icons.delete_outline_rounded),
                color: AdminTheme.error,
                tooltip: '층 삭제',
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...floor.blocks.map((block) => _buildBlockCard(floor, block)),
          const SizedBox(height: 6),
          _buildBlockDragCanvas(floor),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _addBlock(floor),
              style: TextButton.styleFrom(
                foregroundColor: AdminTheme.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '구역 추가',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBlockDragCanvas(_LayoutFloorDraft floor) {
    final stageOnTop = _stagePosition == _stageTop;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktopEditor = screenWidth >= 1100;
    final canvasHeight = isDesktopEditor
        ? (floor.blocks.length >= 6 ? 420.0 : 360.0)
        : (floor.blocks.length >= 6 ? 320.0 : 280.0);
    const stageHeight = 34.0;
    const stageWidth = 180.0;
    const blockWidth = 112.0;
    const blockHeight = 52.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '구역 배치 드래그',
                style: AdminTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '블록을 끌어서 이동',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final rowRange = math.max(1, _layoutRowMax - _layoutRowMin);
              final chartTop = stageOnTop ? stageHeight + 18 : 8.0;
              final chartBottom = stageOnTop ? 8.0 : stageHeight + 18;
              final chartHeight =
                  math.max(72.0, canvasHeight - chartTop - chartBottom);
              const horizontalSlots = _layoutOffsetMax - _layoutOffsetMin + 2;
              final xStep = math.max(
                8.0,
                (width - blockWidth - 24) / horizontalSlots,
              );
              final yStep = chartHeight / rowRange;

              double rowY(int row) {
                final clamped = row < _layoutRowMin
                    ? _layoutRowMin
                    : (row > _layoutRowMax ? _layoutRowMax : row);
                final normalized = (clamped - _layoutRowMin) / rowRange;
                return stageOnTop
                    ? chartTop + (normalized * chartHeight)
                    : chartTop + ((1 - normalized) * chartHeight);
              }

              double centerX(int offset) {
                final clamped = offset < _layoutOffsetMin
                    ? _layoutOffsetMin
                    : (offset > _layoutOffsetMax ? _layoutOffsetMax : offset);
                return (width / 2) + (clamped * xStep);
              }

              return SizedBox(
                height: canvasHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AdminTheme.card,
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: AdminTheme.border, width: 0.5),
                        ),
                      ),
                    ),
                    ...List.generate(rowRange + 1, (idx) {
                      final row = _layoutRowMin + idx;
                      final y = rowY(row);
                      return Positioned(
                        left: 8,
                        right: 8,
                        top: y,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              child: Text(
                                '${row + 1}',
                                style: AdminTheme.sans(
                                  fontSize: 9,
                                  color: AdminTheme.textTertiary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: AdminTheme.border.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    Positioned(
                      top: stageOnTop ? 8 : null,
                      bottom: stageOnTop ? null : 8,
                      left: (width - stageWidth) / 2,
                      child: Container(
                        width: stageWidth,
                        height: stageHeight,
                        decoration: BoxDecoration(
                          color: AdminTheme.sage,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'STAGE',
                          style: AdminTheme.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AdminTheme.onAccent,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                    ...floor.blocks.map((block) {
                      final gradeColor = _gradeColorForLayout(block.grade);
                      final seatText = NumberFormat('#,###')
                          .format(_draftBlockTotalSeats(block));
                      final gradeLabel =
                          (block.grade?.trim().isNotEmpty ?? false)
                              ? block.grade!.trim().toUpperCase()
                              : '미지정';
                      final x = centerX(block.layoutOffset);
                      final y = rowY(block.layoutRow);
                      final left = (x - (blockWidth / 2))
                          .clamp(0.0, math.max(0.0, width - blockWidth))
                          .toDouble();
                      final top = (y - (blockHeight / 2))
                          .clamp(0.0, math.max(0.0, canvasHeight - blockHeight))
                          .toDouble();
                      return Positioned(
                        left: left,
                        top: top,
                        width: blockWidth,
                        height: blockHeight,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: GestureDetector(
                            onPanStart: (details) =>
                                _startBlockDrag(block, details),
                            onPanUpdate: (details) => _updateBlockDrag(
                              block,
                              details,
                              stageOnTop: stageOnTop,
                              xStep: xStep,
                              yStep: yStep,
                            ),
                            onPanEnd: (_) => _endBlockDrag(block),
                            onPanCancel: () => _endBlockDrag(block),
                            child: Container(
                              decoration: BoxDecoration(
                                color: gradeColor.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: gradeColor, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: AdminTheme.sage.withValues(alpha: 0.2),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    block.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AdminTheme.sans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      height: 1.0,
                                      color: AdminTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$gradeLabel · $seatText석',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AdminTheme.sans(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      height: 1.0,
                                      color: AdminTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _startBlockDrag(_LayoutBlockDraft block, DragStartDetails details) {
    _dragStartGlobal[block.id] = details.globalPosition;
    _dragStartRow[block.id] = block.layoutRow;
    _dragStartOffset[block.id] = block.layoutOffset;
  }

  void _updateBlockDrag(
    _LayoutBlockDraft block,
    DragUpdateDetails details, {
    required bool stageOnTop,
    required double xStep,
    required double yStep,
  }) {
    final startGlobal = _dragStartGlobal[block.id];
    final startRow = _dragStartRow[block.id];
    final startOffset = _dragStartOffset[block.id];
    if (startGlobal == null || startRow == null || startOffset == null) {
      return;
    }

    final dx = details.globalPosition.dx - startGlobal.dx;
    final dy = details.globalPosition.dy - startGlobal.dy;
    final offsetDelta = (dx / math.max(1, xStep)).round();
    final visualRowDelta = (dy / math.max(1, yStep)).round();
    final stageRowDelta = stageOnTop ? visualRowDelta : -visualRowDelta;

    var nextOffset = startOffset + offsetDelta;
    if (nextOffset < _layoutOffsetMin) nextOffset = _layoutOffsetMin;
    if (nextOffset > _layoutOffsetMax) nextOffset = _layoutOffsetMax;

    var nextRow = startRow + stageRowDelta;
    if (nextRow < _layoutRowMin) nextRow = _layoutRowMin;
    if (nextRow > _layoutRowMax) nextRow = _layoutRowMax;

    if (nextOffset == block.layoutOffset && nextRow == block.layoutRow) {
      return;
    }

    setState(() {
      block.layoutOffset = nextOffset;
      block.layoutRow = nextRow;
    });
  }

  void _endBlockDrag(_LayoutBlockDraft block) {
    _dragStartGlobal.remove(block.id);
    _dragStartRow.remove(block.id);
    _dragStartOffset.remove(block.id);
  }

  Widget _buildBlockCard(_LayoutFloorDraft floor, _LayoutBlockDraft block) {
    final seatCount = _draftBlockTotalSeats(block);
    final rowCount = _draftBlockRows(block);
    final maxSeatsPerRow = _draftBlockMaxSeatsPerRow(block);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('${block.id}-name'),
                  initialValue: block.name,
                  onChanged: (value) => block.name = value,
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: _fieldDecoration('구역명'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextFormField(
                  key: ValueKey('${block.id}-grade'),
                  initialValue: block.grade ?? '',
                  onChanged: (value) => block.grade = value,
                  style: AdminTheme.sans(
                    fontSize: 13,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: _fieldDecoration('등급'),
                ),
              ),
              IconButton(
                onPressed: floor.blocks.length == 1
                    ? null
                    : () => _removeBlock(floor, block),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                color: AdminTheme.error,
                tooltip: '구역 삭제',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '자유 편집 모드',
                style: AdminTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Switch(
                value: block.useCustomRows,
                onChanged: (enabled) => _toggleCustomRowMode(block, enabled),
                activeThumbColor: AdminTheme.gold,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (block.useCustomRows) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminTheme.surface,
                border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _pill('${block.customRows.length}행'),
                      const SizedBox(width: 6),
                      _pill('${NumberFormat('#,###').format(seatCount)}석'),
                      const SizedBox(width: 6),
                      _pill('행 이동/추가 가능'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...block.customRows.asMap().entries.map(
                        (entry) => _buildCustomRowEditor(
                          block,
                          entry.key,
                          entry.value,
                        ),
                      ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _addCustomRow(block),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminTheme.textPrimary,
                        side: const BorderSide(color: AdminTheme.border, width: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '행 추가',
                            style:
                                AdminTheme.sans(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('${block.id}-rows'),
                    initialValue: block.rows.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      block.rows = int.tryParse(value) ?? 0;
                      setState(() {});
                    },
                    style: AdminTheme.sans(
                      fontSize: 13,
                      color: AdminTheme.textPrimary,
                    ),
                    decoration: _fieldDecoration('행 수'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('${block.id}-seats-per-row'),
                    initialValue: block.seatsPerRow.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      block.seatsPerRow = int.tryParse(value) ?? 0;
                      setState(() {});
                    },
                    style: AdminTheme.sans(
                      fontSize: 13,
                      color: AdminTheme.textPrimary,
                    ),
                    decoration: _fieldDecoration('행당 좌석'),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AdminTheme.card,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${NumberFormat('#,###').format(seatCount)}석',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '배치 방향',
                style: AdminTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('가로형'),
                selected: _normalizeLayoutDirection(block.layoutDirection) ==
                    _layoutHorizontal,
                onSelected: block.useCustomRows
                    ? null
                    : (_) => setState(
                          () => block.layoutDirection = _layoutHorizontal,
                        ),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('세로형'),
                selected: _normalizeLayoutDirection(block.layoutDirection) ==
                    _layoutVertical,
                onSelected: block.useCustomRows
                    ? null
                    : (_) => setState(
                          () => block.layoutDirection = _layoutVertical,
                        ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              block.useCustomRows
                  ? '자유 편집 모드에서는 행 위치/좌석 수를 직접 조정합니다'
                  : '기본 구성: ${block.rows}행 · 행당 ${block.seatsPerRow}석 · 배치는 드래그 화면에서 이동',
              style: AdminTheme.sans(
                fontSize: 10,
                color: AdminTheme.textTertiary,
              ),
            ),
          ),
          if (block.useCustomRows)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '현재 요약: $rowCount행 · 최대 $maxSeatsPerRow석/행 · 총 ${NumberFormat('#,###').format(seatCount)}석',
                  style: AdminTheme.sans(
                    fontSize: 10,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text,
        style: AdminTheme.sans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AdminTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildCustomRowEditor(
      _LayoutBlockDraft block, int index, _LayoutCustomRowDraft row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('${row.id}-name'),
                  initialValue: row.name,
                  onChanged: (value) => row.name = value,
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: _fieldDecoration('행 라벨'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextFormField(
                  key: ValueKey('${row.id}-seat-count'),
                  initialValue: row.seatCount.toString(),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    row.seatCount = int.tryParse(value) ?? 0;
                    setState(() {});
                  },
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textPrimary,
                  ),
                  decoration: _fieldDecoration('좌석 수'),
                ),
              ),
              IconButton(
                onPressed:
                    index == 0 ? null : () => _moveCustomRow(block, index, -1),
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                tooltip: '위로 이동',
              ),
              IconButton(
                onPressed: index == block.customRows.length - 1
                    ? null
                    : () => _moveCustomRow(block, index, 1),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                tooltip: '아래로 이동',
              ),
              IconButton(
                onPressed: block.customRows.length <= 1
                    ? null
                    : () => _removeCustomRow(block, index),
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                color: AdminTheme.error,
                tooltip: '행 삭제',
              ),
            ],
          ),
          Row(
            children: [
              Text(
                '위치',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
                ),
              ),
              Expanded(
                child: Slider(
                  value: row.offset.toDouble().clamp(-12, 12),
                  min: -12,
                  max: 12,
                  divisions: 24,
                  activeColor: AdminTheme.gold,
                  onChanged: (value) {
                    setState(() => row.offset = value.round());
                  },
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${row.offset}',
                  textAlign: TextAlign.right,
                  style: AdminTheme.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _toggleCustomRowMode(_LayoutBlockDraft block, bool enabled) {
    setState(() {
      block.useCustomRows = enabled;
      if (enabled && block.customRows.isEmpty) {
        for (var i = 0; i < block.rows; i++) {
          block.customRows.add(
            _LayoutCustomRowDraft(
              id: _nextLayoutDraftId(),
              name: '${i + 1}',
              seatCount: block.seatsPerRow,
            ),
          );
        }
      }
    });
  }

  void _addCustomRow(_LayoutBlockDraft block) {
    setState(() {
      final nextIdx = block.customRows.length + 1;
      final baseSeats = block.customRows.isNotEmpty
          ? block.customRows.last.seatCount
          : math.max(1, block.seatsPerRow);
      block.customRows.add(
        _LayoutCustomRowDraft(
          id: _nextLayoutDraftId(),
          name: '$nextIdx',
          seatCount: baseSeats,
        ),
      );
    });
  }

  void _removeCustomRow(_LayoutBlockDraft block, int index) {
    setState(() {
      block.customRows.removeAt(index);
    });
  }

  void _moveCustomRow(_LayoutBlockDraft block, int index, int direction) {
    final target = index + direction;
    if (target < 0 || target >= block.customRows.length) return;
    setState(() {
      final row = block.customRows.removeAt(index);
      block.customRows.insert(target, row);
    });
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: AdminTheme.sans(
        fontSize: 11,
        color: AdminTheme.textTertiary,
      ),
      isDense: true,
      filled: true,
      fillColor: AdminTheme.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: AdminTheme.border, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: AdminTheme.border, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: AdminTheme.gold, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  void _addFloor() {
    setState(() {
      _drafts.add(
        _LayoutFloorDraft(
          id: _nextLayoutDraftId(),
          name: '${_drafts.length + 1}층',
          blocks: [
            _LayoutBlockDraft(
              id: _nextLayoutDraftId(),
              name: 'A',
              rows: 10,
              seatsPerRow: 10,
            ),
          ],
        ),
      );
    });
  }

  void _removeFloor(_LayoutFloorDraft floor) {
    setState(() {
      _drafts.removeWhere((item) => item.id == floor.id);
    });
  }

  void _addBlock(_LayoutFloorDraft floor) {
    setState(() {
      final index = floor.blocks.length;
      floor.blocks.add(
        _LayoutBlockDraft(
          id: _nextLayoutDraftId(),
          name: String.fromCharCode(65 + index),
          rows: 10,
          seatsPerRow: 10,
          layoutRow: index ~/ 3,
          layoutOffset: ((index % 3) - 1) * 6,
        ),
      );
    });
  }

  void _removeBlock(_LayoutFloorDraft floor, _LayoutBlockDraft block) {
    setState(() {
      floor.blocks.removeWhere((item) => item.id == block.id);
    });
  }

  void _applyLayout() {
    final validationError = _validateLayoutDrafts(_drafts);
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationError),
          backgroundColor: AdminTheme.error,
        ),
      );
      return;
    }

    final floors = _toVenueFloors(_drafts);
    Navigator.pop(
      context,
      _VenueLayoutEditorResult(
        floors: floors,
        stagePosition: _stagePosition,
      ),
    );
  }
}

class _GeneratedSeatMapDiagram extends StatelessWidget {
  final List<VenueFloor> floors;
  final String stagePosition;
  final bool compact;
  final bool showSummaryLabel;

  const _GeneratedSeatMapDiagram({
    required this.floors,
    required this.stagePosition,
    required this.compact,
    this.showSummaryLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedStagePosition = _normalizeStagePosition(stagePosition);
    final stageOnTop = normalizedStagePosition == _stageTop;
    final padding = compact ? 10.0 : 14.0;

    return Container(
      color: AdminTheme.surface,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSummaryLabel) ...[
              Text(
                '무대 위치: ${_stagePositionLabel(normalizedStagePosition)}',
                style: AdminTheme.sans(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (stageOnTop) ...[
              _buildStageLabel(compact),
              const SizedBox(height: 10),
            ],
            ...floors.asMap().entries.map(
                  (entry) => _buildFloorLayer(
                    floor: entry.value,
                    floorIndex: entry.key,
                    stageOnTop: stageOnTop,
                  ),
                ),
            if (!stageOnTop) ...[
              const SizedBox(height: 10),
              _buildStageLabel(compact),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStageLabel(bool isCompact) {
    return Center(
      child: Container(
        width: isCompact ? 160 : 230,
        padding: EdgeInsets.symmetric(vertical: isCompact ? 7 : 10),
        decoration: BoxDecoration(
          color: AdminTheme.sage,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'STAGE',
          textAlign: TextAlign.center,
          style: AdminTheme.sans(
            fontSize: isCompact ? 14 : 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AdminTheme.onAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildFloorLayer({
    required VenueFloor floor,
    required int floorIndex,
    required bool stageOnTop,
  }) {
    final fmt = NumberFormat('#,###');
    final floorLabel = _displayFloorLabel(floor.name, floorIndex);
    final blocksByRow = <int, List<VenueBlock>>{};
    for (final block in floor.blocks) {
      final rowKey = block.layoutRow < 0 ? 0 : block.layoutRow;
      blocksByRow.putIfAbsent(rowKey, () => <VenueBlock>[]).add(block);
    }
    for (final rowBlocks in blocksByRow.values) {
      rowBlocks.sort((a, b) {
        final offsetCompare = a.layoutOffset.compareTo(b.layoutOffset);
        if (offsetCompare != 0) return offsetCompare;
        return a.name.compareTo(b.name);
      });
    }
    var rowKeys = blocksByRow.keys.toList()..sort();
    if (!stageOnTop) {
      rowKeys = rowKeys.reversed.toList();
    }

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 10 : 14),
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        compact ? 10 : 12,
        compact ? 10 : 14,
        compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: AdminTheme.cardElevated,
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            floorLabel,
            textAlign: TextAlign.center,
            style: AdminTheme.serif(
              fontSize: compact ? 19 : 24,
              fontWeight: FontWeight.w800,
              color: AdminTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (rowKeys.isNotEmpty)
            ...rowKeys.map((rowKey) {
              final rowBlocks = blocksByRow[rowKey] ?? const <VenueBlock>[];
              return Padding(
                padding: EdgeInsets.only(bottom: compact ? 6 : 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: compact ? 8 : 12,
                  runSpacing: compact ? 8 : 10,
                  children: rowBlocks.map((block) {
                    final xOffset =
                        block.layoutOffset.toDouble() * (compact ? 2.0 : 2.6);
                    return Transform.translate(
                      offset: Offset(xOffset, 0),
                      child: _GeneratedSeatBlock(
                        block: block,
                        compact: compact,
                      ),
                    );
                  }).toList(),
                ),
              );
            }),
          const SizedBox(height: 8),
          Text(
            '${floor.name} · ${fmt.format(floor.totalSeats)}석',
            textAlign: TextAlign.center,
            style: AdminTheme.sans(
              fontSize: compact ? 10 : 11,
              color: AdminTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneratedSeatBlock extends StatelessWidget {
  final VenueBlock block;
  final bool compact;

  const _GeneratedSeatBlock({
    required this.block,
    required this.compact,
  });

  List<_GeneratedSeatRow> _resolveRows(String layoutDirection) {
    if (block.customRows.isNotEmpty) {
      final rows = block.customRows
          .where((row) => row.seatCount > 0)
          .map(
            (row) => _GeneratedSeatRow(
              seatCount: math.max(1, row.seatCount),
              offset: row.offset,
            ),
          )
          .toList();
      if (rows.isNotEmpty) return rows;
    }

    final rowCount = math.max(1, block.rows);
    final seatsPerRow = math.max(1, block.seatsPerRow);
    final visualRows =
        layoutDirection == _layoutVertical ? seatsPerRow : rowCount;
    final visualSeatsPerRow =
        layoutDirection == _layoutVertical ? rowCount : seatsPerRow;
    return List.generate(
      visualRows,
      (_) => _GeneratedSeatRow(seatCount: visualSeatsPerRow),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradeColor = _gradeColorForLayout(block.grade);
    final layoutDirection = _normalizeLayoutDirection(block.layoutDirection);
    final rows = _resolveRows(layoutDirection);
    final isCustom = block.customRows.isNotEmpty;
    final dotSize = compact ? 5.0 : 6.0;
    final dotMargin = compact ? 1.0 : 1.2;
    final slotWidth = dotSize + (dotMargin * 2);
    final maxSeatCount = rows.fold<int>(
      1,
      (maxValue, row) => row.seatCount > maxValue ? row.seatCount : maxValue,
    );
    final minOffset = rows.fold<int>(
      0,
      (minValue, row) => row.offset < minValue ? row.offset : minValue,
    );
    final maxOffset = rows.fold<int>(
      0,
      (maxValue, row) => row.offset > maxValue ? row.offset : maxValue,
    );
    final totalSlots = maxSeatCount + (maxOffset - minOffset);
    final baseWidth = compact ? 86.0 : 112.0;
    final rowVisualWidth = math.max(slotWidth, totalSlots * slotWidth);
    final width =
        math.max(baseWidth, rowVisualWidth + 10).clamp(70.0, 260.0).toDouble();
    final seatFill = gradeColor.withValues(alpha: compact ? 0.6 : 0.72);
    final seatBorder = gradeColor.withValues(alpha: 0.95);
    final summaryText = isCustom
        ? '${rows.length}행 · 최대 $maxSeatCount석/행 · 자유 편집'
        : '${block.rows}열 x ${block.seatsPerRow} · ${_layoutDirectionLabel(layoutDirection)}';

    return SizedBox(
      width: width,
      child: Column(
        children: [
          Text(
            '${block.name}열',
            style: AdminTheme.sans(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          ...rows.map((row) {
            final leadingSlots = row.offset - minOffset;
            return Padding(
              padding: EdgeInsets.only(bottom: compact ? 2 : 3),
              child: SizedBox(
                width: rowVisualWidth,
                child: Row(
                  children: [
                    if (leadingSlots > 0)
                      SizedBox(width: leadingSlots * slotWidth),
                    ...List.generate(row.seatCount, (_) {
                      return Container(
                        width: dotSize,
                        height: dotSize,
                        margin: EdgeInsets.all(dotMargin),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: seatFill,
                          border: Border.all(
                            color: seatBorder,
                            width: 0.45,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 2),
          Text(
            summaryText,
            style: AdminTheme.sans(
              fontSize: compact ? 9 : 10,
              color: AdminTheme.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneratedSeatRow {
  final int seatCount;
  final int offset;

  const _GeneratedSeatRow({
    required this.seatCount,
    this.offset = 0,
  });
}

// =============================================================================
// 공연장 상세 바텀시트
// =============================================================================

class VenueDetailScreen extends ConsumerStatefulWidget {
  final String venueId;
  const VenueDetailScreen({super.key, required this.venueId});

  @override
  ConsumerState<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends ConsumerState<VenueDetailScreen> {
  bool _isUploadingSeatMap = false;
  bool _isSavingLayout = false;
  String? _seatMapUrl;
  List<VenueFloor>? _floors;
  String? _stagePosition;

  void _initFromVenue(Venue venue) {
    _seatMapUrl ??= venue.seatMapImageUrl;
    _floors ??= venue.floors;
    _stagePosition ??= _normalizeStagePosition(venue.stagePosition);
  }

  @override
  Widget build(BuildContext context) {
    final venueAsync = ref.watch(venueStreamProvider(widget.venueId));

    return Scaffold(
      backgroundColor: AdminTheme.background,
      appBar: AppBar(
        backgroundColor: AdminTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AdminTheme.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('공연장 상세',
            style: AdminTheme.serif(fontSize: 16)),
        centerTitle: false,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: venueAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AdminTheme.gold)),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (venue) {
          if (venue == null) {
            return const Center(child: Text('공연장을 찾을 수 없습니다'));
          }
          _initFromVenue(venue);
          return _buildBody(venue);
        },
      ),
    );
  }

  Widget _buildBody(Venue venue) {
    final fmt = NumberFormat('#,###');
    final totalSeats = _calcTotalSeats(_floors!);

    return Column(
      children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AdminTheme.goldGradient,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.location_city_rounded,
                      size: 22, color: AdminTheme.onAccent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(venue.name,
                          style: AdminTheme.serif(fontSize: 18)),
                      if (venue.address != null)
                        Text(venue.address!,
                            style: AdminTheme.sans(
                              fontSize: 12,
                              color: AdminTheme.textTertiary,
                            )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AdminTheme.border, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _stat('총 좌석', '${fmt.format(totalSeats)}석'),
                      _stat('층수', '${_floors!.length}층'),
                      _stat('무대', _stagePositionLabel(_stagePosition ?? 'top')),
                      _stat('좌석 시야', venue.hasSeatView ? '등록됨' : '미등록'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('좌석 배치 자산',
                      style: AdminTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.textPrimary,
                      )),
                  const SizedBox(height: 8),
                  _buildSeatMapAssetCard(venue),
                  const SizedBox(height: 20),
                  Text('층/구역 구성',
                      style: AdminTheme.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.textPrimary,
                      )),
                  const SizedBox(height: 8),
                  if (_floors!.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AdminTheme.surface,
                        border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        '등록된 좌석 구조가 없습니다. 좌석 구조 편집에서 추가해주세요.',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          color: AdminTheme.textTertiary,
                        ),
                      ),
                    )
                  else
                    ..._floors!.map((floor) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(floor.name,
                                style: AdminTheme.sans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AdminTheme.textPrimary,
                                )),
                            const SizedBox(height: 8),
                            ...floor.blocks.map((block) => Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AdminTheme.card,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      Text('${block.name}열',
                                          style: AdminTheme.sans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AdminTheme.textPrimary,
                                          )),
                                      const SizedBox(width: 8),
                                      if (block.grade != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color:
                                                AdminTheme.gold.withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(block.grade!,
                                              style: AdminTheme.sans(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: AdminTheme.gold,
                                              )),
                                        ),
                                      const Spacer(),
                                      Builder(
                                        builder: (_) {
                                          final isCustom =
                                              block.customRows.isNotEmpty;
                                          final rowCount = isCustom
                                              ? block.customRows.length
                                              : block.rows;
                                          final modeText = isCustom
                                              ? '자유 편집'
                                              : _layoutDirectionLabel(
                                                  block.layoutDirection,
                                                );
                                          return Text(
                                              '$rowCount행 · ${fmt.format(block.totalSeats)}석 · $modeText',
                                              style: AdminTheme.sans(
                                                fontSize: 12,
                                                color: AdminTheme.textTertiary,
                                              ));
                                        },
                                      ),
                                    ],
                                  ),
                                )),
                            const SizedBox(height: 12),
                          ],
                        )),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
            decoration: const BoxDecoration(
              color: AdminTheme.surface,
              border:
                  Border(top: BorderSide(color: AdminTheme.border, width: 0.5)),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.go(
                        '/venues/${venue.id}/views?name=${Uri.encodeComponent(venue.name)}',
                      );
                    },
                    icon: const Icon(Icons.camera_alt_rounded, size: 18),
                    label: Text('좌석 시야 업로드',
                        style: AdminTheme.sans(
                            fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminTheme.textPrimary,
                      side: const BorderSide(color: AdminTheme.border, width: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      context.go('/venues/${venue.id}/seat-layout');
                    },
                    icon: const Icon(Icons.grid_on_rounded, size: 18),
                    label: Text(
                      venue.seatLayout != null
                          ? '도트맵 좌석 편집 (${venue.seatLayout!.totalSeats}석)'
                          : '도트맵 좌석 배치 만들기',
                      style: AdminTheme.sans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _deleteVenue(context, ref, venue),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.error.withValues(alpha: 0.15),
                      foregroundColor: AdminTheme.error,
                      elevation: 0,
                    ),
                    child: Text('삭제',
                        style:
                            AdminTheme.sans(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _editSeatStructure(Venue venue) async {
    final updated = await showModalBottomSheet<_VenueLayoutEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final width = MediaQuery.of(sheetContext).size.width;
        final widthFactor = width >= 1100 ? 0.98 : 1.0;
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: _VenueLayoutEditorSheet(
              venueName: venue.name,
              initialFloors: _floors!,
              initialStagePosition: _stagePosition!,
            ),
          ),
        );
      },
    );

    if (updated == null) return;
    final updatedFloors = updated.floors;
    final updatedStagePosition = _normalizeStagePosition(updated.stagePosition);

    setState(() => _isSavingLayout = true);
    try {
      final totalSeats = _calcTotalSeats(updatedFloors);
      await ref.read(venueRepositoryProvider).updateVenue(
        venue.id,
        {
          'floors': updatedFloors.map((floor) => floor.toMap()).toList(),
          'totalSeats': totalSeats,
          'stagePosition': updatedStagePosition,
        },
      );
      if (!mounted) return;
      setState(() {
        _floors = updatedFloors;
        _stagePosition = updatedStagePosition;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('좌석 구조와 무대 위치가 저장되었습니다'),
          backgroundColor: AdminTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('좌석 구조 저장 실패: $e'),
          backgroundColor: AdminTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingLayout = false);
    }
  }

  Widget _buildSeatMapAssetCard(Venue venue) {
    final hasSeatMap = _seatMapUrl != null && _seatMapUrl!.isNotEmpty;
    final hasParsedLayout = venue.seatLayout != null && venue.seatLayout!.seats.isNotEmpty;
    final hasAnyMap = hasSeatMap || hasParsedLayout;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasSeatMap
                      ? '좌석배치도 이미지 등록됨'
                      : hasParsedLayout
                          ? '엑셀 파싱 배치도 (${venue.seatLayout!.totalSeats}석)'
                          : '좌석배치도 미등록',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: hasAnyMap ? AdminTheme.info : AdminTheme.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed:
                    _isSavingLayout ? null : () => _editSeatStructure(venue),
                style: TextButton.styleFrom(
                  foregroundColor: AdminTheme.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: _isSavingLayout
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AdminTheme.gold,
                        ),
                      )
                    : Text(
                        hasAnyMap ? '수정' : '구조 만들기',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              TextButton(
                onPressed: _isUploadingSeatMap
                    ? null
                    : () => _uploadSeatMapImage(venue),
                style: TextButton.styleFrom(
                  foregroundColor: AdminTheme.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: _isUploadingSeatMap
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AdminTheme.gold,
                        ),
                      )
                    : Text(
                        hasSeatMap ? '배치도 교체' : '배치도 업로드',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: double.infinity,
              height: hasParsedLayout ? 300 : 140,
              child: hasSeatMap
                  ? Image.network(
                      _seatMapUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _assetPlaceholder('배치도 이미지 로드 실패'),
                    )
                  : hasParsedLayout
                      ? _buildParsedSeatMapPreview(venue.seatLayout!)
                      : _assetPlaceholder('좌석배치도 엑셀을 업로드하세요'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParsedSeatMapPreview(VenueSeatLayout layout) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: CustomPaint(
        painter: _MiniSeatMapPainter(layout),
        size: Size.infinite,
      ),
    );
  }

  Widget _assetPlaceholder(String text) {
    return Container(
      color: AdminTheme.surface,
      child: Center(
        child: Text(
          text,
          style: AdminTheme.sans(
            fontSize: 12,
            color: AdminTheme.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _uploadSeatMapImage(Venue venue) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (bytes == null || file == null) return;

      if (bytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이미지 크기는 10MB 이하만 업로드 가능합니다'),
            backgroundColor: AdminTheme.error,
          ),
        );
        return;
      }

      setState(() => _isUploadingSeatMap = true);
      final oldUrl = _seatMapUrl;

      final imageUrl =
          await ref.read(storageServiceProvider).uploadSeatMapImage(
                bytes: bytes,
                venueId: venue.id,
                fileName: file.name,
              );
      await ref.read(venueRepositoryProvider).updateVenue(
        venue.id,
        {'seatMapImageUrl': imageUrl},
      );

      if (oldUrl != null && oldUrl.isNotEmpty) {
        await ref.read(storageServiceProvider).deleteFile(oldUrl);
      }

      if (!mounted) return;
      setState(() => _seatMapUrl = imageUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('좌석배치도 업로드 완료'),
          backgroundColor: AdminTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('업로드 실패: $e'),
          backgroundColor: AdminTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingSeatMap = false);
    }
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: AdminTheme.card,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Text(value,
                style: AdminTheme.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.gold,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textTertiary,
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteVenue(
      BuildContext context, WidgetRef ref, Venue venue) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Text('공연장 삭제',
            style: AdminTheme.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AdminTheme.textPrimary)),
        content: Text('${venue.name}을(를) 삭제하시겠습니까?',
            style: AdminTheme.sans(
                fontSize: 14, color: AdminTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: AdminTheme.textTertiary,
            ),
            child: Text('취소',
                style: AdminTheme.sans(color: AdminTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AdminTheme.error,
            ),
            child:
                Text('삭제', style: AdminTheme.sans(color: AdminTheme.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(venueRepositoryProvider).deleteVenue(venue.id);
      if (context.mounted) {
        context.go('/venues');
      }
    }
  }
}

// =============================================================================
// 공연장 등록 폼
// =============================================================================

class _VenueCreateForm extends ConsumerStatefulWidget {
  final List<Venue> existingVenues;
  final VoidCallback onBack;
  final VoidCallback onCreated;

  const _VenueCreateForm({
    required this.existingVenues,
    required this.onBack,
    required this.onCreated,
  });

  @override
  ConsumerState<_VenueCreateForm> createState() => _VenueCreateFormState();
}

class _VenueCreateFormState extends ConsumerState<_VenueCreateForm> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _isSubmitting = false;
  String? _selectedPreset;
  String _stagePosition = _stageTop;
  Uint8List? _seatMapBytes;
  String? _seatMapFileName;
  List<VenueFloor> _layoutFloors = [];

  // 엑셀 파싱 결과
  bool _isParsingExcel = false;
  String? _excelFileName;
  ParsedSeatData? _parsedSeatData;
  VenueSeatLayout? _parsedSeatLayout;

  // 프리셋으로 자동 채워진 경우
  Venue? _presetVenue;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width >= 900 ? 40 : 16,
        vertical: 20,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 프리셋 선택
              Text('프리셋 선택',
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.textSecondary,
                  )),
              const SizedBox(height: 10),
              _buildPresetOption(
                '스카이아트홀',
                '서울 등촌 · 409석 · 지하1~2층',
                'sky_art_hall',
              ),
              const SizedBox(height: 8),
              _buildPresetOption(
                '부산시민회관 대극장',
                '부산 동구 · 1,606석 · 1~2층',
                'busan_civic_hall',
              ),

              const SizedBox(height: 24),

              // 직접 입력
              Text('또는 직접 입력',
                  style: AdminTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.textSecondary,
                  )),
              const SizedBox(height: 10),

              _buildField('공연장명', _nameCtrl, '예: 스카이아트홀'),
              const SizedBox(height: 12),
              _buildField('주소 (선택)', _addressCtrl, '예: 서울특별시 강서구 등촌동'),
              const SizedBox(height: 12),
              _buildSeatMapUploadField(),

              // 프리셋 미리보기
              if (_presetVenue != null) ...[
                const SizedBox(height: 20),
                _buildPresetPreview(_presetVenue!),
              ],

              const SizedBox(height: 28),

              // 등록 버튼
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _createVenue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminTheme.gold,
                    foregroundColor: AdminTheme.onAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                    disabledBackgroundColor: AdminTheme.border,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AdminTheme.onAccent))
                      : Text('공연장 등록',
                          style: AdminTheme.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetOption(String name, String detail, String presetId) {
    final isSelected = _selectedPreset == presetId;
    return GestureDetector(
      onTap: () => _selectPreset(presetId),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AdminTheme.goldSubtle : AdminTheme.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AdminTheme.gold : AdminTheme.border,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? AdminTheme.gold.withValues(alpha: 0.2)
                    : AdminTheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.location_city_rounded,
                  size: 20,
                  color: isSelected ? AdminTheme.gold : AdminTheme.textTertiary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: AdminTheme.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.textPrimary,
                      )),
                  Text(detail,
                      style: AdminTheme.sans(
                        fontSize: 12,
                        color: AdminTheme.textTertiary,
                      )),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded,
                  color: AdminTheme.gold, size: 22),
          ],
        ),
      ),
    );
  }

  void _selectPreset(String presetId) {
    Venue preset;
    if (presetId == 'sky_art_hall') {
      preset = SkyArtHallPreset.venue;
    } else if (presetId == 'busan_civic_hall') {
      preset = BusanCivicHallPreset.venue;
    } else {
      return;
    }

    setState(() {
      _selectedPreset = presetId;
      _presetVenue = preset;
      _nameCtrl.text = preset.name;
      _addressCtrl.text = preset.address ?? '';
      _layoutFloors = preset.floors;
      _stagePosition = _normalizeStagePosition(preset.stagePosition);
    });
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AdminTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AdminTheme.textSecondary,
            )),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          style:
              AdminTheme.sans(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AdminTheme.sans(
                fontSize: 13, color: AdminTheme.textTertiary),
            filled: true,
            fillColor: AdminTheme.card,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AdminTheme.border, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AdminTheme.border, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AdminTheme.gold, width: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetPreview(Venue venue) {
    final fmt = NumberFormat('#,###');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminTheme.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AdminTheme.success, size: 16),
              const SizedBox(width: 8),
              Text('프리셋 미리보기',
                  style: AdminTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AdminTheme.success,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          Text('총 ${fmt.format(venue.totalSeats)}석 · ${venue.floors.length}층',
              style: AdminTheme.sans(
                fontSize: 13,
                color: AdminTheme.textSecondary,
              )),
          const SizedBox(height: 6),
          ...venue.floors.map((floor) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${floor.name}: ${floor.blocks.map((b) => "${b.name}(${b.grade ?? "-"})").join(", ")}',
                  style: AdminTheme.sans(
                    fontSize: 12,
                    color: AdminTheme.textTertiary,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSeatMapUploadField() {
    final hasExcel = _excelFileName != null;
    final hasParsed = _parsedSeatLayout != null;
    final hasLayout = _layoutFloors.isNotEmpty;
    final fmt = NumberFormat('#,###');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('좌석배치도 엑셀 업로드',
            style: AdminTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AdminTheme.textSecondary,
            )),
        const SizedBox(height: 6),

        // 엑셀 업로드 영역
        InkWell(
          onTap: _isParsingExcel ? null : _pickExcelForVenue,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: AdminTheme.surface,
              border: Border.all(
                color: hasParsed
                    ? AdminTheme.success.withValues(alpha: 0.5)
                    : AdminTheme.sage.withValues(alpha: 0.25),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Column(
              children: [
                if (_isParsingExcel) ...[
                  const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: AdminTheme.gold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('좌석 배치도 분석 중...',
                    style: AdminTheme.sans(
                      fontSize: 12, color: AdminTheme.textTertiary,
                    ),
                  ),
                ] else if (hasParsed) ...[
                  const Icon(Icons.check_circle_outline,
                    size: 28, color: AdminTheme.success),
                  const SizedBox(height: 8),
                  Text(_excelFileName ?? '',
                    style: AdminTheme.sans(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: AdminTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${fmt.format(_parsedSeatLayout!.totalSeats)}석 감지 · 탭하여 다시 업로드',
                    style: AdminTheme.sans(
                      fontSize: 11, color: AdminTheme.textTertiary,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.upload_file_outlined,
                    size: 28,
                    color: AdminTheme.sage.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text('좌석배치도 엑셀 파일을 업로드하세요',
                    style: AdminTheme.sans(
                      fontSize: 12, color: AdminTheme.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('.xlsx / .xls 지원 · 색상 기반 자동 등급 분류',
                    style: AdminTheme.sans(
                      fontSize: 10, color: AdminTheme.sage.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // 파싱 결과 Canvas 미리보기
        if (hasParsed) ...[
          const SizedBox(height: 12),
          _buildParsedSeatMapPreview(),
        ],

        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AdminTheme.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AdminTheme.info.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasParsed || hasLayout
                    ? '엑셀 파싱 완료! 아래 편집 도구로 미세 조정할 수 있습니다.'
                    : '엑셀 없이도 아래 버튼에서 직접 좌석 구조를 만들 수 있습니다.',
                style: AdminTheme.sans(
                  fontSize: 11,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: hasParsed
                      ? _openSeatStructureEditor
                      : _openSeatLayoutEditor,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminTheme.textPrimary,
                    side: const BorderSide(color: AdminTheme.border, width: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(hasParsed ? Icons.edit_note_rounded : Icons.construction_rounded, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        hasParsed || hasLayout ? '좌석 구조 편집' : '좌석배치도 직접 만들기',
                        style: AdminTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildParsedSeatMapPreview() {
    if (_parsedSeatLayout == null) return const SizedBox.shrink();
    final layout = _parsedSeatLayout!;
    final gradeCount = layout.seatCountByGrade;
    final fmt = NumberFormat('#,###');

    // 층별 → 열별 좌석 그룹핑
    final floorMap = <String, Map<String, Map<String, int>>>{};
    // floorMap[floor][row] = { grade: count }
    for (final seat in layout.seats) {
      final f = seat.floor.isNotEmpty ? seat.floor : '1층';
      final r = seat.row.isNotEmpty ? seat.row : '?';
      floorMap.putIfAbsent(f, () => {});
      floorMap[f]!.putIfAbsent(r, () => {});
      floorMap[f]![r]![seat.grade] = (floorMap[f]![r]![seat.grade] ?? 0) + 1;
    }

    // 층 정렬 (1층, 2층 순서)
    final sortedFloors = floorMap.keys.toList()
      ..sort((a, b) {
        final na = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final nb = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return na.compareTo(nb);
      });

    const gradeColors = {
      'VIP': Color(0xFFD4AF37),
      'R': Color(0xFFE53935),
      'S': Color(0xFF1E88E5),
      'A': Color(0xFF43A047),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminTheme.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AdminTheme.success.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 ──
          Row(
            children: [
              const Icon(Icons.check_circle, size: 14, color: AdminTheme.success),
              const SizedBox(width: 6),
              Text('파싱 결과',
                style: AdminTheme.sans(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: AdminTheme.success,
                ),
              ),
              const Spacer(),
              Text('${fmt.format(layout.totalSeats)}석',
                style: AdminTheme.sans(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AdminTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── 등급 요약 ──
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: ['VIP', 'R', 'S', 'A']
                .where((g) => gradeCount.containsKey(g))
                .map((g) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: gradeColors[g],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$g: ${fmt.format(gradeCount[g])}석',
                          style: AdminTheme.sans(
                            fontSize: 11, color: AdminTheme.textSecondary,
                          ),
                        ),
                      ],
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),

          // ── Canvas 미리보기 ──
          Container(
            width: double.infinity,
            height: 280,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A24),
              borderRadius: BorderRadius.circular(4),
            ),
            child: CustomPaint(
              painter: _MiniSeatMapPainter(layout),
            ),
          ),
          const SizedBox(height: 12),

          // ── 층별 · 열별 상세 ──
          ...sortedFloors.map((floorName) {
            final rowMap = floorMap[floorName]!;
            final floorTotal = rowMap.values.fold<int>(
                0, (sum, grades) => sum + grades.values.fold(0, (s, c) => s + c));

            // 열 정렬: 숫자 우선, 알파벳 다음
            final sortedRows = rowMap.keys.toList()..sort((a, b) {
              final na = int.tryParse(a);
              final nb = int.tryParse(b);
              if (na != null && nb != null) return na.compareTo(nb);
              if (na != null) return -1;
              if (nb != null) return 1;
              return a.compareTo(b);
            });

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdminTheme.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AdminTheme.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        floorName,
                        style: AdminTheme.sans(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: AdminTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${fmt.format(floorTotal)}석 · ${sortedRows.length}열',
                        style: AdminTheme.sans(
                          fontSize: 11, color: AdminTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 열별 테이블
                  ...sortedRows.map((rowName) {
                    final grades = rowMap[rowName]!;
                    final rowTotal = grades.values.fold<int>(0, (s, c) => s + c);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${rowName}열',
                              style: AdminTheme.sans(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: AdminTheme.textSecondary,
                              ),
                            ),
                          ),
                          // 등급별 색상 바
                          Expanded(
                            child: Row(
                              children: ['VIP', 'R', 'S', 'A']
                                  .where((g) => grades.containsKey(g))
                                  .map((g) => Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 6, height: 6,
                                              decoration: BoxDecoration(
                                                color: gradeColors[g],
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              '${grades[g]}',
                                              style: AdminTheme.sans(
                                                fontSize: 10,
                                                color: gradeColors[g],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                          Text(
                            '${fmt.format(rowTotal)}석',
                            style: AdminTheme.sans(
                              fontSize: 10, color: AdminTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSeatLayoutField() {
    final fmt = NumberFormat('#,###');
    final totalSeats = _calcTotalSeats(_layoutFloors);
    final blockCount =
        _layoutFloors.fold<int>(0, (sum, floor) => sum + floor.blocks.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('좌석 구조',
            style: AdminTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AdminTheme.textSecondary,
            )),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AdminTheme.surface,
            border: Border.all(color: AdminTheme.sage.withValues(alpha: 0.15), width: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _layoutFloors.isEmpty
                    ? '아직 좌석 구조가 없습니다'
                    : '총 ${fmt.format(totalSeats)}석 · ${_layoutFloors.length}층 · $blockCount구역 · 무대 ${_stagePositionLabel(_stagePosition)}',
                style: AdminTheme.sans(
                  fontSize: 12,
                  color: _layoutFloors.isEmpty
                      ? AdminTheme.textTertiary
                      : AdminTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '무대 위치',
                style: AdminTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('상단'),
                    selected: _stagePosition == _stageTop,
                    onSelected: (_) =>
                        setState(() => _stagePosition = _stageTop),
                  ),
                  ChoiceChip(
                    label: const Text('하단'),
                    selected: _stagePosition == _stageBottom,
                    onSelected: (_) =>
                        setState(() => _stagePosition = _stageBottom),
                  ),
                ],
              ),
              if (_layoutFloors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _layoutFloors
                      .map(
                        (floor) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AdminTheme.surface,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            '${floor.name} (${fmt.format(floor.totalSeats)}석)',
                            style: AdminTheme.sans(
                              fontSize: 11,
                              color: AdminTheme.textSecondary,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                _buildLayoutPreviewMap(),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _openSeatLayoutEditor,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminTheme.textPrimary,
                    side: const BorderSide(color: AdminTheme.border, width: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.grid_view_rounded, size: 17),
                      const SizedBox(width: 8),
                      Text(
                        _layoutFloors.isEmpty ? '좌석배치도 직접 만들기' : '좌석 구조 편집',
                        style: AdminTheme.sans(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLayoutPreviewMap() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '자동 생성 배치도 미리보기',
            style: AdminTheme.sans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _GeneratedSeatMapDiagram(
            floors: _layoutFloors,
            stagePosition: _stagePosition,
            compact: false,
            showSummaryLabel: true,
          ),
        ],
      ),
    );
  }

  Future<void> _openSeatLayoutEditor() async {
    final initialFloors =
        _layoutFloors.isNotEmpty ? _layoutFloors : (_presetVenue?.floors ?? []);
    final result = await showModalBottomSheet<_VenueLayoutEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final width = MediaQuery.of(sheetContext).size.width;
        final widthFactor = width >= 1100 ? 0.98 : 1.0;
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: _VenueLayoutEditorSheet(
              venueName: _nameCtrl.text.trim().isEmpty
                  ? '새 공연장'
                  : _nameCtrl.text.trim(),
              initialFloors: initialFloors,
              initialStagePosition: _stagePosition,
            ),
          ),
        );
      },
    );

    if (result == null) return;
    setState(() {
      _layoutFloors = result.floors;
      _stagePosition = _normalizeStagePosition(result.stagePosition);
    });
  }

  Future<void> _openSeatStructureEditor() async {
    if (_parsedSeatLayout == null) return;
    final result = await showModalBottomSheet<VenueSeatLayout>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final width = MediaQuery.of(sheetContext).size.width;
        final widthFactor = width >= 1100 ? 0.98 : 1.0;
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: _SeatStructureEditorSheet(
              layout: _parsedSeatLayout!,
            ),
          ),
        );
      },
    );
    if (result == null) return;

    // 편집된 layout 반영 + floors 재계산
    final floorMap = <String, Map<String, List<LayoutSeat>>>{};
    for (final seat in result.seats) {
      final floor = seat.floor.isNotEmpty ? seat.floor : '1층';
      final zone = seat.zone.isNotEmpty ? seat.zone : 'A';
      floorMap.putIfAbsent(floor, () => {});
      floorMap[floor]!.putIfAbsent(zone, () => []);
      floorMap[floor]![zone]!.add(seat);
    }
    final venueFloors = <VenueFloor>[];
    for (final entry in floorMap.entries) {
      final blocks = <VenueBlock>[];
      for (final zoneEntry in entry.value.entries) {
        final seats = zoneEntry.value;
        final rows = seats.map((s) => s.row).toSet();
        final grade = seats.isNotEmpty ? seats.first.grade : null;
        blocks.add(VenueBlock(
          name: zoneEntry.key,
          rows: rows.length,
          seatsPerRow: rows.isNotEmpty
              ? (seats.length / rows.length).ceil()
              : seats.length,
          totalSeats: seats.length,
          grade: grade,
        ));
      }
      venueFloors.add(VenueFloor(
        name: entry.key,
        blocks: blocks,
        totalSeats: blocks.fold(0, (s, b) => s + b.totalSeats),
      ));
    }

    setState(() {
      _parsedSeatLayout = result;
      _layoutFloors = venueFloors;
    });
  }

  Future<void> _pickExcelForVenue() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;

      setState(() {
        _isParsingExcel = true;
        _excelFileName = file.name;
      });

      // ExcelToSeatMapConverter로 직접 변환 (색상 기반 + 리스트 등 모든 포맷 지원)
      final convResult = ExcelToSeatMapConverter.convert(bytes);
      final layout = convResult.layout;

      if (layout.seats.isEmpty && !mounted) {
        if (mounted) {
          setState(() => _isParsingExcel = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('좌석 데이터를 파싱할 수 없습니다'),
              backgroundColor: AdminTheme.error,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      if (layout.seats.isEmpty) {
        setState(() => _isParsingExcel = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(convResult.errors.isNotEmpty
                ? '파싱 오류: ${convResult.errors.first}'
                : '좌석 데이터를 파싱할 수 없습니다'),
            backgroundColor: AdminTheme.error,
          ),
        );
        return;
      }

      // layout에서 floors 역산 (zone+grade 기반 그룹화)
      final floorMap = <String, Map<String, List<LayoutSeat>>>{};
      for (final seat in layout.seats) {
        final floor = seat.floor.isNotEmpty ? seat.floor : '1층';
        final zone = seat.zone.isNotEmpty ? seat.zone : 'A';
        floorMap.putIfAbsent(floor, () => {});
        floorMap[floor]!.putIfAbsent(zone, () => []);
        floorMap[floor]![zone]!.add(seat);
      }

      final venueFloors = <VenueFloor>[];
      for (final entry in floorMap.entries) {
        final blocks = <VenueBlock>[];
        for (final zoneEntry in entry.value.entries) {
          final seats = zoneEntry.value;
          final rows = seats.map((s) => s.row).toSet();
          final grade = seats.isNotEmpty ? seats.first.grade : null;
          blocks.add(VenueBlock(
            name: zoneEntry.key,
            rows: rows.length,
            seatsPerRow: rows.isNotEmpty
                ? (seats.length / rows.length).ceil()
                : seats.length,
            totalSeats: seats.length,
            grade: grade,
          ));
        }
        venueFloors.add(VenueFloor(
          name: entry.key,
          blocks: blocks,
          totalSeats: blocks.fold(0, (s, b) => s + b.totalSeats),
        ));
      }

      setState(() {
        _isParsingExcel = false;
        _parsedSeatLayout = layout;
        _layoutFloors = venueFloors;
        // 공연장명 자동 채우기 (비어있으면)
        if (_nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text = file.name.replaceAll(RegExp(r'\.(xlsx|xls)$'), '');
        }
      });

      if (convResult.warnings.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('파싱 완료 (경고: ${convResult.warnings.first})'),
            backgroundColor: AdminTheme.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isParsingExcel = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('엑셀 파싱 오류: $e'),
            backgroundColor: AdminTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _createVenue() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('공연장명을 입력해주세요'),
          backgroundColor: AdminTheme.error,
        ),
      );
      return;
    }

    final floors = _layoutFloors.isNotEmpty
        ? _layoutFloors
        : (_presetVenue?.floors ?? <VenueFloor>[]);
    if (_parsedSeatLayout == null && floors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('좌석배치도 엑셀을 업로드하거나 좌석 구조를 직접 만들어주세요'),
          backgroundColor: AdminTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final venue = Venue(
        id: '',
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty
            ? _presetVenue?.address
            : _addressCtrl.text.trim(),
        stagePosition: _stagePosition,
        floors: floors,
        totalSeats: _parsedSeatLayout?.totalSeats ?? _calcTotalSeats(floors),
        seatLayout: _parsedSeatLayout,
        createdAt: DateTime.now(),
      );

      final venueId =
          await ref.read(venueRepositoryProvider).createVenue(venue);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${venue.name} 등록 완료'),
            backgroundColor: AdminTheme.success,
          ),
        );
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류: $e'),
            backgroundColor: AdminTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

// ══════════════════════════════════════════════════
//  좌석 구조 편집 시트 (파싱 결과 미세 조정)
// ══════════════════════════════════════════════════

class _SeatStructureEditorSheet extends StatefulWidget {
  final VenueSeatLayout layout;

  const _SeatStructureEditorSheet({required this.layout});

  @override
  State<_SeatStructureEditorSheet> createState() =>
      _SeatStructureEditorSheetState();
}

class _SeatStructureEditorSheetState extends State<_SeatStructureEditorSheet> {
  late List<LayoutSeat> _seats;
  final Set<int> _selected = {};
  String _tool = 'select'; // select | grade | lasso
  String _paintGrade = 'VIP';
  bool _showInfo = false;
  // zoom / pan
  final TransformationController _transformCtrl = TransformationController();

  static const _gradeColors = {
    'VIP': Color(0xFFD4AF37),
    'R': Color(0xFFE53935),
    'S': Color(0xFF1E88E5),
    'A': Color(0xFF43A047),
    '시야장애': Color(0xFF888888),
    '하우스유보': Color(0xFF4488CC),
    '유보석': Color(0xFF666666),
  };
  static const _gradeOrder = ['VIP', 'R', 'S', 'A'];
  static const _extraGrades = ['시야장애', '하우스유보', '유보석'];

  @override
  void initState() {
    super.initState();
    _seats = widget.layout.seats.map((s) => s.copyWith()).toList();
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  Map<String, int> get _gradeCounts {
    final m = <String, int>{};
    for (final s in _seats) {
      m[s.grade] = (m[s.grade] ?? 0) + 1;
    }
    return m;
  }

  // ── 좌석 탭 핸들러 ──
  void _onSeatTap(int index) {
    setState(() {
      if (_tool == 'grade') {
        _seats[index] = _seats[index].copyWith(grade: _paintGrade);
      } else {
        if (_selected.contains(index)) {
          _selected.remove(index);
        } else {
          _selected.add(index);
        }
        _showInfo = _selected.length == 1;
      }
    });
  }

  // ── 선택 영역 등급 일괄 변경 ──
  void _changeSelectedGrade(String grade) {
    setState(() {
      for (final i in _selected) {
        _seats[i] = _seats[i].copyWith(grade: grade);
      }
    });
  }

  // ── 등급별 전체 선택 ──
  void _selectByGrade(String grade) {
    setState(() {
      _selected.clear();
      for (int i = 0; i < _seats.length; i++) {
        if (_seats[i].grade == grade) _selected.add(i);
      }
      _showInfo = false;
    });
  }

  // ── 구역별 전체 선택 ──
  void _selectByZone(String zone) {
    setState(() {
      _selected.clear();
      for (int i = 0; i < _seats.length; i++) {
        if (_seats[i].zone == zone) _selected.add(i);
      }
      _showInfo = false;
    });
  }

  void _selectAll() => setState(() {
        _selected.clear();
        _selected.addAll(List.generate(_seats.length, (i) => i));
        _showInfo = false;
      });

  void _clearSelection() => setState(() {
        _selected.clear();
        _showInfo = false;
      });

  // ── 선택 좌석 삭제 ──
  void _deleteSelected() {
    if (_selected.isEmpty) return;
    setState(() {
      final sorted = _selected.toList()..sort((a, b) => b.compareTo(a));
      for (final i in sorted) {
        _seats.removeAt(i);
      }
      _selected.clear();
      _showInfo = false;
    });
  }

  // ── 개별 좌석 수정 (zone, row, number) ──
  static const _seatTypeLabels = {
    SeatType.normal: '일반석',
    SeatType.obstructedView: '시야장애석',
    SeatType.houseReserved: '하우스유보석',
    SeatType.wheelchair: '장애인석',
    SeatType.reservedHold: '유보석',
  };

  void _editSingleSeat(int index) {
    final seat = _seats[index];
    final zoneCtrl = TextEditingController(text: seat.zone);
    final rowCtrl = TextEditingController(text: seat.row);
    final numCtrl = TextEditingController(text: seat.number.toString());
    String tempGrade = seat.grade;
    SeatType tempSeatType = seat.seatType;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AdminTheme.surface,
          title: Text(
            '좌석 정보 수정',
            style: AdminTheme.sans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textPrimary,
            ),
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField('구역', zoneCtrl),
                const SizedBox(height: 10),
                _dialogField('열', rowCtrl),
                const SizedBox(height: 10),
                _dialogField('번호', numCtrl, isNumber: true),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('등급',
                          style: AdminTheme.sans(
                            fontSize: 12,
                            color: AdminTheme.textSecondary,
                          )),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [..._gradeOrder, ..._extraGrades].map(
                          (g) => GestureDetector(
                            onTap: () => setDlg(() => tempGrade = g),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: tempGrade == g
                                    ? _gradeColors[g]
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _gradeColors[g] ?? AdminTheme.border,
                                  width: tempGrade == g ? 1.5 : 0.5,
                                ),
                              ),
                              child: Text(
                                g,
                                style: AdminTheme.sans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: tempGrade == g
                                      ? Colors.white
                                      : _gradeColors[g],
                                ),
                              ),
                            ),
                          ),
                        ).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 좌석 유형 선택
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('유형',
                          style: AdminTheme.sans(
                            fontSize: 12,
                            color: AdminTheme.textSecondary,
                          )),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _seatTypeLabels.entries.map(
                          (e) => GestureDetector(
                            onTap: () => setDlg(() => tempSeatType = e.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: tempSeatType == e.key
                                    ? AdminTheme.gold.withValues(alpha: 0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: tempSeatType == e.key
                                      ? AdminTheme.gold
                                      : AdminTheme.border,
                                  width: tempSeatType == e.key ? 1.5 : 0.5,
                                ),
                              ),
                              child: Text(
                                e.value,
                                style: AdminTheme.sans(
                                  fontSize: 10,
                                  fontWeight: tempSeatType == e.key
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: tempSeatType == e.key
                                      ? AdminTheme.gold
                                      : AdminTheme.textTertiary,
                                ),
                              ),
                            ),
                          ),
                        ).toList(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소',
                  style: AdminTheme.sans(color: AdminTheme.textTertiary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.gold,
                foregroundColor: AdminTheme.onAccent,
              ),
              onPressed: () {
                setState(() {
                  _seats[index] = _seats[index].copyWith(
                    zone: zoneCtrl.text.trim(),
                    row: rowCtrl.text.trim(),
                    number: int.tryParse(numCtrl.text.trim()) ?? seat.number,
                    grade: tempGrade,
                    seatType: tempSeatType,
                  );
                });
                Navigator.pop(ctx);
              },
              child: Text('적용',
                  style: AdminTheme.sans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogField(String label, TextEditingController ctrl,
      {bool isNumber = false}) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(label,
              style: AdminTheme.sans(
                fontSize: 12,
                color: AdminTheme.textSecondary,
              )),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctrl,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            style: AdminTheme.sans(
                fontSize: 13, color: AdminTheme.textPrimary),
            cursorColor: AdminTheme.gold,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide:
                    const BorderSide(color: AdminTheme.border, width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AdminTheme.gold, width: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 적용 & 반환 ──
  void _apply() {
    final newLayout = VenueSeatLayout(
      layoutVersion: widget.layout.layoutVersion,
      canvasWidth: widget.layout.canvasWidth,
      canvasHeight: widget.layout.canvasHeight,
      stagePosition: widget.layout.stagePosition,
      stageWidthRatio: widget.layout.stageWidthRatio,
      stageHeight: widget.layout.stageHeight,
      stageShape: widget.layout.stageShape,
      seats: _seats,
      labels: widget.layout.labels,
      dividers: widget.layout.dividers,
      gradePrice: widget.layout.gradePrice,
      backgroundImageUrl: widget.layout.backgroundImageUrl,
      backgroundOpacity: widget.layout.backgroundOpacity,
    );
    Navigator.pop(context, newLayout);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');
    final gc = _gradeCounts;
    final zones = _seats.map((s) => s.zone).toSet().toList()..sort();

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AdminTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // ── 핸들 + 헤더 ──
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AdminTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.edit_note_rounded,
                        color: AdminTheme.gold, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '좌석 구조 편집',
                      style: AdminTheme.sans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '총 ${fmt.format(_seats.length)}석',
                      style: AdminTheme.sans(
                        fontSize: 12,
                        color: AdminTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                      color: AdminTheme.textTertiary,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── 등급 요약 바 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [..._gradeOrder, ..._extraGrades]
                  .where((g) => gc.containsKey(g))
                  .map((g) => Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _gradeColors[g],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$g ${fmt.format(gc[g])}',
                              style: AdminTheme.sans(
                                fontSize: 11,
                                color: AdminTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),

          const Divider(height: 1, color: AdminTheme.border),

          // ── 도구 바 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _toolButton(
                    icon: Icons.touch_app_rounded,
                    label: '선택',
                    active: _tool == 'select',
                    onTap: () => setState(() => _tool = 'select'),
                  ),
                  const SizedBox(width: 4),
                  _toolButton(
                    icon: Icons.brush_rounded,
                    label: '등급 칠하기',
                    active: _tool == 'grade',
                    onTap: () => setState(() => _tool = 'grade'),
                  ),
                  if (_tool == 'grade') ...[
                    const SizedBox(width: 8),
                    ...[..._gradeOrder, ..._extraGrades].map(
                      (g) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: GestureDetector(
                          onTap: () => setState(() => _paintGrade = g),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _paintGrade == g
                                  ? _gradeColors[g]
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _gradeColors[g] ?? AdminTheme.border,
                                width: _paintGrade == g ? 1.5 : 0.5,
                              ),
                            ),
                            child: Text(
                              g,
                              style: AdminTheme.sans(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _paintGrade == g
                                    ? Colors.white
                                    : _gradeColors[g],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Container(
                      width: 1, height: 20, color: AdminTheme.border),
                  const SizedBox(width: 8),
                  // 빠른 선택
                  PopupMenuButton<String>(
                    tooltip: '빠른 선택',
                    color: AdminTheme.surface,
                    onSelected: (val) {
                      if (val == 'all') {
                        _selectAll();
                      } else if (val == 'clear') {
                        _clearSelection();
                      } else if (val.startsWith('grade:')) {
                        _selectByGrade(val.substring(6));
                      } else if (val.startsWith('zone:')) {
                        _selectByZone(val.substring(5));
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'all',
                        child: Text('전체 선택',
                            style: AdminTheme.sans(
                                fontSize: 12,
                                color: AdminTheme.textPrimary)),
                      ),
                      PopupMenuItem(
                        value: 'clear',
                        child: Text('선택 해제',
                            style: AdminTheme.sans(
                                fontSize: 12,
                                color: AdminTheme.textPrimary)),
                      ),
                      const PopupMenuDivider(),
                      ...[..._gradeOrder, ..._extraGrades].map(
                        (g) => PopupMenuItem(
                          value: 'grade:$g',
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _gradeColors[g],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('$g석 전체',
                                  style: AdminTheme.sans(
                                      fontSize: 12,
                                      color: AdminTheme.textPrimary)),
                            ],
                          ),
                        ),
                      ),
                      if (zones.length > 1) ...[
                        const PopupMenuDivider(),
                        ...zones.map(
                          (z) => PopupMenuItem(
                            value: 'zone:$z',
                            child: Text('$z구역',
                                style: AdminTheme.sans(
                                    fontSize: 12,
                                    color: AdminTheme.textPrimary)),
                          ),
                        ),
                      ],
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AdminTheme.border, width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.checklist_rounded,
                              size: 14, color: AdminTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text('빠른 선택',
                              style: AdminTheme.sans(
                                fontSize: 11,
                                color: AdminTheme.textSecondary,
                              )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 선택 액션 바 (선택시만) ──
          if (_selected.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AdminTheme.gold.withValues(alpha: 0.08),
              child: Row(
                children: [
                  Text(
                    '${_selected.length}석 선택됨',
                    style: AdminTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AdminTheme.gold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ...[..._gradeOrder, ..._extraGrades].map(
                    (g) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _actionChip(
                        label: g,
                        color: _gradeColors[g]!,
                        onTap: () => _changeSelectedGrade(g),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_selected.length == 1)
                    IconButton(
                      onPressed: () =>
                          _editSingleSeat(_selected.first),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      color: AdminTheme.textSecondary,
                      tooltip: '상세 편집',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                    ),
                  IconButton(
                    onPressed: _deleteSelected,
                    icon:
                        const Icon(Icons.delete_outline_rounded, size: 16),
                    color: AdminTheme.error,
                    tooltip: '선택 삭제',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: AdminTheme.textTertiary,
                    tooltip: '선택 해제',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

          // ── 캔버스 (인터랙티브 좌석맵) ──
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF12121A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AdminTheme.border.withValues(alpha: 0.3)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                transformationController: _transformCtrl,
                minScale: 0.5,
                maxScale: 5.0,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(200),
                child: SizedBox(
                  width: widget.layout.canvasWidth,
                  height: widget.layout.canvasHeight,
                  child: CustomPaint(
                    painter: _InteractiveSeatMapPainter(
                      seats: _seats,
                      selected: _selected,
                      layout: widget.layout,
                    ),
                    child: _SeatTapLayer(
                      seats: _seats,
                      onTap: _onSeatTap,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── 좌석 정보 패널 (1석 선택시) ──
          if (_showInfo && _selected.length == 1)
            _buildSeatInfoPanel(_seats[_selected.first]),

          // ── 하단 버튼 ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminTheme.textSecondary,
                      side: const BorderSide(
                          color: AdminTheme.border, width: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text('취소',
                        style: AdminTheme.sans(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.gold,
                      foregroundColor: AdminTheme.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(
                      '적용 (${fmt.format(_seats.length)}석)',
                      style:
                          AdminTheme.sans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AdminTheme.gold.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? AdminTheme.gold : AdminTheme.border,
            width: active ? 1 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? AdminTheme.gold : AdminTheme.textTertiary),
            const SizedBox(width: 4),
            Text(
              label,
              style: AdminTheme.sans(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AdminTheme.gold : AdminTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChip({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 0.8),
        ),
        child: Text(
          label,
          style: AdminTheme.sans(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildSeatInfoPanel(LayoutSeat seat) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AdminTheme.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _gradeColors[seat.grade],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${seat.zone}구역 ${seat.row}열 ${seat.number}번',
            style: AdminTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AdminTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _gradeColors[seat.grade]?.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              seat.grade,
              style: AdminTheme.sans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _gradeColors[seat.grade],
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${seat.floor} · (${seat.x.toInt()}, ${seat.y.toInt()})',
            style: AdminTheme.sans(
              fontSize: 10,
              color: AdminTheme.textTertiary,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _editSingleSeat(_selected.first),
            child: const Icon(Icons.edit_rounded,
                size: 14, color: AdminTheme.gold),
          ),
        ],
      ),
    );
  }
}

// ── 인터랙티브 좌석맵 페인터 ──
class _InteractiveSeatMapPainter extends CustomPainter {
  final List<LayoutSeat> seats;
  final Set<int> selected;
  final VenueSeatLayout layout;

  _InteractiveSeatMapPainter({
    required this.seats,
    required this.selected,
    required this.layout,
  });

  static const _gradeColors = {
    'VIP': Color(0xFFD4AF37),
    'R': Color(0xFFE53935),
    'S': Color(0xFF1E88E5),
    'A': Color(0xFF43A047),
    '시야장애': Color(0xFF888888),
    '하우스유보': Color(0xFF4488CC),
    '유보석': Color(0xFF666666),
  };

  @override
  void paint(Canvas canvas, Size size) {
    // Stage
    final stageW = size.width * layout.stageWidthRatio;
    const stageH = 40.0;
    final stageRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, stageH / 2 + 20),
        width: stageW,
        height: stageH,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(stageRect, Paint()..color = const Color(0xFF2A2A34));
    final tp = TextPainter(
      text: const TextSpan(
        text: 'STAGE',
        style: TextStyle(
          color: Color(0xFF888898),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 3,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(size.width / 2 - tp.width / 2, stageH / 2 + 20 - tp.height / 2),
    );

    // Seats
    const dotR = 5.0;
    const selectedR = 7.0;
    final selectedPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < seats.length; i++) {
      final seat = seats[i];
      final color = _gradeColors[seat.grade] ?? const Color(0xFF666666);
      final isSelected = selected.contains(i);
      canvas.drawCircle(
        Offset(seat.x, seat.y),
        isSelected ? selectedR : dotR,
        Paint()..color = color,
      );
      if (isSelected) {
        canvas.drawCircle(
          Offset(seat.x, seat.y),
          selectedR + 1.5,
          selectedPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InteractiveSeatMapPainter old) => true;
}

// ── 좌석 탭 감지 레이어 ──
class _SeatTapLayer extends StatelessWidget {
  final List<LayoutSeat> seats;
  final void Function(int index) onTap;

  const _SeatTapLayer({required this.seats, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) {
        final pos = details.localPosition;
        const hitRadius = 12.0;
        // 가장 가까운 좌석 탐색
        double minDist = double.infinity;
        int closest = -1;
        for (int i = 0; i < seats.length; i++) {
          final dx = seats[i].x - pos.dx;
          final dy = seats[i].y - pos.dy;
          final dist = dx * dx + dy * dy;
          if (dist < minDist) {
            minDist = dist;
            closest = i;
          }
        }
        if (closest >= 0 && minDist <= hitRadius * hitRadius) {
          onTap(closest);
        }
      },
      child: const SizedBox.expand(),
    );
  }
}

/// 미니 좌석맵 Canvas 미리보기 (열 라벨 + 층 구분 + 특수좌석 표시)
class _MiniSeatMapPainter extends CustomPainter {
  final VenueSeatLayout layout;

  _MiniSeatMapPainter(this.layout);

  static const _gradeColors = {
    'VIP': Color(0xFFD4AF37),
    'R': Color(0xFFE53935),
    'S': Color(0xFF1E88E5),
    'A': Color(0xFF43A047),
  };

  static const _seatTypeColors = {
    SeatType.obstructedView: Color(0xFF888888),
    SeatType.houseReserved: Color(0xFF4488CC),
    SeatType.wheelchair: Color(0xFFAA66CC),
    SeatType.reservedHold: Color(0xFF666666),
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.seats.isEmpty) return;

    final scaleX = size.width / layout.canvasWidth;
    final scaleY = size.height / layout.canvasHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offsetX = (size.width - layout.canvasWidth * scale) / 2;
    final offsetY = (size.height - layout.canvasHeight * scale) / 2;

    // ── Stage ──
    final stageW = size.width * layout.stageWidthRatio;
    final stageH = 16.0;
    final stageRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, offsetY + stageH / 2 + 4),
        width: stageW,
        height: stageH,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(stageRect, Paint()..color = const Color(0xFF3A3A44));
    _drawText(canvas, 'STAGE',
      Offset(size.width / 2, offsetY + stageH / 2 + 4),
      fontSize: 7, color: const Color(0xFF888898), letterSpacing: 2,
    );

    // ── 층별 좌석 그룹핑 ──
    final floorGroups = <String, List<LayoutSeat>>{};
    for (final s in layout.seats) {
      final f = s.floor.isNotEmpty ? s.floor : '1층';
      floorGroups.putIfAbsent(f, () => []).add(s);
    }
    final sortedFloors = floorGroups.keys.toList()..sort((a, b) {
      final na = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final nb = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return na.compareTo(nb);
    });

    // ── 층 구분선 + 라벨 (2개 이상 층일 때) ──
    if (sortedFloors.length > 1) {
      for (int i = 1; i < sortedFloors.length; i++) {
        final prevFloor = floorGroups[sortedFloors[i - 1]]!;
        final currFloor = floorGroups[sortedFloors[i]]!;
        final prevMaxY = prevFloor.fold<double>(0, (m, s) => s.y > m ? s.y : m);
        final currMinY = currFloor.fold<double>(double.infinity, (m, s) => s.y < m ? s.y : m);
        final midY = offsetY + ((prevMaxY + currMinY) / 2) * scale;

        // 구분선
        canvas.drawLine(
          Offset(offsetX + 10, midY),
          Offset(size.width - offsetX - 10, midY),
          Paint()
            ..color = const Color(0xFF555566)
            ..strokeWidth = 0.5,
        );

        // 층 라벨 (위쪽 층)
        if (i == 1) {
          _drawText(canvas, sortedFloors[0],
            Offset(size.width - offsetX - 4, midY - 8),
            fontSize: 7, color: const Color(0xFF999999), align: TextAlign.right,
          );
        }
        // 아래쪽 층 라벨
        _drawText(canvas, sortedFloors[i],
          Offset(size.width - offsetX - 4, midY + 4),
          fontSize: 7, color: const Color(0xFF999999), align: TextAlign.right,
        );
      }
    }

    // ── 열 라벨 수집 (row 이름별 좌석 중앙 좌표) ──
    final rowCenters = <String, _RowCenter>{}; // "floor:row" → center
    for (final seat in layout.seats) {
      final key = '${seat.floor}:${seat.row}';
      if (!rowCenters.containsKey(key)) {
        rowCenters[key] = _RowCenter(seat.row, seat.x, seat.y, seat.x, seat.y);
      } else {
        final rc = rowCenters[key]!;
        if (seat.x < rc.minX) rc.minX = seat.x;
        if (seat.x > rc.maxX) rc.maxX = seat.x;
        if (seat.y < rc.minY) rc.minY = seat.y;
        if (seat.y > rc.maxY) rc.maxY = seat.y;
      }
    }

    // 열 라벨 그리기 (각 행 그룹의 위쪽 중앙에)
    final drawnLabels = <String>{};
    for (final entry in rowCenters.entries) {
      final rc = entry.value;
      final label = '${rc.name}열';
      // 같은 이름 열이 여러 층에 있을 수 있으므로 키 전체로 중복 체크
      if (drawnLabels.contains(entry.key)) continue;
      drawnLabels.add(entry.key);

      final cx = offsetX + ((rc.minX + rc.maxX) / 2) * scale;
      final topY = offsetY + rc.minY * scale - 7;

      _drawText(canvas, label, Offset(cx, topY),
        fontSize: 5.5, color: const Color(0xFFAAAAAA),
      );
    }

    // ── Seats ──
    final dotRadius = (scale * 6).clamp(1.5, 4.0);
    for (final seat in layout.seats) {
      final x = offsetX + seat.x * scale;
      final y = offsetY + seat.y * scale;

      // 특수좌석은 다른 색상
      Color color;
      if (seat.seatType != SeatType.normal) {
        color = _seatTypeColors[seat.seatType] ?? const Color(0xFF666666);
      } else {
        color = _gradeColors[seat.grade] ?? const Color(0xFF666666);
      }

      canvas.drawCircle(Offset(x, y), dotRadius, Paint()..color = color);

      // 특수좌석 표시 (작은 마커)
      if (seat.seatType == SeatType.obstructedView) {
        // 대각선 줄
        canvas.drawLine(
          Offset(x - dotRadius * 0.6, y - dotRadius * 0.6),
          Offset(x + dotRadius * 0.6, y + dotRadius * 0.6),
          Paint()..color = Colors.white.withValues(alpha: 0.6)..strokeWidth = 0.5,
        );
      } else if (seat.seatType == SeatType.houseReserved) {
        // 작은 사각형 마커
        canvas.drawRect(
          Rect.fromCenter(center: Offset(x, y), width: dotRadius, height: dotRadius),
          Paint()..color = Colors.white.withValues(alpha: 0.4)..style = PaintingStyle.stroke..strokeWidth = 0.5,
        );
      }
    }
  }

  void _drawText(Canvas canvas, String text, Offset center, {
    double fontSize = 7,
    Color color = const Color(0xFF888898),
    double letterSpacing = 0,
    TextAlign align = TextAlign.center,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color, fontSize: fontSize,
          fontWeight: FontWeight.w600, letterSpacing: letterSpacing,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.right
        ? center.dx - tp.width
        : center.dx - tp.width / 2;
    tp.paint(canvas, Offset(dx, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MiniSeatMapPainter old) => true;
}

/// 열 라벨 위치 계산용
class _RowCenter {
  final String name;
  double minX, minY, maxX, maxY;
  _RowCenter(this.name, this.minX, this.minY, this.maxX, this.maxY);
}
