import 'package:flutter_test/flutter_test.dart';
import 'package:melon_ticket_app/features/mobile_ticket/mobile_ticket_logic.dart';

void main() {
  group('resolveTicketState', () {
    test(
      'returns beforeReveal when ticket is active and reveal is pending',
      () {
        final state = resolveTicketState(
          status: 'active',
          isCheckedIn: false,
          isRevealed: false,
        );

        expect(state.code, 'beforeReveal');
        expect(state.label, '공개 전');
      },
    );

    test('returns active when ticket is revealed and unused', () {
      final state = resolveTicketState(
        status: 'active',
        isCheckedIn: false,
        isRevealed: true,
      );

      expect(state.code, 'active');
      expect(state.label, '사용 가능');
    });

    test('returns entryCheckedIn when active ticket has checked in', () {
      final state = resolveTicketState(
        status: 'active',
        isCheckedIn: true,
        isRevealed: true,
      );

      expect(state.code, 'entryCheckedIn');
      expect(state.label, '입장 완료');
    });

    test('returns used for completed ticket', () {
      final state = resolveTicketState(
        status: 'used',
        isCheckedIn: true,
        isRevealed: true,
      );

      expect(state.code, 'used');
      expect(state.label, '사용 완료');
    });

    test('normalizes canceled spelling to cancelled state', () {
      final state = resolveTicketState(
        status: 'canceled',
        isCheckedIn: false,
        isRevealed: true,
      );

      expect(state.code, 'cancelled');
      expect(state.label, '취소됨');
    });
  });

  group('deriveGroupTicketViewState', () {
    test('opens group overview first for multi-ticket orders', () {
      final state = deriveGroupTicketViewState(
        siblings: const [
          {'accessToken': 'ticket-a'},
          {'accessToken': 'ticket-b'},
        ],
        currentAccessToken: 'ticket-b',
        preserveGroupContext: false,
        previousPage: 0,
        previousOverview: false,
      );

      expect(state.currentPage, 1);
      expect(state.showGroupOverview, isTrue);
    });

    test('preserves current page and overview choice on refresh', () {
      final state = deriveGroupTicketViewState(
        siblings: const [
          {'accessToken': 'ticket-a'},
          {'accessToken': 'ticket-b'},
          {'accessToken': 'ticket-c'},
        ],
        currentAccessToken: 'ticket-a',
        preserveGroupContext: true,
        previousPage: 2,
        previousOverview: false,
      );

      expect(state.currentPage, 2);
      expect(state.showGroupOverview, isFalse);
    });

    test('opening a ticket sets overview to false and correct page', () {
      // First: initial state shows overview
      final initial = deriveGroupTicketViewState(
        siblings: const [
          {'accessToken': 'ticket-a'},
          {'accessToken': 'ticket-b'},
          {'accessToken': 'ticket-c'},
        ],
        currentAccessToken: 'ticket-a',
        preserveGroupContext: false,
        previousPage: 0,
        previousOverview: false,
      );
      expect(initial.showGroupOverview, isTrue);

      // Then: simulating "open ticket #2" → preserve context with
      // overview=false and page=1
      final afterOpen = deriveGroupTicketViewState(
        siblings: const [
          {'accessToken': 'ticket-a'},
          {'accessToken': 'ticket-b'},
          {'accessToken': 'ticket-c'},
        ],
        currentAccessToken: 'ticket-a',
        preserveGroupContext: true,
        previousPage: 1,
        previousOverview: false,
      );
      expect(afterOpen.showGroupOverview, isFalse);
      expect(afterOpen.currentPage, 1);
    });

    test('clamps page index when siblings shrink', () {
      final state = deriveGroupTicketViewState(
        siblings: const [
          {'accessToken': 'ticket-a'},
          {'accessToken': 'ticket-b'},
        ],
        currentAccessToken: 'ticket-a',
        preserveGroupContext: true,
        previousPage: 5,
        previousOverview: false,
      );

      expect(state.currentPage, 1); // clamped to max index
    });

    test('single-ticket order never shows group overview', () {
      final state = deriveGroupTicketViewState(
        siblings: const [
          {'accessToken': 'ticket-a'},
        ],
        currentAccessToken: 'ticket-a',
        preserveGroupContext: false,
        previousPage: 0,
        previousOverview: false,
      );

      expect(state.showGroupOverview, isFalse);
      expect(state.currentPage, 0);
    });
  });
}
