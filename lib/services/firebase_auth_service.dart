import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/user_model.dart';

class FirebaseAuthService {
  final FirebaseAuth      _auth      = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage   _storage   = FirebaseStorage.instance;

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ── Upload profile image to Firebase Storage ───────────────────────────────
  /// Uploads [imageFile] for [uid] and returns the public download URL.
  /// Throws on failure so callers can handle the error properly.
  Future<String> uploadProfileImage(File imageFile, String uid) async {
    final ref = _storage.ref().child('profile_images/$uid.jpg');
    final task = await ref.putFile(
      imageFile,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    // Always get a fresh token so the URL doesn't expire from cache
    return await task.ref.getDownloadURL();
  }

  // ── Finalize Account (called from SignupDetailsScreen) ─────────────────────
  /// Creates the user document in Firestore. If [profileImageFile] is
  /// provided it is uploaded to Firebase Storage first and the resulting
  /// URL is stored in `profileImage` in Firestore AND in Firebase Auth.
  Future<String?> finalizeAccount({
    required String   password,
    required String   name,
    required String   phone,
    required String   city,
    required DateTime dob,
    File?   profileImageFile,
    String? profileImageUrl,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No active session. Please try again.';

      // 1. Set password first
      await user.updatePassword(password);

      // 2. Upload profile image (if provided) → get fresh download URL
      String? imageUrl = profileImageUrl;
      if (profileImageFile != null) {
        try {
          imageUrl = await uploadProfileImage(profileImageFile, user.uid);
        } catch (e) {
          // Image upload failed — log and continue without image
          // (don't block account creation)
          imageUrl = null;
        }
      }

      // 3. Build the map explicitly so we control every field
      final Map<String, dynamic> userData = {
        'uid':          user.uid,
        'name':         name,
        'email':        user.email ?? '',
        'phone':        phone,
        'city':         city,
        'dob':          Timestamp.fromDate(dob),
        'createdAt':    Timestamp.now(),
        'role':         'buyer',
        'listingsCount':  0,
        'completedDeals': 0,
        'verificationStatus': 'unverified',
      };

      // Only write profileImage if we actually have a URL
      if (imageUrl != null && imageUrl.isNotEmpty) {
        userData['profileImage'] = imageUrl;
      }

      // 4. Persist to Firestore
      await _firestore.collection('users').doc(user.uid).set(userData);

      // 5. Sync Firebase Auth display name & photo
      await user.updateDisplayName(name);
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await user.updatePhotoURL(imageUrl);
      }

      return null; // success
    } on FirebaseAuthException catch (e) {
      return _mapError(e);
    } catch (e) {
      return e.toString();
    }
  }

  // ── Update Profile (called from EditProfileScreen / ProfileScreen) ─────────
  Future<String?> updateProfile({
    required String name,
    required String phone,
    required String city,
    File?           profileImageFile,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No active session.';

      String? imageUrl;
      if (profileImageFile != null) {
        // Upload and get a fresh URL — this overwrites the existing file
        // because we always use the same path: profile_images/{uid}.jpg
        imageUrl = await uploadProfileImage(profileImageFile, user.uid);
      }

      final Map<String, dynamic> updates = {
        'name':      name,
        'phone':     phone,
        'city':      city,
        'updatedAt': Timestamp.now(),
      };

      if (imageUrl != null && imageUrl.isNotEmpty) {
        updates['profileImage'] = imageUrl;
      }

      await _firestore.collection('users').doc(user.uid).update(updates);
      await user.updateDisplayName(name);
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await user.updatePhotoURL(imageUrl);
      }

      return null;
    } on FirebaseAuthException catch (e) {
      return _mapError(e);
    } catch (e) {
      return e.toString();
    }
  }

  // ── Remove Profile Image ───────────────────────────────────────────────────
  Future<String?> removeProfileImage() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No active session.';

      // Delete from Storage (ignore "object not found" errors)
      try {
        await _storage
            .ref()
            .child('profile_images/${user.uid}.jpg')
            .delete();
      } catch (_) {}

      // Remove from Firestore — use FieldValue.delete() to fully remove the key
      await _firestore.collection('users').doc(user.uid).update({
        'profileImage': FieldValue.delete(),
        'updatedAt':    Timestamp.now(),
      });

      // Clear from Firebase Auth profile
      await user.updatePhotoURL(null);

      return null;
    } on FirebaseAuthException catch (e) {
      return _mapError(e);
    } catch (e) {
      return e.toString();
    }
  }

  // ── Login ──────────────────────────────────────────────────────────────────
  Future<String?> login(String email, String password) async {
    try {
      final userCred = await _auth.signInWithEmailAndPassword(
        email:    email,
        password: password,
      );

      if (!userCred.user!.emailVerified) {
        await _auth.signOut();
        return 'Please verify your email before logging in.';
      }

      final doc  = await _firestore
          .collection('users')
          .doc(userCred.user!.uid)
          .get();
      final data = doc.data();

      if (data?['isSuspended'] == true) {
        final reason = data?['suspensionReason'] as String? ?? '';
        await _auth.signOut();
        return reason.isNotEmpty
            ? 'Account suspended: $reason'
            : 'Your account has been suspended. Contact support.';
      }

      if (data?['isDisabled'] == true) {
        await _auth.signOut();
        return 'This account has been disabled.';
      }

      return null;
    } on FirebaseAuthException catch (e) {
      return _mapError(e);
    } catch (e) {
      return e.toString();
    }
  }

  // ── Delete Account ─────────────────────────────────────────────────────────
  Future<String?> deleteAccount({required String password}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No active session.';

      final credential = EmailAuthProvider.credential(
        email:    user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      await _firestore.collection('users').doc(user.uid).delete();

      try {
        await _storage
            .ref()
            .child('profile_images/${user.uid}.jpg')
            .delete();
      } catch (_) {}

      await user.delete();
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapError(e);
    } catch (e) {
      return e.toString();
    }
  }

  // ── Disable Account ────────────────────────────────────────────────────────
  Future<String?> disableAccount({required String password}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'No active session.';

      final credential = EmailAuthProvider.credential(
        email:    user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      await _firestore.collection('users').doc(user.uid).update({
        'isDisabled': true,
        'disabledAt': Timestamp.now(),
      });

      await _auth.signOut();
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapError(e);
    } catch (e) {
      return e.toString();
    }
  }

  // ── Favorites stream ───────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> favoritesStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => {...d.data(), 'id': d.id}).toList());
  }

  Future<void> logout() async => _auth.signOut();

  // ── Error mapping ──────────────────────────────────────────────────────────
  String _mapError(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Password is too weak (min 6 characters).';
      case 'requires-recent-login':
        return 'Session expired. Please log out and log back in.';
      case 'user-not-found':
        return 'No account found for this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return e.message ?? 'Authentication error occurred.';
    }
  }
}