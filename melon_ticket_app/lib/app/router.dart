import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/platform_utils.dart';
import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/events/event_detail_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/booking/seat_selection_screen.dart';
import '../features/tickets/my_tickets_screen.dart';
import '../features/tickets/ticket_detail_screen.dart';
import '../features/staff_scanner/scanner_screen.dart';
import '../features/admin/admin_dashboard_screen.dart';
import '../features/admin/admin_setup_screen.dart';
import '../features/admin/event_create_screen.dart';
import '../features/admin/web_admin_dashboard.dart';
// web_event_create_screen.dart removed - unified into event_create_screen.dart
import '../features/admin/seat_upload_screen.dart';
import '../features/admin/assignment_check_screen.dart';
import '../features/admin/venue_view_upload_screen.dart';
import '../features/admin/venue_manage_screen.dart';
import '../features/mobile/mobile_main_screen.dart';
import '../features/demo/demo_flow_screen.dart';
import '../features/orders/my_orders_screen.dart';
import '../features/admin/admin_orders_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final path = state.matchedLocation;

      final requiresAuth = path.startsWith('/tickets') ||
          path.startsWith('/orders') ||
          path.startsWith('/checkout') ||
          path.startsWith('/staff') ||
          path.startsWith('/admin');

      if (!isLoggedIn && requiresAuth) {
        return '/login';
      }
      if (isLoggedIn && path == '/login') {
        return '/';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => _MobileBookingFrame(child: child),
        routes: [
          // 모바일 메인 (하단 탭)
          GoRoute(
            path: '/',
            name: 'home',
            builder: (context, state) {
              final focusEventId = state.uri.queryParameters['focusEventId'] ??
                  state.uri.queryParameters['eventId'] ??
                  state.uri.queryParameters['event'];
              return (PlatformUtils.isWeb || PlatformUtils.isMobile)
                  ? MobileMainScreen(focusEventId: focusEventId)
                  : const HomeScreen();
            },
          ),

          GoRoute(
            path: '/demo-flow',
            name: 'demoFlow',
            builder: (context, state) => const DemoFlowScreen(),
          ),

          // 로그인
          GoRoute(
            path: '/login',
            name: 'login',
            builder: (context, state) => const LoginScreen(),
          ),

          // 공연 상세 (공유 링크로 직접 접근 가능)
          GoRoute(
            path: '/event/:eventId',
            name: 'eventDetail',
            builder: (context, state) {
              final eventId = state.pathParameters['eventId']!;
              return EventDetailScreen(eventId: eventId);
            },
          ),

          // 좌석 선택
          GoRoute(
            path: '/seats/:eventId',
            name: 'seatSelection',
            builder: (context, state) {
              final eventId = state.pathParameters['eventId']!;
              final qty = int.tryParse(state.uri.queryParameters['qty'] ?? '');
              final budget =
                  int.tryParse(state.uri.queryParameters['budget'] ?? '');
              final instrument = state.uri.queryParameters['inst'];
              final aiFromQuick = state.uri.queryParameters['ai'] == '1';
              return SeatSelectionScreen(
                eventId: eventId,
                openAIFirst: aiFromQuick,
                initialAIQuantity: qty,
                initialAIMaxBudget: budget,
                initialAIInstrument: instrument,
              );
            },
          ),

          // 링크 유입 전용 빠른 예매 진입
          GoRoute(
            path: '/book/:eventId',
            name: 'quickBook',
            builder: (context, state) {
              final eventId = state.pathParameters['eventId']!;
              return SeatSelectionScreen(eventId: eventId);
            },
          ),

          // 결제
          GoRoute(
            path: '/checkout/:eventId',
            name: 'checkout',
            builder: (context, state) {
              final eventId = state.pathParameters['eventId']!;
              final extra = state.extra as Map<String, dynamic>?;
              return CheckoutScreen(
                eventId: eventId,
                selectedSeatIds: (extra?['seatIds'] as List<String>?) ?? [],
                quantity: (extra?['quantity'] as int?) ?? 1,
              );
            },
          ),

          // 예매 완료
          GoRoute(
            path: '/booking-complete/:orderId',
            name: 'bookingComplete',
            builder: (context, state) {
              final orderId = state.pathParameters['orderId']!;
              return _BookingCompleteScreen(orderId: orderId);
            },
          ),

          // 주문 내역
          GoRoute(
            path: '/orders',
            name: 'orders',
            builder: (context, state) => const MyOrdersScreen(),
          ),

          // 내 티켓
          GoRoute(
            path: '/tickets',
            name: 'tickets',
            builder: (context, state) => const MyTicketsScreen(),
            routes: [
              GoRoute(
                path: ':ticketId',
                name: 'ticketDetail',
                builder: (context, state) {
                  final ticketId = state.pathParameters['ticketId']!;
                  return TicketDetailScreen(ticketId: ticketId);
                },
              ),
            ],
          ),

          // 스태프 스캐너
          GoRoute(
            path: '/staff/scanner',
            name: 'staffScanner',
            builder: (context, state) => const ScannerScreen(),
          ),
        ],
      ),

      // 어드민
      GoRoute(
        path: '/admin',
        name: 'admin',
        builder: (context, state) {
          final width = MediaQuery.sizeOf(context).width;
          final compactWeb = PlatformUtils.isWeb && width < 1100;
          if (compactWeb) return const AdminDashboardScreen();
          return PlatformUtils.isWeb
              ? const WebAdminDashboard()
              : const AdminDashboardScreen();
        },
        routes: [
          GoRoute(
            path: 'setup',
            name: 'adminSetup',
            builder: (context, state) => const AdminSetupScreen(),
          ),
          GoRoute(
            path: 'events/create',
            name: 'adminEventCreate',
            builder: (context, state) => const EventCreateScreen(),
          ),
          GoRoute(
            path: 'events/:eventId/seats',
            name: 'adminSeatUpload',
            builder: (context, state) {
              final eventId = state.pathParameters['eventId']!;
              return SeatUploadScreen(eventId: eventId);
            },
          ),
          GoRoute(
            path: 'events/:eventId/assignments',
            name: 'adminAssignments',
            builder: (context, state) {
              final eventId = state.pathParameters['eventId']!;
              return AssignmentCheckScreen(eventId: eventId);
            },
          ),
          GoRoute(
            path: 'events/:eventId/orders',
            name: 'adminOrders',
            builder: (context, state) {
              final eventId = state.pathParameters['eventId']!;
              return AdminOrdersScreen(eventId: eventId);
            },
          ),
          GoRoute(
            path: 'venues',
            name: 'adminVenues',
            builder: (context, state) => const VenueManageScreen(),
          ),
          GoRoute(
            path: 'venues/:venueId/views',
            name: 'adminVenueViews',
            builder: (context, state) {
              final venueId = state.pathParameters['venueId']!;
              final venueName = state.uri.queryParameters['name'] ?? '공연장';
              return VenueViewUploadScreen(
                venueId: venueId,
                venueName: venueName,
              );
            },
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFC9A84C), size: 48),
            const SizedBox(height: 16),
            Text(
              '페이지를 찾을 수 없습니다',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('홈으로 돌아가기'),
            ),
          ],
        ),
      ),
    ),
  );
});

class _MobileBookingFrame extends StatelessWidget {
  final Widget child;

  const _MobileBookingFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils.isWeb) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useFrame = constraints.maxWidth >= 560;
        if (!useFrame) return child;

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF141A28), Color(0xFF0F141F)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1220),
                      borderRadius: BorderRadius.circular(34),
                      border:
                          Border.all(color: const Color(0xFF2E3A50), width: 1),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xA6000000),
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 예매 완료 화면 (간단한 안내)
class _BookingCompleteScreen extends StatelessWidget {
  final String orderId;
  const _BookingCompleteScreen({required this.orderId});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0D3E67);
    const lineBlue = Color(0xFF2F6FB2);
    const surface = Color(0xFFF3F5F8);
    const softBlue = Color(0xFFE7F0FA);
    const cardBorder = Color(0xFFD7DFE8);
    const textPrimary = Color(0xFF111827);
    const textSecondary = Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text(
          '예매 완료',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        color: lineBlue,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(13)),
                      ),
                      child: const Text(
                        '모바일티켓 발권 완료',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                      child: Column(
                        children: [
                          Container(
                            width: 82,
                            height: 82,
                            decoration: BoxDecoration(
                              color: softBlue,
                              borderRadius: BorderRadius.circular(41),
                              border:
                                  Border.all(color: const Color(0xFFB8CFE5)),
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: lineBlue,
                              size: 44,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            '예매가 완료되었습니다',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '모바일 티켓이 발급되었습니다.\n내 티켓에서 QR코드를 확인해 주세요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 14,
                              height: 1.55,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFFDDE3EA)),
                            ),
                            child: Column(
                              children: [
                                _BookingInfoRow(label: '주문번호', value: orderId),
                                const SizedBox(height: 6),
                                const _BookingInfoRow(
                                  label: '발급채널',
                                  value: '모바일티켓',
                                ),
                                const SizedBox(height: 6),
                                _BookingInfoRow(
                                  label: '발행시각',
                                  value: DateTime.now()
                                      .toIso8601String()
                                      .substring(0, 19)
                                      .replaceFirst('T', ' '),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            color: softBlue,
            padding: EdgeInsets.fromLTRB(
              0,
              6,
              0,
              MediaQuery.of(context).padding.bottom == 0
                  ? 6
                  : MediaQuery.of(context).padding.bottom,
            ),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => context.go('/'),
                      child: const Text(
                        '홈으로',
                        style: TextStyle(
                          color: navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: Color(0xFFB7CADA)),
                  Expanded(
                    child: TextButton(
                      onPressed: () => context.go('/tickets'),
                      child: const Text(
                        '내 티켓',
                        style: TextStyle(
                          color: navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
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
}

class _BookingInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _BookingInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
