import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FirebaseFirestore get instance => _firestore;

  // Collections
  CollectionReference get venues => _firestore.collection('venues');
  CollectionReference get events => _firestore.collection('events');
  CollectionReference get seats => _firestore.collection('seats');
  CollectionReference get orders => _firestore.collection('orders');
  CollectionReference get seatBlocks => _firestore.collection('seatBlocks');
  CollectionReference get tickets => _firestore.collection('tickets');
  CollectionReference get checkins => _firestore.collection('checkins');
  CollectionReference get users => _firestore.collection('users');
  CollectionReference get venueViews => _firestore.collection('venueViews');

  /// 배치 쓰기 (최대 500개)
  WriteBatch batch() => _firestore.batch();

  /// 트랜잭션
  Future<T> runTransaction<T>(Future<T> Function(Transaction) transactionHandler) {
    return _firestore.runTransaction(transactionHandler);
  }
}
