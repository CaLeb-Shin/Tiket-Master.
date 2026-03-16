import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final offlineCheckinCacheProvider = Provider<OfflineCheckinCache>(
  (ref) => OfflineCheckinCache(),
);

/// 스캐너 오프라인 캐시 — SharedPreferences 기반
/// 공연 2시간 전 전체 티켓을 로컬에 저장하여 네트워크 장애 시에도 입장 처리 가능
class OfflineCheckinCache {
  static const _keyPrefix = 'offline_cache_';
  static const _checkinQueueKey = 'offline_checkin_queue';
  static const _cacheMetaKey = 'offline_cache_meta';

  // ─── 캐시 다운로드 ───────────────────────────────────

  /// 서버에서 받은 티켓 데이터를 로컬에 저장
  Future<void> cacheEventTickets(Map<String, dynamic> serverData) async {
    final prefs = await SharedPreferences.getInstance();
    final eventId = serverData['eventId'] as String;

    // 티켓 데이터 저장 (tickets + mobileTickets 합쳐서 ticketId → json)
    final Map<String, String> ticketMap = {};

    for (final t in (serverData['tickets'] as List? ?? [])) {
      final ticket = Map<String, dynamic>.from(t);
      ticketMap[ticket['id'] as String] = jsonEncode(ticket);
    }
    for (final t in (serverData['mobileTickets'] as List? ?? [])) {
      final ticket = Map<String, dynamic>.from(t);
      // 모바일 티켓은 "mt_" 접두사로 구분 (QR 포맷과 동일)
      ticketMap['mt_${ticket['id']}'] = jsonEncode(ticket);
      // accessToken으로도 검색 가능하도록 인덱스 추가
      if (ticket['accessToken'] != null) {
        ticketMap['at_${ticket['accessToken']}'] = ticket['id'] as String;
      }
    }

    await prefs.setString(
      '$_keyPrefix$eventId',
      jsonEncode(ticketMap),
    );

    // 메타 정보 저장
    final meta = {
      'eventId': eventId,
      'eventTitle': serverData['eventTitle'] ?? '',
      'totalTickets': serverData['totalTickets'] ?? 0,
      'totalMobileTickets': serverData['totalMobileTickets'] ?? 0,
      'downloadedAt': serverData['downloadedAt'] ?? DateTime.now().toIso8601String(),
    };
    await prefs.setString('${_cacheMetaKey}_$eventId', jsonEncode(meta));

    debugPrint('[OfflineCache] 캐시 완료: $eventId (${ticketMap.length}건)');
  }

  /// 캐시된 이벤트 메타 정보 조회
  Future<Map<String, dynamic>?> getCacheMeta(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_cacheMetaKey}_$eventId');
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  /// 캐시가 존재하는지 확인
  Future<bool> hasCacheForEvent(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_keyPrefix$eventId');
  }

  // ─── 오프라인 QR 검증 ──────────────────────────────

  /// 오프라인 모드에서 ticketId로 티켓 검증 + 체크인 처리
  /// 반환값은 온라인 verifyAndCheckIn과 동일한 형태
  Future<Map<String, dynamic>> offlineVerify({
    required String ticketId,
    required String eventId,
    required String checkinStage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$eventId');
    if (raw == null) {
      return {
        'success': false,
        'result': 'noCache',
        'message': '오프라인 캐시가 없습니다. 먼저 캐시를 다운로드하세요.',
      };
    }

    final ticketMap = Map<String, String>.from(jsonDecode(raw));
    final ticketJson = ticketMap[ticketId];
    if (ticketJson == null) {
      return {
        'success': false,
        'result': 'invalidTicket',
        'message': '캐시에 없는 티켓입니다.',
      };
    }

    final ticket = Map<String, dynamic>.from(jsonDecode(ticketJson));
    final status = ticket['status'] as String? ?? '';

    // 취소된 티켓
    if (status == 'cancelled' || status == 'canceled') {
      return {
        'success': false,
        'result': 'cancelled',
        'message': '취소된 티켓입니다.',
        'buyerName': ticket['buyerName'],
        'seatInfo': ticket['seatInfo'],
      };
    }

    // 로컬 체크인 기록 확인
    final localCheckins = await _getLocalCheckins();
    final checkinKey = '${ticketId}_$checkinStage';

    if (localCheckins.contains(checkinKey)) {
      return {
        'success': false,
        'result': 'alreadyUsed',
        'message': checkinStage == 'entry' ? '이미 입장 처리되었습니다.' : '이미 인터미션 처리되었습니다.',
        'buyerName': ticket['buyerName'],
        'seatInfo': ticket['seatInfo'],
      };
    }

    // 서버에서 이미 체크인된 경우
    if (checkinStage == 'entry' && ticket['entryCheckedInAt'] != null) {
      return {
        'success': false,
        'result': 'alreadyUsed',
        'message': '이미 입장 처리되었습니다 (서버 기록).',
        'buyerName': ticket['buyerName'],
        'seatInfo': ticket['seatInfo'],
      };
    }
    if (checkinStage == 'intermission') {
      if (ticket['entryCheckedInAt'] == null && !localCheckins.contains('${ticketId}_entry')) {
        return {
          'success': false,
          'result': 'missingEntryCheckin',
          'message': '1차 입장이 필요합니다.',
          'buyerName': ticket['buyerName'],
          'seatInfo': ticket['seatInfo'],
        };
      }
      if (ticket['intermissionCheckedInAt'] != null) {
        return {
          'success': false,
          'result': 'alreadyUsed',
          'message': '이미 인터미션 처리되었습니다 (서버 기록).',
          'buyerName': ticket['buyerName'],
          'seatInfo': ticket['seatInfo'],
        };
      }
    }

    // 체크인 성공 → 로컬 기록
    await _addLocalCheckin(checkinKey);
    // 동기화 큐에 추가
    await _addToSyncQueue({
      'ticketId': ticketId,
      'eventId': eventId,
      'checkinStage': checkinStage,
      'checkedInAt': DateTime.now().toIso8601String(),
      'isOffline': true,
    });

    return {
      'success': true,
      'result': 'success',
      'message': '입장 확인 (오프라인)',
      'buyerName': ticket['buyerName'],
      'phoneLast4': ticket['phoneLast4'],
      'seatInfo': ticket['seatInfo'],
      'title': '입장 확인 (오프라인)',
    };
  }

  // ─── 로컬 체크인 기록 ──────────────────────────────

  Future<Set<String>> _getLocalCheckins() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('offline_local_checkins') ?? [];
    return list.toSet();
  }

  Future<void> _addLocalCheckin(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('offline_local_checkins') ?? [];
    list.add(key);
    await prefs.setStringList('offline_local_checkins', list);
  }

  // ─── 동기화 큐 ─────────────────────────────────────

  Future<void> _addToSyncQueue(Map<String, dynamic> entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_checkinQueueKey);
    final List<dynamic> queue = raw != null ? jsonDecode(raw) : [];
    queue.add(entry);
    await prefs.setString(_checkinQueueKey, jsonEncode(queue));
  }

  /// 동기화 대기 중인 체크인 수
  Future<int> pendingSyncCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_checkinQueueKey);
    if (raw == null) return 0;
    final List<dynamic> queue = jsonDecode(raw);
    return queue.length;
  }

  /// 동기화 큐 반환 (네트워크 복구 시 서버에 전송용)
  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_checkinQueueKey);
    if (raw == null) return [];
    final List<dynamic> queue = jsonDecode(raw);
    return queue.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// 동기화 완료 후 큐 비우기
  Future<void> clearSyncQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_checkinQueueKey);
  }

  /// 특정 이벤트 캐시 삭제
  Future<void> clearCacheForEvent(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$eventId');
    await prefs.remove('${_cacheMetaKey}_$eventId');
  }

  // ─── 이름/전화번호 수동 검색 (긴급 수동모드용) ────────

  /// 이름 또는 전화번호 뒷자리로 티켓 검색
  Future<List<Map<String, dynamic>>> searchByNameOrPhone({
    required String eventId,
    required String query,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$eventId');
    if (raw == null) return [];

    final ticketMap = Map<String, String>.from(jsonDecode(raw));
    final results = <Map<String, dynamic>>[];
    final queryLower = query.toLowerCase().trim();

    for (final entry in ticketMap.entries) {
      // at_ 인덱스 스킵
      if (entry.key.startsWith('at_')) continue;

      try {
        final ticket = Map<String, dynamic>.from(jsonDecode(entry.value));
        final name = (ticket['buyerName'] as String? ?? '').toLowerCase();
        final phone = ticket['phoneLast4'] as String? ?? '';

        if (name.contains(queryLower) || phone.contains(queryLower)) {
          ticket['_cacheKey'] = entry.key;
          results.add(ticket);
        }
      } catch (_) {
        continue;
      }
    }
    return results;
  }
}
