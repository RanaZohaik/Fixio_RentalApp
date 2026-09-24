import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DisputeService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── File a new dispute ────────────────────────────────────────────────────
  Future<String?> fileDispute({
    required String title,
    required String description,
    String? relatedItemId,
    String? reportedUserId,
  }) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return 'Not logged in.';

      await _db.collection('disputes').add({
        'title'          : title,
        'description'    : description,
        'reportedBy'     : uid,
        'relatedItemId'  : relatedItemId ?? '',
        'reportedUserId' : reportedUserId ?? '',
        'status'         : 'open',
        'resolution'     : '',
        'adminNote'      : '',
        'createdAt'      : Timestamp.now(),
      });
      return null; // success
    } catch (e) {
      return e.toString();
    }
  }

  /// Stream of disputes filed BY the current user
  Stream<QuerySnapshot> myDisputes() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('disputes')
        .where('reportedBy', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Stream of disputes AGAINST the current user (vendor)
  Stream<QuerySnapshot> disputesAgainstMe() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('disputes')
        .where('reportedUserId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}