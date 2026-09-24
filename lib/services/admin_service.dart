import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Admin check ───────────────────────────────────────────────────────────
  Future<bool> isAdmin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['role'] == 'admin';
  }

  // ── LISTINGS ──────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> getPendingListings() =>
      _db.collection('items')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots();

  Stream<QuerySnapshot> getAllListings() =>
      _db.collection('items')
          .orderBy('createdAt', descending: true)
          .snapshots();

  Stream<QuerySnapshot> getListingsByStatus(String status) =>
      _db.collection('items')
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .snapshots();

  Future<void> approveItem(String itemId) async {
    await _db.collection('items').doc(itemId).update({
      'status'     : 'approved',
      'approvedAt' : Timestamp.now(),
      'approvedBy' : _auth.currentUser?.uid,
      // Clear any previous rejection reason
      'rejectionReason': FieldValue.delete(),
    });
    await _logAction('approve_item', {'itemId': itemId});
  }

  Future<void> rejectItem(String itemId, String reason) async {
    await _db.collection('items').doc(itemId).update({
      'status'          : 'rejected',
      'rejectionReason' : reason,
      'rejectedAt'      : Timestamp.now(),
      'rejectedBy'      : _auth.currentUser?.uid,
    });
    await _logAction('reject_item', {'itemId': itemId, 'reason': reason});
  }

  Future<void> deleteItem(String itemId) async {
    await _db.collection('items').doc(itemId).delete();
    await _logAction('delete_item', {'itemId': itemId});
  }

  Future<void> featureItem(String itemId, bool featured) async {
    await _db.collection('items').doc(itemId).update({'featured': featured});
    await _logAction(
        featured ? 'feature_item' : 'unfeature_item', {'itemId': itemId});
  }

  // ── USERS ─────────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> getAllUsers() =>
      _db.collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots();

  Stream<QuerySnapshot> getUsersByRole(String role) =>
      _db.collection('users')
          .where('role', isEqualTo: role)
          .orderBy('createdAt', descending: true)
          .snapshots();

  Future<DocumentSnapshot> getUserById(String uid) =>
      _db.collection('users').doc(uid).get();

  /// Suspension is enforced in two ways:
  ///  1. FirebaseAuthService.login() checks isSuspended on sign-in.
  ///  2. SuspensionGuard (StreamBuilder) detects real-time changes and
  ///     signs the user out immediately while showing a blocked screen.
  Future<void> suspendUser(String uid, String reason) async {
    await _db.collection('users').doc(uid).update({
      'isSuspended'      : true,
      'suspensionReason' : reason,
      'suspendedAt'      : Timestamp.now(),
      'suspendedBy'      : _auth.currentUser?.uid,
    });
    await _logAction('suspend_user', {'uid': uid, 'reason': reason});
  }

  Future<void> unsuspendUser(String uid) async {
    await _db.collection('users').doc(uid).update({
      'isSuspended'      : false,
      'suspensionReason' : FieldValue.delete(),
      'suspendedAt'      : FieldValue.delete(),
      'suspendedBy'      : FieldValue.delete(),
    });
    await _logAction('unsuspend_user', {'uid': uid});
  }

  Future<void> changeUserRole(String uid, String newRole) async {
    await _db.collection('users').doc(uid).update({'role': newRole});
    await _logAction('change_role', {'uid': uid, 'newRole': newRole});
  }

  Future<void> verifyUserCNIC(String uid) async {
    await _db.collection('users').doc(uid).update({'cnicStatus': 'verified'});
    await _logAction('verify_cnic', {'uid': uid});
  }

  // ── DISPUTES ──────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> getDisputes() =>
      _db.collection('disputes')
          .orderBy('createdAt', descending: true)
          .snapshots();

  Stream<QuerySnapshot> getOpenDisputes() =>
      _db.collection('disputes')
          .where('status', isEqualTo: 'open')
          .orderBy('createdAt', descending: true)
          .snapshots();

  Future<void> resolveDispute(
      String disputeId, String resolution, String action) async {
    await _db.collection('disputes').doc(disputeId).update({
      'status'     : 'resolved',
      'resolution' : resolution,
      'action'     : action,
      'resolvedAt' : Timestamp.now(),
      'resolvedBy' : _auth.currentUser?.uid,
    });
    await _logAction('resolve_dispute', {
      'disputeId'  : disputeId,
      'resolution' : resolution,
      'action'     : action,
    });
  }

  Future<void> dismissDispute(String disputeId, String reason) async {
    await _db.collection('disputes').doc(disputeId).update({
      'status'      : 'dismissed',
      'dismissNote' : reason,
      'resolvedAt'  : Timestamp.now(),
      'resolvedBy'  : _auth.currentUser?.uid,
    });
    await _logAction('dismiss_dispute', {'disputeId': disputeId});
  }

  Future<void> addDisputeNote(String disputeId, String note) async {
    await _db.collection('disputes').doc(disputeId).update({
      'adminNote'   : note,
      'noteAddedAt' : Timestamp.now(),
    });
  }

  // ── STATS ─────────────────────────────────────────────────────────────────

  Future<Map<String, int>> getDashboardStats() async {
    final results = await Future.wait([
      _db.collection('users').count().get(),
      _db.collection('users').where('isSuspended', isEqualTo: true).count().get(),
      _db.collection('items').where('status', isEqualTo: 'approved').count().get(),
      _db.collection('items').where('status', isEqualTo: 'pending').count().get(),
      _db.collection('items').where('status', isEqualTo: 'rejected').count().get(),
      _db.collection('disputes').where('status', isEqualTo: 'open').count().get(),
      _db.collection('disputes').where('status', isEqualTo: 'resolved').count().get(),
      _db.collection('users').where('role', isEqualTo: 'vendor').count().get(),
    ]);
    return {
      'totalUsers'       : results[0].count ?? 0,
      'suspendedUsers'   : results[1].count ?? 0,
      'activeListings'   : results[2].count ?? 0,
      'pendingReview'    : results[3].count ?? 0,
      'rejectedListings' : results[4].count ?? 0,
      'openDisputes'     : results[5].count ?? 0,
      'resolvedDisputes' : results[6].count ?? 0,
      'totalVendors'     : results[7].count ?? 0,
    };
  }

  // ── LOGS ──────────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> getAdminLogs() =>
      _db.collection('adminLogs')
          .orderBy('timestamp', descending: true)
          .limit(200)
          .snapshots();

  Future<void> _logAction(
      String action, Map<String, dynamic> details) async {
    await _db.collection('adminLogs').add({
      'action'     : action,
      'details'    : details,
      'adminId'    : _auth.currentUser?.uid,
      'adminEmail' : _auth.currentUser?.email,
      'timestamp'  : Timestamp.now(),
    });
  }
}