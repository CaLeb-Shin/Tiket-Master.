import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

class StorageService {
  final _uuid = const Uuid();

  List<String> _bucketCandidates() {
    final options = Firebase.app().options;
    final projectId = options.projectId.trim();
    final configured = (options.storageBucket ?? '').trim();
    final buckets = <String>{
      if (configured.isNotEmpty) configured,
      if (projectId.isNotEmpty) '$projectId.firebasestorage.app',
      if (projectId.isNotEmpty) '$projectId.appspot.com',
    };
    return buckets.toList();
  }

  bool _shouldTryFallback(FirebaseException e) {
    switch (e.code) {
      case 'retry-limit-exceeded':
      case 'bucket-not-found':
      case 'object-not-found':
      case 'unknown':
        return true;
      default:
        return false;
    }
  }

  Future<String> _uploadWithStorage({
    required FirebaseStorage storage,
    required String path,
    required Uint8List bytes,
    required SettableMetadata metadata,
  }) async {
    storage.setMaxUploadRetryTime(const Duration(seconds: 45));
    storage.setMaxOperationRetryTime(const Duration(seconds: 30));
    final ref = storage.ref().child(path);
    final snapshot = await ref.putData(bytes, metadata);
    return snapshot.ref.getDownloadURL();
  }

  /// 이미지 업로드 (웹용 - bytes)
  Future<String> uploadImageBytes({
    required Uint8List bytes,
    required String folder,
    required String fileName,
  }) async {
    final ext = fileName.split('.').last.toLowerCase();
    final uniqueName = '${_uuid.v4()}.$ext';
    final path = '$folder/$uniqueName';

    final metadata = SettableMetadata(
      contentType: _getContentType(ext),
    );

    Object? lastError;
    for (final bucket in _bucketCandidates()) {
      final normalizedBucket = bucket.trim();
      if (normalizedBucket.isEmpty) continue;
      final storage =
          FirebaseStorage.instanceFor(bucket: 'gs://$normalizedBucket');
      try {
        return await _uploadWithStorage(
          storage: storage,
          path: path,
          bytes: bytes,
          metadata: metadata,
        );
      } on FirebaseException catch (e) {
        lastError = e;
        if (_shouldTryFallback(e)) {
          continue;
        }
        rethrow;
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError is FirebaseException) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: lastError.code,
        message:
            '${lastError.message ?? '업로드 실패'}\n버킷 연결 또는 CORS/권한 설정을 확인해주세요.',
      );
    }
    throw lastError ??
        FirebaseException(
          plugin: 'firebase_storage',
          code: 'unknown',
          message: '업로드 실패: 버킷 연결 또는 네트워크 상태를 확인해주세요.',
        );
  }

  /// 포스터 이미지 업로드
  Future<String> uploadPosterImage({
    required Uint8List bytes,
    required String eventId,
    required String fileName,
  }) async {
    return uploadImageBytes(
      bytes: bytes,
      folder: 'posters/$eventId',
      fileName: fileName,
    );
  }

  /// 좌석배치도 이미지 업로드
  Future<String> uploadSeatMapImage({
    required Uint8List bytes,
    required String venueId,
    required String fileName,
  }) async {
    return uploadImageBytes(
      bytes: bytes,
      folder: 'seat_maps/$venueId',
      fileName: fileName,
    );
  }

  /// 공연장 시점 이미지 업로드
  Future<String> uploadVenueViewImage({
    required Uint8List bytes,
    required String venueId,
    required String zone,
    required String fileName,
  }) async {
    return uploadImageBytes(
      bytes: bytes,
      folder: 'venue_views/$venueId',
      fileName: fileName,
    );
  }

  /// 파일 삭제
  Future<void> deleteFile(String url) async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      await ref.delete();
    } catch (e) {
      // 파일이 없거나 삭제 실패시 무시
    }
  }

  String _getContentType(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }
}
