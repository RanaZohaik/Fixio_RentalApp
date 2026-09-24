import 'package:cloud_firestore/cloud_firestore.dart';

enum CNICStatus     { pending, verified }
enum LivenessStatus { notCompleted, completed }
enum UserRole       { buyer, vendor, admin }

class UserModel {
  final String         uid;
  final String         name;
  final String         email;
  final String         phone;
  final String         city;
  final Timestamp      dob;
  final Timestamp      createdAt;
  final String?        profileImage;
  final CNICStatus     cnicStatus;
  final LivenessStatus livenessStatus;
  final UserRole       role;
  final int            listingsCount;
  final int            completedDeals;
  final double         rating;
  final bool           isSuspended;
  final String         suspensionReason;
  final bool           isDisabled;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.city,
    required this.dob,
    required this.createdAt,
    this.profileImage,
    this.cnicStatus      = CNICStatus.pending,
    this.livenessStatus  = LivenessStatus.notCompleted,
    this.role            = UserRole.buyer,
    this.listingsCount   = 0,
    this.completedDeals  = 0,
    this.rating          = 0.0,
    this.isSuspended     = false,
    this.suspensionReason = '',
    this.isDisabled      = false,
  });

  // ── Factory from Firestore doc ────────────────────────────────────────────
  factory UserModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    CNICStatus parseCNIC(String? val) =>
        val == 'verified' ? CNICStatus.verified : CNICStatus.pending;

    LivenessStatus parseLiveness(String? val) =>
        val == 'completed' ? LivenessStatus.completed : LivenessStatus.notCompleted;

    UserRole parseRole(String? val) {
      switch (val) {
        case 'admin':  return UserRole.admin;
        case 'vendor': return UserRole.vendor;
        default:       return UserRole.buyer;
      }
    }

    return UserModel(
      uid              : doc.id,
      name             : data['name']             as String? ?? '',
      email            : data['email']            as String? ?? '',
      phone            : data['phone']            as String? ?? '',
      city             : data['city']             as String? ?? '',
      dob              : data['dob']              as Timestamp? ?? Timestamp.now(),
      createdAt        : data['createdAt']        as Timestamp? ?? Timestamp.now(),
      profileImage     : data['profileImage']     as String?,
      cnicStatus       : parseCNIC(data['cnicStatus']       as String?),
      livenessStatus   : parseLiveness(data['livenessStatus'] as String?),
      role             : parseRole(data['role']             as String?),
      listingsCount    : (data['listingsCount']  as num?)?.toInt()    ?? 0,
      completedDeals   : (data['completedDeals'] as num?)?.toInt()    ?? 0,
      rating           : (data['rating']         as num?)?.toDouble() ?? 0.0,
      isSuspended      : data['isSuspended']      as bool? ?? false,
      suspensionReason : data['suspensionReason'] as String? ?? '',
      isDisabled       : data['isDisabled']       as bool? ?? false,
    );
  }

  // ── To Firestore map ──────────────────────────────────────────────────────
  Map<String, dynamic> toMap() => {
    'name'             : name,
    'email'            : email,
    'phone'            : phone,
    'city'             : city,
    'dob'              : dob,
    'createdAt'        : createdAt,
    'profileImage'     : profileImage,
    'cnicStatus'       : _cnicStr,
    'livenessStatus'   : _livenessStr,
    'role'             : _roleStr,
    'listingsCount'    : listingsCount,
    'completedDeals'   : completedDeals,
    'rating'           : rating,
    'isSuspended'      : isSuspended,
    'suspensionReason' : suspensionReason,
    'isDisabled'       : isDisabled,
  };

  // ── Private helpers ───────────────────────────────────────────────────────
  String get _cnicStr {
    switch (cnicStatus) {
      case CNICStatus.verified: return 'verified';
      default:                  return 'pending';
    }
  }

  String get _livenessStr {
    switch (livenessStatus) {
      case LivenessStatus.completed: return 'completed';
      default:                       return 'notCompleted';
    }
  }

  String get _roleStr {
    switch (role) {
      case UserRole.admin:  return 'admin';
      case UserRole.vendor: return 'vendor';
      default:              return 'buyer';
    }
  }

  // ── Convenience getters ───────────────────────────────────────────────────
  DateTime get dobDateTime       => dob.toDate();
  DateTime get createdAtDateTime => createdAt.toDate();
  bool get isCNICVerified        => cnicStatus == CNICStatus.verified;
  bool get isLivenessCompleted   => livenessStatus == LivenessStatus.completed;
  bool get isVendor              => role == UserRole.vendor;
  bool get isAdmin               => role == UserRole.admin;
  bool get isActive              => !isSuspended && !isDisabled;

  // ── CopyWith ──────────────────────────────────────────────────────────────
  UserModel copyWith({
    String?         name,
    String?         email,
    String?         phone,
    String?         city,
    Timestamp?      dob,
    String?         profileImage,
    CNICStatus?     cnicStatus,
    LivenessStatus? livenessStatus,
    UserRole?       role,
    int?            listingsCount,
    int?            completedDeals,
    double?         rating,
    bool?           isSuspended,
    String?         suspensionReason,
    bool?           isDisabled,
  }) =>
      UserModel(
        uid              : uid,
        name             : name             ?? this.name,
        email            : email            ?? this.email,
        phone            : phone            ?? this.phone,
        city             : city             ?? this.city,
        dob              : dob              ?? this.dob,
        createdAt        : createdAt,
        profileImage     : profileImage     ?? this.profileImage,
        cnicStatus       : cnicStatus       ?? this.cnicStatus,
        livenessStatus   : livenessStatus   ?? this.livenessStatus,
        role             : role             ?? this.role,
        listingsCount    : listingsCount    ?? this.listingsCount,
        completedDeals   : completedDeals   ?? this.completedDeals,
        rating           : rating           ?? this.rating,
        isSuspended      : isSuspended      ?? this.isSuspended,
        suspensionReason : suspensionReason ?? this.suspensionReason,
        isDisabled       : isDisabled       ?? this.isDisabled,
      );
}