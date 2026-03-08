import 'package:flutter/material.dart';
import 'package:melon_core/presentation/theme.dart';

typedef TicketStateInfo = ({String code, String label, Color color});
typedef GroupTicketViewState = ({int currentPage, bool showGroupOverview});

const _ticketCancelledColor = Color(0xFFFF7A7A);
const _ticketSuccessColor = Color(0xFF58C27D);

String normalizeTicketStatus(String? raw) => switch (raw) {
  'used' => 'used',
  'cancelled' || 'canceled' => 'cancelled',
  _ => 'active',
};

TicketStateInfo resolveTicketState({
  required String? status,
  required bool isCheckedIn,
  required bool isRevealed,
}) {
  final normalizedStatus = normalizeTicketStatus(status);
  if (normalizedStatus == 'cancelled') {
    return (code: 'cancelled', label: '취소됨', color: _ticketCancelledColor);
  }
  if (normalizedStatus == 'used') {
    return (code: 'used', label: '사용 완료', color: _ticketSuccessColor);
  }
  if (!isRevealed) {
    return (code: 'beforeReveal', label: '공개 전', color: AppTheme.gold);
  }
  if (isCheckedIn) {
    return (code: 'entryCheckedIn', label: '입장 완료', color: _ticketSuccessColor);
  }
  return (code: 'active', label: '사용 가능', color: AppTheme.gold);
}

GroupTicketViewState deriveGroupTicketViewState({
  required List<Map<String, dynamic>> siblings,
  required String currentAccessToken,
  required bool preserveGroupContext,
  required int previousPage,
  required bool previousOverview,
}) {
  var initialPage = 0;
  if (siblings.length > 1) {
    initialPage = siblings.indexWhere(
      (sibling) => sibling['accessToken'] == currentAccessToken,
    );
    if (initialPage < 0) {
      initialPage = 0;
    }
  }

  final nextPage = preserveGroupContext && siblings.isNotEmpty
      ? previousPage.clamp(0, siblings.length - 1).toInt()
      : initialPage;

  return (
    currentPage: nextPage,
    showGroupOverview:
        siblings.length > 1 && (preserveGroupContext ? previousOverview : true),
  );
}
