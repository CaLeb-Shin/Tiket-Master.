import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/auth/login_screen.dart';
import '../features/admin/web_admin_dashboard.dart';
import '../features/admin/admin_setup_screen.dart';
import '../features/admin/event_create_screen.dart';
import '../features/admin/seat_upload_screen.dart';
import '../features/admin/assignment_check_screen.dart';
import '../features/admin/venue_manage_screen.dart';
import '../features/admin/venue_view_upload_screen.dart';
import '../features/admin/admin_orders_screen.dart';
import '../features/admin/admin_bookers_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final path = state.matchedLocation;

      if (!isLoggedIn && path != '/login') {
        return '/login';
      }
      if (isLoggedIn && path == '/login') {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'dashboard',
        builder: (context, state) => const WebAdminDashboard(),
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
            path: 'events/:eventId/edit',
            name: 'adminEventEdit',
            builder: (context, state) {
              final eventId = state.pathParameters['eventId']!;
              return EventCreateScreen(editEventId: eventId);
            },
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
            path: 'events/:eventId/bookers',
            name: 'adminBookers',
            builder: (context, state) {
              final eventId = state.pathParameters['eventId']!;
              return AdminBookersScreen(eventId: eventId);
            },
          ),
          GoRoute(
            path: 'venues',
            name: 'adminVenues',
            builder: (context, state) => const VenueManageScreen(),
          ),
          GoRoute(
            path: 'venues/:venueId',
            name: 'adminVenueDetail',
            builder: (context, state) {
              final venueId = state.pathParameters['venueId']!;
              return VenueDetailScreen(venueId: venueId);
            },
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
                color: Color(0xFFC42A4D), size: 48),
            const SizedBox(height: 16),
            Text(
              '페이지를 찾을 수 없습니다',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('대시보드로 돌아가기'),
            ),
          ],
        ),
      ),
    ),
  );
});
