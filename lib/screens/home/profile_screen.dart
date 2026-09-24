import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import "package:url_launcher/url_launcher.dart";
import 'package:fixio/constants/app_colors.dart';
import 'package:fixio/routes/app_routes.dart';
import 'package:fixio/screens/home/edit_profile_screen.dart';
import 'package:fixio/screens/home/item_detail_screen.dart';
import 'package:fixio/services/firebase_auth_service.dart';
import '../../models/user_model.dart';
import '../chat/chat_list_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  UserModel? user;
  bool       _isAdmin = false;
  late TabController _tabController;

  int    _listingsCount       = 0;
  int    _completedDeals      = 0;
  String _verificationStatus  = 'unverified';

  String? _profileImageUrl;
  int _avatarCacheBuster = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists || !mounted) return;

      final data      = doc.data() as Map<String, dynamic>? ?? {};
      final verStatus = data['verificationStatus'] as String? ?? 'unverified';

      if (verStatus == 'verified' && data['role'] == 'buyer') {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'role': 'vendor'});
      }

      final firestoreImageUrl = data['profileImage'] as String?;

      setState(() {
        user                = UserModel.fromDocument(doc);
        _isAdmin            = data['role'] == 'admin';
        _verificationStatus = verStatus;
        _profileImageUrl    = firestoreImageUrl;
      });

      _fetchStats(uid);
    });
  }

  Future<void> _fetchStats(String uid) async {
    final listingsSnap = await FirebaseFirestore.instance
        .collection('items')
        .where('vendorId', isEqualTo: uid)
        .get();

    final dealsSnap = await FirebaseFirestore.instance
        .collection('orders')
        .where('buyerId', isEqualTo: uid)
        .where('status', isEqualTo: 'completed')
        .get();

    if (mounted) {
      setState(() {
        _listingsCount  = listingsSnap.docs.length;
        _completedDeals = dealsSnap.docs.length;
      });

      FirebaseFirestore.instance.collection('users').doc(uid).update({
        'listingsCount':  _listingsCount,
        'completedDeals': _completedDeals,
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await _showConfirmDialog(
      title:        "Log Out",
      message:      "Are you sure you want to log out?",
      confirmText:  "Log Out",
      confirmColor: Colors.redAccent,
    );
    if (confirmed != true) return;
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    }
  }

  Future<void> _changeAvatar() async {
    final action = await showModalBottomSheet<String>(
      context:         context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AvatarActionSheet(hasPhoto: _profileImageUrl != null),
    );
    if (action == null) return;

    if (action == 'remove') {
      await _removeAvatar();
      return;
    }

    final source = action == 'gallery' ? ImageSource.gallery : ImageSource.camera;

    final pickedFile = await ImagePicker().pickImage(
      source:       source,
      imageQuality: 80,
      maxWidth:     800,
      maxHeight:    800,
    );
    if (pickedFile == null || !mounted) return;

    _showLoadingDialog("Updating photo…");

    final error = await FirebaseAuthService().updateProfile(
      name:             user?.name  ?? '',
      phone:            user?.phone ?? '',
      city:             user?.city  ?? '',
      profileImageFile: File(pickedFile.path),
    );

    if (!mounted) return;
    Navigator.pop(context);

    if (error != null) {
      _showSnack(error, isError: true);
    } else {
      await _refreshProfileImageUrl();
      _showSnack("Profile photo updated!");
    }
  }

  Future<void> _removeAvatar() async {
    _showLoadingDialog("Removing photo…");
    final error = await FirebaseAuthService().removeProfileImage();
    if (!mounted) return;
    Navigator.pop(context);
    if (error != null) {
      _showSnack(error, isError: true);
    } else {
      setState(() {
        _profileImageUrl  = null;
        _avatarCacheBuster++;
      });
      _showSnack("Profile photo removed.");
    }
  }

  Future<void> _refreshProfileImageUrl() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final url = doc.data()?['profileImage'] as String?;
      if (mounted) {
        setState(() {
          _profileImageUrl  = url;
          _avatarCacheBuster++;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _avatarCacheBuster++);
    }
  }

  Future<void> _deleteAccount() async {
    final password = await _showPasswordDialog(
      title:       "Delete Account",
      message:     "This will permanently delete your account and all data.",
      actionLabel: "Delete My Account",
      actionColor: Colors.red,
    );
    if (password == null) return;
    _showLoadingDialog("Deleting account…");
    final error = await FirebaseAuthService().deleteAccount(password: password);
    if (!mounted) return;
    Navigator.pop(context);
    if (error != null) {
      _showSnack(error, isError: true);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    }
  }

  Future<void> _disableAccount() async {
    final password = await _showPasswordDialog(
      title:       "Disable Account",
      message:     "Your account will be hidden and you will be signed out.",
      actionLabel: "Disable Account",
      actionColor: Colors.orange,
    );
    if (password == null) return;
    _showLoadingDialog("Disabling account…");
    final error = await FirebaseAuthService().disableAccount(password: password);
    if (!mounted) return;
    Navigator.pop(context);
    if (error != null) {
      _showSnack(error, isError: true);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context:            context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding:    const EdgeInsets.all(28),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primaryBlue),
              const SizedBox(height: 16),
              Text(message,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required Color  confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:   Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<String?> _showPasswordDialog({
    required String title,
    required String message,
    required String actionLabel,
    required Color  actionColor,
  }) async {
    final ctrl    = TextEditingController();
    bool  obscure = true;
    String? inputError;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize:       MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller:  ctrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: "Current Password",
                  errorText: inputError,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setS(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: actionColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                if (ctrl.text.trim().isEmpty) {
                  setS(() => inputError = "Enter your password");
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: Text(actionLabel, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: isError ? Colors.redAccent : AppColors.successGreen,
      behavior:        SnackBarBehavior.floating,
      shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showAccountActionsSheet() {
    showModalBottomSheet(
      context:         context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AccountActionsSheet(onDisable: _disableAccount, onDelete: _deleteAccount),
    );
  }

  void _openEditProfile() {
    if (user != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EditProfileScreen(userData: user!.toMap())),
      ).then((_) => _refreshProfileImageUrl());
    }
  }

  void _openMessages() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListScreen()));
  }

  void _openRentalHistory() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _RentalHistoryScreen()));
  }

  void _openMyOrders() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _MyOrdersScreen()));
  }

  void _openNotifications() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _NotificationsScreen()));
  }

  void _openPrivacyPolicy() {
    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _PrivacyPolicySheet(),
    );
  }

  void _openHelpSupport() {
    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _HelpSupportSheet(),
    );
  }

  void _openVerification() {
    Navigator.pushNamed(context, AppRoutes.verificationPending);
  }

  @override
  Widget build(BuildContext context) {
    final isVendor = user?.role == UserRole.vendor;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: Column(
        children: [
          _ProfileHeader(
            user:               user,
            isVendor:           isVendor,
            isAdmin:            _isAdmin,
            profileImageUrl:    _profileImageUrl,
            avatarCacheBuster:  _avatarCacheBuster,
            listingsCount:      _listingsCount,
            completedDeals:     _completedDeals,
            verificationStatus: _verificationStatus,
            onChangeAvatar:     _changeAvatar,
            onMoreTap:          _showAccountActionsSheet,
            onEditTap:          _openEditProfile,
            onAdminTap: () => Navigator.pushNamed(context, AppRoutes.adminDashboard),
            tabController:      _tabController,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _AccountTab(
                  user:               user,
                  isVendor:           isVendor,
                  isAdmin:            _isAdmin,
                  verificationStatus: _verificationStatus,
                  onLogout:           _logout,
                  onEdit:             _openEditProfile,
                  onMessages:         _openMessages,
                  onRentalHistory:    _openRentalHistory,
                  onMyOrders:         _openMyOrders,
                  onNotifications:    _openNotifications,
                  onPrivacyPolicy:    _openPrivacyPolicy,
                  onHelpSupport:      _openHelpSupport,
                  onVerification:     _openVerification,
                  onAdminDashboard: () =>
                      Navigator.pushNamed(context, AppRoutes.adminDashboard),
                ),
                const _FavoritesTab(),
                _MyListingsTab(uid: FirebaseAuth.instance.currentUser?.uid ?? ''),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile Header ────────────────────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final UserModel? user;
  final bool       isVendor, isAdmin;
  final String?    profileImageUrl;
  final int        avatarCacheBuster;
  final int        listingsCount, completedDeals;
  final String     verificationStatus;
  final VoidCallback onChangeAvatar, onMoreTap, onEditTap, onAdminTap;
  final TabController tabController;

  const _ProfileHeader({
    required this.user,
    required this.isVendor,
    required this.isAdmin,
    required this.profileImageUrl,
    required this.avatarCacheBuster,
    required this.listingsCount,
    required this.completedDeals,
    required this.verificationStatus,
    required this.onChangeAvatar,
    required this.onMoreTap,
    required this.onEditTap,
    required this.onAdminTap,
    required this.tabController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryBlue, Color(0xFF1565C0)],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "My Profile",
                    style: TextStyle(
                      color:         Colors.white,
                      fontSize:      22,
                      fontWeight:    FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Row(
                    children: [
                      if (isAdmin)
                        GestureDetector(
                          onTap: onAdminTap,
                          child: Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.admin_panel_settings_rounded,
                                    color: Colors.white, size: 14),
                                SizedBox(width: 5),
                                Text('Admin',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      IconButton(
                        onPressed: onMoreTap,
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                      ),
                      IconButton(
                        onPressed: onEditTap,
                        icon: const Icon(Icons.edit_outlined, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onChangeAvatar,
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.5), width: 2.5),
                          ),
                          child: CircleAvatar(
                            radius:          38,
                            backgroundColor: const Color(0xFFBBDEFB),
                            key: ValueKey('avatar_${profileImageUrl}_$avatarCacheBuster'),
                            backgroundImage: _buildAvatarImage(),
                            child: profileImageUrl == null
                                ? const Icon(Icons.person_rounded,
                                color: AppColors.primaryBlue, size: 38)
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          right:  2,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle),
                            child: Icon(Icons.camera_alt_rounded,
                                size: 12, color: AppColors.primaryBlue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user?.name ?? "Loading…",
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (isAdmin) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('ADMIN',
                                    style: TextStyle(
                                        color:         Colors.white,
                                        fontSize:      9,
                                        fontWeight:    FontWeight.w800,
                                        letterSpacing: 0.5)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user?.email ?? "",
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _RoleBadge(isVendor: isVendor),
                            const SizedBox(width: 8),
                            _VerificationBadge(status: verificationStatus),
                          ],
                        ),
                        if (user?.city != null && user!.city.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.location_on_rounded,
                                  size: 12, color: Colors.white.withOpacity(0.7)),
                              const SizedBox(width: 3),
                              Text(
                                user!.city,
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.7), fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border:       Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatItem(
                      value: "$completedDeals",
                      label: "Deals",
                      icon:  Icons.handshake_rounded,
                      color: Colors.greenAccent,
                    ),
                    _VertDivider(),
                    _StatItem(
                      value: "$listingsCount",
                      label: "Listings",
                      icon:  Icons.storefront_rounded,
                      color: Colors.lightBlueAccent,
                    ),
                    _VertDivider(),
                    _StatItem(
                      value: _memberSince(user?.createdAt),
                      label: "Member",
                      icon:  Icons.calendar_today_rounded,
                      color: Colors.pinkAccent,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            TabBar(
              controller:           tabController,
              indicatorColor:       Colors.white,
              indicatorWeight:      3,
              indicatorSize:        TabBarIndicatorSize.label,
              labelColor:           Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: const [
                Tab(text: "Account"),
                Tab(text: "Favorites"),
                Tab(text: "Listings"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ImageProvider? _buildAvatarImage() {
    if (profileImageUrl == null || profileImageUrl!.isEmpty) return null;
    return NetworkImage('$profileImageUrl?cb=$avatarCacheBuster');
  }

  String _memberSince(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return "${months[dt.month - 1]} ${dt.year}";
  }
}

// ── Verification Badge ────────────────────────────────────────────────────────
class _VerificationBadge extends StatelessWidget {
  final String status;
  const _VerificationBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color    color;
    IconData icon;
    String   label;

    switch (status) {
      case 'verified':
        color = Colors.greenAccent;
        icon  = Icons.verified_rounded;
        label = 'Verified';
        break;
      case 'pending':
        color = Colors.orangeAccent;
        icon  = Icons.hourglass_top_rounded;
        label = 'Pending';
        break;
      case 'rejected':
        color = Colors.redAccent;
        icon  = Icons.cancel_rounded;
        label = 'Rejected';
        break;
      default:
        color = Colors.white54;
        icon  = Icons.gpp_maybe_rounded;
        label = 'Unverified';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Role Badge ────────────────────────────────────────────────────────────────
class _RoleBadge extends StatelessWidget {
  final bool isVendor;
  const _RoleBadge({required this.isVendor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isVendor
            ? Colors.purpleAccent.withOpacity(0.25)
            : Colors.greenAccent.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isVendor
              ? Colors.purpleAccent.withOpacity(0.4)
              : Colors.greenAccent.withOpacity(0.4),
        ),
      ),
      child: Text(
        isVendor ? "⚡ Vendor" : "🛒 Buyer",
        style: TextStyle(
          color:      isVendor ? Colors.purpleAccent : Colors.greenAccent,
          fontSize:   11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Stat Item ─────────────────────────────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final String   value, label;
  final IconData icon;
  final Color    color;
  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label,
            style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11)),
      ],
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 32, width: 1, color: Colors.white.withOpacity(0.2));
}

// ── Account Tab ───────────────────────────────────────────────────────────────
class _AccountTab extends StatelessWidget {
  final UserModel? user;
  final bool       isVendor, isAdmin;
  final String     verificationStatus;
  final VoidCallback onLogout, onEdit, onMessages, onRentalHistory,
      onMyOrders, onNotifications, onPrivacyPolicy, onHelpSupport,
      onVerification, onAdminDashboard;

  const _AccountTab({
    required this.user,
    required this.isVendor,
    required this.isAdmin,
    required this.verificationStatus,
    required this.onLogout,
    required this.onEdit,
    required this.onMessages,
    required this.onRentalHistory,
    required this.onMyOrders,
    required this.onNotifications,
    required this.onPrivacyPolicy,
    required this.onHelpSupport,
    required this.onVerification,
    required this.onAdminDashboard,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show verification card only when NOT verified
          if (verificationStatus != 'verified') ...[
            _VerificationCard(status: verificationStatus, onTap: onVerification),
            const SizedBox(height: 20),
          ],

          if (isAdmin) ...[
            _SectionTitle("Admin Zone"),
            _AdminCard(onTap: onAdminDashboard),
            const SizedBox(height: 20),
          ],

          _SectionTitle("My Activity"),
          _MenuCard(children: [
            _MenuItem(
              title:    "Rental History",
              subtitle: "View past rentals",
              icon:     Icons.history_rounded,
              color:    AppColors.primaryBlue,
              onTap:    onRentalHistory,
            ),
            _MenuItem(
              title:    "Messages",
              subtitle: "Chat with buyers & sellers",
              icon:     Icons.chat_bubble_rounded,
              color:    Colors.orange,
              onTap:    onMessages,
            ),
            _MenuItem(
              title:    "My Orders",
              subtitle: "Track your orders",
              icon:     Icons.shopping_bag_rounded,
              color:    Colors.green,
              onTap:    onMyOrders,
            ),
          ]),

          const SizedBox(height: 20),
          _SectionTitle("Settings"),
          _MenuCard(children: [
            _MenuItem(
              title:    "Edit Profile",
              subtitle: "Update your information",
              icon:     Icons.person_rounded,
              color:    Colors.teal,
              onTap:    onEdit,
            ),
            _MenuItem(
              title:    "Notifications",
              subtitle: "Manage alerts & preferences",
              icon:     Icons.notifications_rounded,
              color:    Colors.indigo,
              onTap:    onNotifications,
            ),
            _MenuItem(
              title:    "Privacy Policy",
              subtitle: "Read our privacy terms",
              icon:     Icons.lock_rounded,
              color:    Colors.grey,
              onTap:    onPrivacyPolicy,
            ),
            _MenuItem(
              title:    "Help & Support",
              subtitle: "Get help anytime",
              icon:     Icons.help_rounded,
              color:    Colors.blueGrey,
              onTap:    onHelpSupport,
            ),
          ]),

          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Text("Fixio v1.0.0",
                    style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                const SizedBox(height: 4),
                Text("Made with ❤️ for Pakistan",
                    style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onLogout,
              icon:  const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
              label: const Text("Log Out",
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side:    BorderSide(color: Colors.redAccent.withOpacity(0.35)),
                shape:   RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Verification Card ─────────────────────────────────────────────────────────
class _VerificationCard extends StatelessWidget {
  final String       status;
  final VoidCallback onTap;
  const _VerificationCard({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPending  = status == 'pending';
    final isRejected = status == 'rejected';

    final Color    bgColor     = isPending
        ? Colors.orange.withOpacity(0.1)
        : isRejected
        ? Colors.red.withOpacity(0.1)
        : AppColors.primaryBlue.withOpacity(0.07);
    final Color    borderColor = isPending
        ? Colors.orange.withOpacity(0.3)
        : isRejected
        ? Colors.red.withOpacity(0.3)
        : AppColors.primaryBlue.withOpacity(0.2);
    final Color    iconColor   = isPending
        ? Colors.orange
        : isRejected
        ? Colors.red
        : AppColors.primaryBlue;
    final String   title       = isPending
        ? "Verification Pending"
        : isRejected
        ? "Verification Rejected"
        : "Get Verified";
    final String   subtitle    = isPending
        ? "Your documents are under review. This may take up to 24 hours."
        : isRejected
        ? "Your verification was rejected. Please re-submit your documents."
        : "Verify your identity to become a vendor and list items.";
    final String   buttonLabel = isPending ? "View Status" : isRejected ? "Re-submit" : "Verify Now";
    final IconData icon        = isPending
        ? Icons.hourglass_top_rounded
        : isRejected
        ? Icons.error_rounded
        : Icons.verified_user_rounded;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:    const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        bgColor,
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding:    const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:        iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800, color: iconColor)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.4)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                        color: iconColor, borderRadius: BorderRadius.circular(8)),
                    child: Text(buttonLabel,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section Title ─────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize:      11,
        fontWeight:    FontWeight.w800,
        color:         Colors.grey[500],
        letterSpacing: 1.2,
      ),
    ),
  );
}

// ── Admin Card ────────────────────────────────────────────────────────────────
class _AdminCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AdminCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:    const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color:      const Color(0xFF3B82F6).withOpacity(0.3),
              blurRadius: 16,
              offset:     const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width:  52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin Dashboard',
                      style: TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  SizedBox(height: 3),
                  Text('Manage listings, users & disputes',
                      style: TextStyle(color: Color(0xFF93C5FD), fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding:    const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white, size: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Menu Card & Item ──────────────────────────────────────────────────────────
class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color:        Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
            color:      Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset:     const Offset(0, 5)),
      ],
    ),
    child: Column(children: children),
  );
}

class _MenuItem extends StatelessWidget {
  final String       title, subtitle;
  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;
  const _MenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding:    const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:        color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize:   15,
                            fontWeight: FontWeight.w700,
                            color:      Color(0xFF1A1A2E))),
                    Text(subtitle,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey[300]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Favorites Tab ─────────────────────────────────────────────────────────────
class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text("Not signed in"));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('favorites')
          .orderBy('savedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:    const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryBlue.withOpacity(0.08),
                        AppColors.primaryBlue.withOpacity(0.03),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(Icons.favorite_border_rounded,
                      size: 56, color: AppColors.primaryBlue),
                ),
                const SizedBox(height: 20),
                const Text("No favorites yet",
                    style: TextStyle(
                        fontSize:   18,
                        fontWeight: FontWeight.w800,
                        color:      AppColors.textPrimary)),
                const SizedBox(height: 8),
                Text("Items you ❤️ will appear here",
                    style: TextStyle(color: Colors.grey[500], fontSize: 14)),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:   2,
            mainAxisSpacing:  14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.72,
          ),
          itemCount:   docs.length,
          itemBuilder: (context, index) {
            final data  = {...docs[index].data() as Map<String, dynamic>};
            final docId = docs[index].id;
            data['id'] = docId;
            return _FavoriteCard(data: data, docId: docId, uid: uid);
          },
        );
      },
    );
  }
}

// ── My Listings Tab ───────────────────────────────────────────────────────────
class _MyListingsTab extends StatelessWidget {
  final String uid;
  const _MyListingsTab({required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const Center(child: Text("Not signed in"));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('items')
          .where('vendorId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:    const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color:        AppColors.primaryBlueLight,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(Icons.storefront_outlined,
                      size: 56, color: AppColors.primaryBlue),
                ),
                const SizedBox(height: 20),
                const Text("No listings yet",
                    style: TextStyle(
                        fontSize:   18,
                        fontWeight: FontWeight.w800,
                        color:      AppColors.textPrimary)),
                const SizedBox(height: 8),
                Text("Tap + to post your first item",
                    style: TextStyle(color: Colors.grey[500], fontSize: 14)),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:   2,
            mainAxisSpacing:  14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.65,
          ),
          itemCount:   docs.length,
          itemBuilder: (_, i) {
            final data  = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            return _MyListingCard(data: data, docId: docId, uid: uid);
          },
        );
      },
    );
  }
}

class _MyListingCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String               docId, uid;
  const _MyListingCard({required this.data, required this.docId, required this.uid});

  Future<void> _deleteListing(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:   const Text("Delete Listing"),
        content: const Text("Are you sure you want to delete this listing?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseFirestore.instance.collection('items').doc(docId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Listing deleted")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title     = data['title'] as String? ?? 'Untitled';
    final price     = data['price'];
    final isRent    = data['listingType'] == 'rent';
    final rawImages = data['images'];
    final imageUrl  = (rawImages is List && rawImages.isNotEmpty)
        ? rawImages.first.toString()
        : (data['image'] as String? ?? '');
    final color = isRent ? AppColors.accentOrange : AppColors.primaryBlue;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ItemDetailScreen(data: data, docId: docId)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color:      Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset:     const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: imageUrl.isNotEmpty
                        ? Image.network(imageUrl,
                        fit:          BoxFit.cover,
                        errorBuilder: (_, __, ___) => _NoImg())
                        : _NoImg(),
                  ),
                  Positioned(
                    top:  8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: color, borderRadius: BorderRadius.circular(6)),
                      child: Text(isRent ? "Rent" : "Sale",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Positioned(
                    top:   6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => _deleteListing(context),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.9), shape: BoxShape.circle),
                        child: const Icon(Icons.delete_rounded,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w700,
                          color:      AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (price != null) ...[
                    const SizedBox(height: 3),
                    Text("Rs. $price",
                        style: TextStyle(
                            fontSize:   13,
                            fontWeight: FontWeight.w900,
                            color:      color)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoImg extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF0F2F5),
    child: const Icon(Icons.image_not_supported_outlined,
        color: Colors.grey, size: 32),
  );
}

// ── Favorite Card ─────────────────────────────────────────────────────────────
class _FavoriteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String               docId, uid;
  const _FavoriteCard({required this.data, required this.docId, required this.uid});

  Future<void> _removeFavorite(BuildContext context) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(docId)
        .delete();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         const Text("Removed from favorites",
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.grey[700],
        behavior:        SnackBarBehavior.floating,
        shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title    = data['title'] as String? ?? 'Untitled';
    final price    = data['price'];
    final images   = data['images'];
    final image    = data['image'] as String? ?? '';
    final thumbUrl = (images is List && images.isNotEmpty)
        ? images.first.toString()
        : image;
    final isRent    = data['listingType'] == 'rent';
    final typeColor = isRent ? AppColors.accentOrange : AppColors.primaryBlue;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ItemDetailScreen(data: data, docId: docId)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color:      Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset:     const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: thumbUrl.isNotEmpty
                        ? Image.network(thumbUrl,
                        fit:          BoxFit.cover,
                        errorBuilder: (_, __, ___) => _NoImg())
                        : _NoImg(),
                  ),
                  Positioned(
                    top:  8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: typeColor, borderRadius: BorderRadius.circular(8)),
                      child: Text(isRent ? "Rent" : "Sale",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Positioned(
                    top:   8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _removeFavorite(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color:     Colors.white,
                          shape:     BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color:      Colors.black.withOpacity(0.1),
                                blurRadius: 6)
                          ],
                        ),
                        child: const Icon(Icons.favorite_rounded,
                            color: Colors.redAccent, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w700,
                          color:      AppColors.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (price != null)
                    Text("Rs. $price",
                        style: TextStyle(
                            fontSize:   13,
                            fontWeight: FontWeight.w900,
                            color:      typeColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Inline Screens ────────────────────────────────────────────────────────────

class _RentalHistoryScreen extends StatelessWidget {
  const _RentalHistoryScreen();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text("Rental History", style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('buyerId', isEqualTo: uid)
            .where('listingType', isEqualTo: 'rent')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("No rental history yet",
                      style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding:     const EdgeInsets.all(16),
            itemCount:   docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              return _OrderCard(data: d, isRent: true);
            },
          );
        },
      ),
    );
  }
}

class _MyOrdersScreen extends StatelessWidget {
  const _MyOrdersScreen();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text("My Orders", style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('buyerId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("No orders yet",
                      style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding:     const EdgeInsets.all(16),
            itemCount:   docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              return _OrderCard(data: d, isRent: false);
            },
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool                 isRent;
  const _OrderCard({required this.data, required this.isRent});

  @override
  Widget build(BuildContext context) {
    final title       = data['itemTitle'] as String? ?? 'Order';
    final price       = data['totalPrice'] ?? data['price'];
    final status      = data['status'] as String? ?? 'pending';
    final statusColor = status == 'completed'
        ? Colors.green
        : status == 'cancelled'
        ? Colors.red
        : Colors.orange;

    return Container(
      margin:  const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color:      Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset:     const Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding:    const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:        AppColors.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isRent ? Icons.key_rounded : Icons.shopping_bag_rounded,
              color: AppColors.primaryBlue,
              size:  22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize:   14,
                        fontWeight: FontWeight.w700,
                        color:      AppColors.textPrimary)),
                if (price != null) ...[
                  const SizedBox(height: 3),
                  Text("Rs. $price",
                      style: const TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w600,
                          color:      AppColors.primaryBlue)),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status[0].toUpperCase() + status.substring(1),
              style: TextStyle(
                  color: statusColor, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsScreen extends StatelessWidget {
  const _NotificationsScreen();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text("Notifications", style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('notifications')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("No notifications yet",
                      style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding:     const EdgeInsets.all(16),
            itemCount:   docs.length,
            itemBuilder: (_, i) {
              final d     = docs[i].data() as Map<String, dynamic>;
              final title = d['title'] as String? ?? 'Notification';
              final body  = d['body']  as String? ?? '';
              final read  = d['read']  as bool?   ?? false;
              return Container(
                margin:  const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: read
                      ? Colors.white
                      : AppColors.primaryBlue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: read
                          ? Colors.grey.withOpacity(0.12)
                          : AppColors.primaryBlue.withOpacity(0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding:    const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.notifications_rounded,
                          color: AppColors.primaryBlue, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize:   14,
                                  color:      read
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary)),
                          if (body.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(body,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                    if (!read)
                      Container(
                        width:  8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppColors.primaryBlue, shape: BoxShape.circle),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PrivacyPolicySheet extends StatelessWidget {
  const _PrivacyPolicySheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize:     0.95,
      minChildSize:     0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width:  40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text("Privacy Policy",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text("Last updated: January 2025",
                style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            const Divider(height: 24),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding:    const EdgeInsets.symmetric(horizontal: 24),
                children: const [
                  _PolicySection(
                    title:   "1. Information We Collect",
                    content: "We collect information you provide when registering, including your name, email, phone number, and CNIC for verification purposes. We also collect usage data such as items viewed and transactions made.",
                  ),
                  _PolicySection(
                    title:   "2. How We Use Your Information",
                    content: "Your information is used to provide and improve our services, process transactions, verify your identity, communicate with you about your account, and ensure platform safety.",
                  ),
                  _PolicySection(
                    title:   "3. Data Security",
                    content: "We implement industry-standard security measures to protect your personal information. Your data is encrypted in transit and at rest. We never sell your personal data to third parties.",
                  ),
                  _PolicySection(
                    title:   "4. CNIC & Verification Data",
                    content: "CNIC images are used solely for identity verification. They are stored securely and only accessible to our verification team. Once verified, raw images are deleted after 30 days.",
                  ),
                  _PolicySection(
                    title:   "5. Your Rights",
                    content: "You may request access to, correction of, or deletion of your personal data at any time by contacting support@fixio.pk. We will respond within 7 business days.",
                  ),
                  _PolicySection(
                    title:   "6. Contact",
                    content: "For privacy-related concerns, contact us at: privacy@fixio.pk or call 0800-FIXIO.",
                  ),
                  SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title, content;
  const _PolicySection({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize:   15,
                  fontWeight: FontWeight.w800,
                  color:      AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(content,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
        ],
      ),
    );
  }
}

class _HelpSupportSheet extends StatelessWidget {
  const _HelpSupportSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize:     0.95,
      minChildSize:     0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width:  40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text("Help & Support",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Divider(height: 24),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding:    const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _SupportTile(
                    icon:     Icons.email_rounded,
                    color:    Colors.blue,
                    title:    "Email Support",
                    subtitle: "support@fixio.pk",
                    onTap: () async {
                      final uri = Uri.parse('mailto:support@fixio.pk');
                      if (await canLaunchUrl(uri)) launchUrl(uri);
                    },
                  ),
                  _SupportTile(
                    icon:     Icons.phone_rounded,
                    color:    Colors.green,
                    title:    "Call Us",
                    subtitle: "0800-FIXIO (Mon–Sat 9AM–6PM)",
                    onTap: () async {
                      final uri = Uri.parse('tel:0800-34946');
                      if (await canLaunchUrl(uri)) launchUrl(uri);
                    },
                  ),
                  _SupportTile(
                    icon:     Icons.chat_rounded,
                    color:    Colors.teal,
                    title:    "Live Chat",
                    subtitle: "Chat with our support team",
                    onTap:    () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 20),
                  const Text("FAQs",
                      style: TextStyle(
                          fontSize:   16,
                          fontWeight: FontWeight.w800,
                          color:      AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  const _FaqItem(
                    q: "How do I become a vendor?",
                    a: "Complete identity verification (CNIC + liveness check). Once approved, your account automatically upgrades to Vendor.",
                  ),
                  const _FaqItem(
                    q: "How long does verification take?",
                    a: "Usually under 5 minutes. In some cases it may take up to 24 hours during high volume.",
                  ),
                  const _FaqItem(
                    q: "How do I list an item?",
                    a: "Tap the + button in the bottom navigation bar. Fill in the details, add photos, and submit.",
                  ),
                  const _FaqItem(
                    q: "Is my CNIC data safe?",
                    a: "Yes. CNIC images are encrypted and only used for verification. They are deleted 30 days after approval.",
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportTile extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       title, subtitle;
  final VoidCallback onTap;
  const _SupportTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin:  const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding:    const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color:        color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize:   14,
                          color:      AppColors.textPrimary)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String q, a;
  const _FaqItem({required this.q, required this.a});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin:  const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _open ? AppColors.primaryBlue.withOpacity(0.05) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _open
                ? AppColors.primaryBlue.withOpacity(0.25)
                : Colors.grey.withOpacity(0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.q,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize:   13,
                          color: _open ? AppColors.primaryBlue : AppColors.textPrimary)),
                ),
                Icon(
                  _open ? Icons.remove_rounded : Icons.add_rounded,
                  size:  18,
                  color: AppColors.primaryBlue,
                ),
              ],
            ),
            if (_open) ...[
              const SizedBox(height: 8),
              Text(widget.a,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountActionsSheet extends StatelessWidget {
  final VoidCallback onDisable, onDelete;
  const _AccountActionsSheet({required this.onDisable, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: const BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width:  36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          const Text("Account Actions",
              style: TextStyle(
                  fontSize:   18,
                  fontWeight: FontWeight.w800,
                  color:      AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text("These actions affect your account access",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          _ActionTile(
            icon:      Icons.pause_circle_outline_rounded,
            iconColor: Colors.orange,
            title:     "Disable Account",
            subtitle:  "Temporarily hide your account.",
            onTap: () {
              Navigator.pop(context);
              onDisable();
            },
          ),
          const Divider(height: 1),
          _ActionTile(
            icon:       Icons.delete_forever_rounded,
            iconColor:  Colors.red,
            title:      "Delete Account",
            subtitle:   "Permanently delete all data.",
            titleColor: Colors.red,
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel",
                  style: TextStyle(
                      color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData     icon;
  final Color        iconColor;
  final String       title, subtitle;
  final Color?       titleColor;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding:    const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color:        iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize:   15,
                          fontWeight: FontWeight.w700,
                          color:      titleColor ?? AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

class _AvatarActionSheet extends StatelessWidget {
  final bool hasPhoto;
  const _AvatarActionSheet({required this.hasPhoto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: const BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width:  36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          const Text("Profile Photo",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SourceOptionColored(
                icon:  Icons.photo_library_rounded,
                label: "Gallery",
                color: AppColors.primaryBlue,
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              _SourceOptionColored(
                icon:  Icons.camera_alt_rounded,
                label: "Camera",
                color: AppColors.accentOrange,
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              if (hasPhoto)
                _SourceOptionColored(
                  icon:  Icons.delete_outline_rounded,
                  label: "Remove",
                  color: Colors.redAccent,
                  onTap: () => Navigator.pop(context, 'remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceOptionColored extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _SourceOptionColored({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width:  70,
            height: 70,
            decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(18),
              border:       Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  color:      Colors.grey[600],
                  fontSize:   13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}