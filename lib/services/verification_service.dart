// lib/services/verification_service.dart
//
// KEY FIX: waitForFaceMatchResult() now accepts an optional stream subscription
// so the caller can start listening BEFORE the upload begins, eliminating the
// race condition where the Cloud Function writes the result before Flutter's
// listener is attached.

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

// ─── Public enums & models ────────────────────────────────────────────────────

enum VerificationStatus { verified, faceMismatch, livenessFailed, error }

class VerificationResult {
  final VerificationStatus status;
  final double? confidence;
  final String message;

  const VerificationResult({
    required this.status,
    required this.message,
    this.confidence,
  });
}

class CnicData {
  final String? name;
  final String? fatherOrHusbandName;
  final String? cnicNumber;
  final String? dateOfBirth;
  final String? dateOfIssue;
  final String? dateOfExpiry;
  final String? gender;
  final String? address;
  final String? country;
  final bool isExpired;
  final bool cnicHasFace;

  const CnicData({
    this.name,
    this.fatherOrHusbandName,
    this.cnicNumber,
    this.dateOfBirth,
    this.dateOfIssue,
    this.dateOfExpiry,
    this.gender,
    this.address,
    this.country,
    this.isExpired = false,
    this.cnicHasFace = false,
  });

  factory CnicData.fromMap(Map<String, dynamic> map) {
    return CnicData(
      name:                map['name']                as String?,
      fatherOrHusbandName: map['fatherOrHusbandName'] as String?,
      cnicNumber:          map['cnicNumber']          as String?,
      dateOfBirth:         map['dateOfBirth']         as String?,
      dateOfIssue:         map['dateOfIssue']         as String?,
      dateOfExpiry:        map['dateOfExpiry']         as String?,
      gender:              map['gender']              as String?,
      address:             map['address']             as String?,
      country:             map['country']             as String?,
      isExpired:           map['isExpired']           as bool? ?? false,
      cnicHasFace:         map['cnicHasFace']         as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'name':                name,
    'fatherOrHusbandName': fatherOrHusbandName,
    'cnicNumber':          cnicNumber,
    'dateOfBirth':         dateOfBirth,
    'dateOfIssue':         dateOfIssue,
    'dateOfExpiry':        dateOfExpiry,
    'gender':              gender,
    'address':             address,
    'country':             country,
    'isExpired':           isExpired,
    'cnicHasFace':         cnicHasFace,
  };
}

// ─── Service ──────────────────────────────────────────────────────────────────

class VerificationService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth      = FirebaseAuth.instance;
  static final _storage   = FirebaseStorage.instance;

  static String get _uid => _auth.currentUser!.uid;

  static DocumentReference<Map<String, dynamic>> get _userDoc =>
      _firestore.collection('users').doc(_uid)
      as DocumentReference<Map<String, dynamic>>;

  // ─── Verification status checks ────────────────────────────────────────────

  static Future<bool> isUserVerified() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data()?['isVerified'] == true;
  }

  static Future<Map<String, dynamic>> getVerificationStatus() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return {'step': 'not_started'};
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data() ?? {'step': 'not_started'};
  }

  static Future<CnicData?> getCnicData() async {
    final doc     = await _userDoc.get();
    final data    = doc.data();
    if (data == null) return null;
    final cnicMap = data['cnicData'] as Map<String, dynamic>?;
    if (cnicMap == null) return null;
    return CnicData.fromMap(cnicMap);
  }

  // ─── CNIC upload ───────────────────────────────────────────────────────────

  static Future<void> uploadCnicImage(
      File file, {
        required String side,
        void Function(double)? onProgress,
      }) async {
    assert(side == 'front' || side == 'back');

    final ref        = _storage.ref().child('users/$_uid/cnic_$side.jpg');
    final uploadTask = ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));

    uploadTask.snapshotEvents.listen((snap) {
      final progress =
      snap.totalBytes > 0 ? snap.bytesTransferred / snap.totalBytes : 0.0;
      onProgress?.call(progress);
    });

    await uploadTask;
    final url = await ref.getDownloadURL();

    await _userDoc.set({
      side == 'front' ? 'cnicFrontUrl' : 'cnicBackUrl': url,
      'cnic_${side}_Uploaded': true,
      'verificationStep': 'cnic_uploading',
    }, SetOptions(merge: true));
  }

  // ─── Selfie upload ─────────────────────────────────────────────────────────

  static Future<void> uploadLivenessSelfie(
      File file, {
        void Function(double)? onProgress,
      }) async {
    final ref        = _storage.ref().child('users/$_uid/selfie.jpg');
    final uploadTask = ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));

    uploadTask.snapshotEvents.listen((snap) {
      final progress =
      snap.totalBytes > 0 ? snap.bytesTransferred / snap.totalBytes : 0.0;
      onProgress?.call(progress);
    });

    await uploadTask;
    final url = await ref.getDownloadURL();

    await _userDoc.set({
      'selfieUrl':        url,
      'verificationStep': 'selfie_uploaded',
    }, SetOptions(merge: true));
  }

  // ─── Real-time stream ──────────────────────────────────────────────────────

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchVerificationStatus() {
    return _userDoc.snapshots();
  }

  // ─── Polling helpers ───────────────────────────────────────────────────────

  static Future<CnicData> waitForOcrResult({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final completer = Completer<CnicData>();
    late StreamSubscription sub;

    final timer = Timer(timeout, () {
      sub.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('OCR timed out after ${timeout.inSeconds}s', timeout),
        );
      }
    });

    sub = _userDoc.snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) return;

      final ocrStatus = data['ocrStatus'] as String? ?? '';
      final step      = data['verificationStep'] as String? ?? '';

      if (ocrStatus == 'success' || step == 'ocr_done') {
        timer.cancel();
        sub.cancel();
        final cnicMap = data['cnicData'] as Map<String, dynamic>?;
        if (!completer.isCompleted) {
          completer.complete(
            cnicMap != null ? CnicData.fromMap(cnicMap) : const CnicData(),
          );
        }
      } else if (ocrStatus == 'failed') {
        timer.cancel();
        sub.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            Exception(data['ocrError'] ?? 'OCR failed'),
          );
        }
      }
    });

    return completer.future;
  }

  /// FIX: Start the Firestore listener first, THEN upload.
  ///
  /// Usage in your screen:
  ///
  ///   final resultFuture = VerificationService.waitForFaceMatchResult();
  ///   await VerificationService.uploadLivenessSelfie(_selfie!, onProgress: ...);
  ///   final result = await resultFuture;
  ///
  /// This ensures no Firestore write from the Cloud Function can be missed
  /// between upload completion and listener attachment.
  static Future<VerificationResult> waitForFaceMatchResult({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final completer = Completer<VerificationResult>();
    late StreamSubscription sub;

    final timer = Timer(timeout, () {
      sub.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException(
            'Face match timed out after ${timeout.inSeconds}s — '
                'check Firebase Functions logs for errors',
            timeout,
          ),
        );
      }
    });

    sub = _userDoc.snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) return;

      final step       = data['verificationStep'] as String? ?? '';
      final confidence = (data['faceMatchConfidence'] as num?)?.toDouble();

      VerificationResult? result;

      switch (step) {
        case 'completed':
          result = VerificationResult(
            status:     VerificationStatus.verified,
            confidence: confidence,
            message:    'Identity verified successfully! 🎉',
          );

        case 'face_mismatch':
          result = VerificationResult(
            status:     VerificationStatus.faceMismatch,
            confidence: confidence,
            message:    confidence != null && confidence > 0
                ? 'Face does not match CNIC photo '
                '(${confidence.toStringAsFixed(1)}% similarity).'
                : 'Face does not match the CNIC photo.',
          );

        case 'liveness_failed':
          result = VerificationResult(
            status:  VerificationStatus.livenessFailed,
            message: data['faceMatchError'] as String? ??
                'Liveness check failed. Please retake in good lighting.',
          );

        case 'error':
          result = VerificationResult(
            status:  VerificationStatus.error,
            message: data['faceMatchError'] as String? ??
                'An unexpected error occurred. Please try again.',
          );
      }

      if (result != null && !completer.isCompleted) {
        timer.cancel();
        sub.cancel();
        completer.complete(result);
      }
    });

    return completer.future;
  }
}