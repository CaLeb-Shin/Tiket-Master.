import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _uuid = const Uuid();

  /// 이미지 업로드 (웹용 - bytes)
  Future<String> uploadImageBytes({
    required Uint8List bytes,
    required String folder,
    required String fileName,
  }) async {
    final ext = fileName.split('.').last.toLowerCase();
    final uniqueName = '${_uuid.v4()}.$ext';
    final ref = _storage.ref().child('$folder/$uniqueName');

    final metadata = SettableMetadata(
      contentType: _getContentType(ext),
    );

    final uploadTask = await ref.putData(bytes, metadata);
    return await uploadTask.ref.getDownloadURL();
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
      final ref = _storage.refFromURL(url);
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
