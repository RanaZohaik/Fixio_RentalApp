import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../constants/app_colors.dart';
import '../../routes/app_routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE HELPERS  (all reads & writes live here, no external AdminService)
// ─────────────────────────────────────────────────────────────────────────────
final _db = FirebaseFirestore.instance;

Future<void> _logAction(String action, Map<String, dynamic> details) async {
  try {
    await _db.collection('adminLogs').add({
      'action'    : action,
      'details'   : details,
      'adminEmail': FirebaseAuth.instance.currentUser?.email ?? '',
      'adminUid'  : FirebaseAuth.instance.currentUser?.uid ?? '',
      'timestamp' : FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}

// ── Items ──────────────────────────────────────────────────────────────────
Stream<QuerySnapshot> _itemsStream(String filter) {
  final col = _db.collection('items');
  if (filter == 'all')      return col.orderBy('createdAt', descending: true).snapshots();
  if (filter == 'approved') return col.where('status', whereIn: ['approved', 'active']).snapshots();
  return col.where('status', isEqualTo: filter).snapshots();
}

Future<void> _approveItem(String docId) async {
  await _db.collection('items').doc(docId).update({'status': 'approved', 'rejectionReason': ''});
  await _logAction('approve_item', {'itemId': docId});
}

Future<void> _rejectItem(String docId, String reason) async {
  await _db.collection('items').doc(docId).update({'status': 'rejected', 'rejectionReason': reason});
  await _logAction('reject_item', {'itemId': docId, 'reason': reason});
}

Future<void> _deleteItem(String docId) async {
  await _db.collection('items').doc(docId).delete();
  await _logAction('delete_item', {'itemId': docId});
}

Future<void> _featureItem(String docId, bool featured) async {
  await _db.collection('items').doc(docId).update({'featured': featured});
  await _logAction(featured ? 'feature_item' : 'unfeature_item', {'itemId': docId});
}

// ── Users ──────────────────────────────────────────────────────────────────
Stream<QuerySnapshot> _usersStream(String filter) {
  final col = _db.collection('users');
  if (filter == 'vendor') return col.where('role', isEqualTo: 'vendor').snapshots();
  if (filter == 'buyer')  return col.where('role', isEqualTo: 'buyer').snapshots();
  return col.snapshots();
}

Future<void> _suspendUser(String uid, String reason) async {
  await _db.collection('users').doc(uid).update({
    'isSuspended'    : true,
    'suspensionReason': reason,
  });
  await _logAction('suspend_user', {'uid': uid, 'reason': reason});
}

Future<void> _unsuspendUser(String uid) async {
  await _db.collection('users').doc(uid).update({
    'isSuspended'    : false,
    'suspensionReason': '',
  });
  await _logAction('unsuspend_user', {'uid': uid});
}

Future<void> _verifyUserCNIC(String uid) async {
  await _db.collection('users').doc(uid).update({'cnicStatus': 'verified'});
  await _logAction('verify_cnic', {'uid': uid});
}

Future<void> _changeUserRole(String uid, String newRole) async {
  await _db.collection('users').doc(uid).update({'role': newRole});
  await _logAction('change_role', {'uid': uid, 'newRole': newRole});
}

// ── Disputes ───────────────────────────────────────────────────────────────
Stream<QuerySnapshot> _disputesStream(String filter) {
  final col = _db.collection('disputes');
  if (filter == 'open') return col.where('status', isEqualTo: 'open').snapshots();
  return col.snapshots();
}

Future<void> _resolveDispute(String docId, String resolution, String action) async {
  await _db.collection('disputes').doc(docId).update({
    'status'    : 'resolved',
    'resolution': resolution,
    'actionTaken': action,
    'resolvedAt': FieldValue.serverTimestamp(),
  });
  await _logAction('resolve_dispute', {'disputeId': docId});
}

Future<void> _dismissDispute(String docId, String reason) async {
  await _db.collection('disputes').doc(docId).update({
    'status'   : 'dismissed',
    'adminNote': reason,
  });
  await _logAction('dismiss_dispute', {'disputeId': docId});
}

Future<void> _addDisputeNote(String docId, String note) async {
  await _db.collection('disputes').doc(docId).update({'adminNote': note});
  await _logAction('add_note', {'disputeId': docId});
}

// ── Stats ──────────────────────────────────────────────────────────────────
Future<Map<String, int>> _getDashboardStats() async {
  final results = await Future.wait([
    _db.collection('users').get(),                                                        // 0 all users
    _db.collection('users').where('role', isEqualTo: 'vendor').get(),                    // 1 vendors
    _db.collection('users').where('isSuspended', isEqualTo: true).get(),                 // 2 suspended
    _db.collection('items').where('status', isEqualTo: 'pending').get(),                 // 3 pending
    _db.collection('items').where('status', whereIn: ['active', 'approved']).get(),      // 4 active/approved
    _db.collection('items').where('status', isEqualTo: 'rejected').get(),                // 5 rejected
    _db.collection('disputes').where('status', isEqualTo: 'open').get(),                 // 6 open
    _db.collection('disputes').where('status', isEqualTo: 'resolved').get(),            // 7 resolved
  ]);
  return {
    'totalUsers'       : results[0].docs.length,
    'totalVendors'     : results[1].docs.length,
    'suspendedUsers'   : results[2].docs.length,
    'pendingReview'    : results[3].docs.length,
    'activeListings'   : results[4].docs.length,
    'rejectedListings' : results[5].docs.length,
    'openDisputes'     : results[6].docs.length,
    'resolvedDisputes' : results[7].docs.length,
  };
}

// ── Logs ───────────────────────────────────────────────────────────────────
Stream<QuerySnapshot> _logsStream() =>
    _db.collection('adminLogs').orderBy('timestamp', descending: true).limit(50).snapshots();

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN DASHBOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTab = 0;

  static const _navItems = [
    _NavItem(icon: Icons.dashboard_rounded,      label: 'Overview'),
    _NavItem(icon: Icons.pending_actions_rounded, label: 'Listings'),
    _NavItem(icon: Icons.people_alt_rounded,      label: 'Users'),
    _NavItem(icon: Icons.gavel_rounded,           label: 'Disputes'),
    _NavItem(icon: Icons.history_rounded,         label: 'Logs'),
  ];

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        title  : 'Sign Out',
        message: 'Are you sure you want to sign out?',
        confirm: 'Sign Out',
        danger : true,
      ),
    );
    if (ok == true && mounted) {
      await FirebaseAuth.instance.signOut();
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 720;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FA),
      body: isWide ? _wideLayout() : _narrowLayout(),
    );
  }

  Widget _wideLayout() => Row(children: [
    _Sidebar(
      items        : _navItems,
      selectedIndex: _selectedTab,
      onSelect     : (i) => setState(() => _selectedTab = i),
      onLogout     : _logout,
    ),
    Expanded(child: _buildContent()),
  ]);

  Widget _narrowLayout() => Column(children: [
    _TopBar(title: _navItems[_selectedTab].label, onLogout: _logout),
    Expanded(child: _buildContent()),
    _BottomNav(
      items        : _navItems,
      selectedIndex: _selectedTab,
      onSelect     : (i) => setState(() => _selectedTab = i),
    ),
  ]);

  Widget _buildContent() {
    switch (_selectedTab) {
      case 0:  return const _OverviewTab();
      case 1:  return const _ListingsTab();
      case 2:  return const _UsersTab();
      case 3:  return const _DisputesTab();
      case 4:  return const _LogsTab();
      default: return const _OverviewTab();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String   label;
  const _NavItem({required this.icon, required this.label});
}

class _Sidebar extends StatelessWidget {
  final List<_NavItem>    items;
  final int               selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback      onLogout;
  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width     : 240,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F2544), Color(0xFF1B3D6E)],
          begin : Alignment.topLeft,
          end   : Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color       : Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(13),
                  border      : Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin Panel',
                      style: TextStyle(
                          color      : Colors.white,
                          fontSize   : 15,
                          fontWeight : FontWeight.w800,
                          letterSpacing: 0.3)),
                  Text('BazaarBuddy',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(color: Colors.white.withOpacity(0.12), height: 1),
          ),
          const SizedBox(height: 16),
          ...List.generate(items.length, (i) {
            final sel = i == selectedIndex;
            return GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin  : const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                padding : const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color       : sel ? Colors.white.withOpacity(0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border      : sel ? Border.all(color: Colors.white.withOpacity(0.22)) : null,
                ),
                child: Row(children: [
                  Icon(items[i].icon,
                      size : 18,
                      color: sel ? Colors.white : Colors.white54),
                  const SizedBox(width: 12),
                  Text(items[i].label,
                      style: TextStyle(
                          fontSize  : 13.5,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color     : sel ? Colors.white : Colors.white54)),
                  if (sel) ...[
                    const Spacer(),
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                    ),
                  ],
                ]),
              ),
            );
          }),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(color: Colors.white.withOpacity(0.12), height: 1),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: onLogout,
              child: Container(
                padding   : const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color       : Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border      : Border.all(color: Colors.red.withOpacity(0.25)),
                ),
                child: const Row(children: [
                  Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Text('Sign Out',
                      style: TextStyle(
                          color     : Colors.redAccent,
                          fontSize  : 13.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String       title;
  final VoidCallback onLogout;
  const _TopBar({required this.title, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFF0F2544), Color(0xFF1B3D6E)]),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color       : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Admin Panel',
                      style: TextStyle(
                          color     : Colors.white,
                          fontSize  : 15,
                          fontWeight: FontWeight.w800)),
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            Container(
              padding   : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color       : Colors.greenAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border      : Border.all(color: Colors.greenAccent.withOpacity(0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 5, height: 5,
                  decoration: const BoxDecoration(
                      color: Colors.greenAccent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                const Text('Live',
                    style: TextStyle(
                        color     : Colors.greenAccent,
                        fontSize  : 10,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
            IconButton(
              icon     : const Icon(Icons.logout_rounded,
                  color: Colors.white54, size: 20),
              onPressed: onLogout,
            ),
          ]),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final List<_NavItem>    items;
  final int               selectedIndex;
  final ValueChanged<int> onSelect;
  const _BottomNav({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color    : Colors.white,
        border   : Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
              color     : Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset    : const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: List.generate(items.length, (i) {
              final sel = i == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap   : () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  child   : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(items[i].icon,
                          size : 22,
                          color: sel ? AppColors.primaryBlue : Colors.grey.shade400),
                      const SizedBox(height: 3),
                      Text(items[i].label,
                          style: TextStyle(
                              fontSize  : 9,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                              color     : sel ? AppColors.primaryBlue : Colors.grey.shade400)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OVERVIEW TAB  — real-time stats + recent logs
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  late Future<Map<String, int>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _getDashboardStats();
  }

  void _refresh() => setState(() => _statsFuture = _getDashboardStats());

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      color    : AppColors.primaryBlue,
      child    : SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child  : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: _PageHeader(
                  title   : 'Dashboard Overview',
                  subtitle: 'Real-time platform statistics',
                  icon    : Icons.dashboard_rounded,
                ),
              ),
              GestureDetector(
                onTap: _refresh,
                child: Container(
                  padding   : const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color       : AppColors.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: AppColors.primaryBlue, size: 18),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            FutureBuilder<Map<String, int>>(
              future : _statsFuture,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 200,
                    child : Center(child: CircularProgressIndicator(
                        color: AppColors.primaryBlue)),
                  );
                }
                if (snap.hasError) {
                  return _ErrorCard(message: 'Failed to load stats: ${snap.error}');
                }
                final s = snap.data!;
                return Column(children: [
                  _statsRow([
                    _StatData(
                        label: 'Total Users',
                        value: '${s['totalUsers']}',
                        sub  : '${s['suspendedUsers']} suspended',
                        icon : Icons.people_alt_rounded,
                        color: AppColors.primaryBlue),
                    _StatData(
                        label: 'Total Vendors',
                        value: '${s['totalVendors']}',
                        sub  : 'Active sellers',
                        icon : Icons.storefront_rounded,
                        color: Colors.purple),
                  ]),
                  const SizedBox(height: 12),
                  _statsRow([
                    _StatData(
                        label: 'Pending Review',
                        value: '${s['pendingReview']}',
                        sub  : 'Awaiting approval',
                        icon : Icons.pending_actions_rounded,
                        color: AppColors.accentOrange),
                    _StatData(
                        label: 'Active Listings',
                        value: '${s['activeListings']}',
                        sub  : '${s['rejectedListings']} rejected',
                        icon : Icons.check_circle_rounded,
                        color: AppColors.successGreen),
                  ]),
                  const SizedBox(height: 12),
                  _statsRow([
                    _StatData(
                        label: 'Open Disputes',
                        value: '${s['openDisputes']}',
                        sub  : 'Need resolution',
                        icon : Icons.gavel_rounded,
                        color: Colors.redAccent),
                    _StatData(
                        label: 'Resolved',
                        value: '${s['resolvedDisputes']}',
                        sub  : 'Disputes closed',
                        icon : Icons.task_alt_rounded,
                        color: AppColors.successGreen),
                  ]),
                ]);
              },
            ),
            const SizedBox(height: 28),
            const _PageHeader(
              title   : 'Recent Activity',
              subtitle: 'Latest admin actions',
              icon    : Icons.history_rounded,
            ),
            const SizedBox(height: 14),
            StreamBuilder<QuerySnapshot>(
              stream : _logsStream(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(
                      color: AppColors.primaryBlue));
                }
                if (snap.hasError) {
                  return _ErrorCard(message: 'Log error: ${snap.error}');
                }
                final docs = snap.data?.docs.take(6).toList() ?? [];
                if (docs.isEmpty) {
                  return const _EmptyState(
                      icon: Icons.history, message: 'No activity yet');
                }
                return Column(
                  children: docs.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child  : _LogTile(data: d.data() as Map<String, dynamic>),
                  )).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsRow(List<_StatData> cards) => Row(
    children: List.generate(cards.length, (i) => Expanded(
      child: Padding(
        padding: EdgeInsets.only(
            left : i == 0 ? 0 : 6,
            right: i == cards.length - 1 ? 0 : 6),
        child: _StatCard(data: cards[i]),
      ),
    )),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LISTINGS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _ListingsTab extends StatefulWidget {
  const _ListingsTab();

  @override
  State<_ListingsTab> createState() => _ListingsTabState();
}

class _ListingsTabState extends State<_ListingsTab> {
  String _filter = 'pending';

  static const _filters = ['pending', 'approved', 'rejected', 'all'];

  Color _filterColor(String f) {
    switch (f) {
      case 'pending' : return AppColors.accentOrange;
      case 'approved': return AppColors.successGreen;
      case 'rejected': return Colors.redAccent;
      default        : return AppColors.primaryBlue;
    }
  }

  String _filterLabel(String f) {
    if (f == 'all') return 'All';
    return f[0].toUpperCase() + f.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Header with filter chips ────────────────────────────────────────
      Container(
        color  : Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child  : Row(children: [
          const Text('Listings',
              style: TextStyle(
                  fontSize  : 18,
                  fontWeight: FontWeight.w800,
                  color     : AppColors.textPrimary)),
          const SizedBox(width: 12),
          // FIX: Flexible + SingleChildScrollView prevents overflow
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((f) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _FilterChip(
                      label   : _filterLabel(f),
                      selected: _filter == f,
                      color   : _filterColor(f),
                      onTap   : () => setState(() => _filter = f),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ]),
      ),

      // ── List ────────────────────────────────────────────────────────────
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream : _itemsStream(_filter),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(
                  color: AppColors.primaryBlue));
            }
            if (snap.hasError) {
              return _ErrorCard(
                  message: 'Error loading listings.\n${snap.error}');
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return _EmptyState(
                  icon   : Icons.storefront_outlined,
                  message: 'No $_filter listings');
            }
            return ListView.separated(
              padding         : const EdgeInsets.all(16),
              itemCount       : docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder     : (_, i) => _ListingAdminCard(
                data : docs[i].data() as Map<String, dynamic>,
                docId: docs[i].id,
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USERS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  String _filter = 'all';
  final  _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Header ──────────────────────────────────────────────────────────
      Container(
        color  : Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child  : Column(children: [
          Row(children: [
            const Text('Users',
                style: TextStyle(
                    fontSize  : 18,
                    fontWeight: FontWeight.w800,
                    color     : AppColors.textPrimary)),
            const SizedBox(width: 12),
            _FilterChip(
                label   : 'All',
                selected: _filter == 'all',
                color   : AppColors.primaryBlue,
                onTap   : () => setState(() => _filter = 'all')),
            const SizedBox(width: 6),
            _FilterChip(
                label   : 'Vendors',
                selected: _filter == 'vendor',
                color   : Colors.purple,
                onTap   : () => setState(() => _filter = 'vendor')),
            const SizedBox(width: 6),
            _FilterChip(
                label   : 'Buyers',
                selected: _filter == 'buyer',
                color   : AppColors.primaryBlue,
                onTap   : () => setState(() => _filter = 'buyer')),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged : (v) => setState(() => _query = v.toLowerCase()),
            style     : const TextStyle(
                color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText   : 'Search by name or email…',
              hintStyle  : const TextStyle(color: AppColors.textSecondary),
              prefixIcon : const Icon(Icons.search,
                  color: AppColors.textSecondary, size: 18),
              filled     : true,
              fillColor  : const Color(0xFFF5F7FB),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide  : BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide  : BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide  : const BorderSide(
                      color: AppColors.primaryBlue)),
            ),
          ),
        ]),
      ),

      // ── List ────────────────────────────────────────────────────────────
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          // Key forces stream rebuild when filter changes
          key   : ValueKey(_filter),
          stream: _usersStream(_filter),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(
                  color: AppColors.primaryBlue));
            }
            if (snap.hasError) {
              return _ErrorCard(
                  message: 'Error loading users.\n${snap.error}');
            }
            var docs = snap.data?.docs ?? [];
            // Client-side search filter
            if (_query.isNotEmpty) {
              docs = docs.where((d) {
                final data  = d.data() as Map<String, dynamic>;
                final name  = (data['name']  as String? ?? '').toLowerCase();
                final email = (data['email'] as String? ?? '').toLowerCase();
                return name.contains(_query) || email.contains(_query);
              }).toList();
            }
            if (docs.isEmpty) {
              return const _EmptyState(
                  icon: Icons.person_search, message: 'No users found');
            }
            return ListView.separated(
              padding         : const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount       : docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder     : (_, i) => _UserCard(
                data: docs[i].data() as Map<String, dynamic>,
                uid : docs[i].id,
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DISPUTES TAB
// ─────────────────────────────────────────────────────────────────────────────

class _DisputesTab extends StatefulWidget {
  const _DisputesTab();

  @override
  State<_DisputesTab> createState() => _DisputesTabState();
}

class _DisputesTabState extends State<_DisputesTab> {
  String _filter = 'open';

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color  : Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child  : Row(children: [
          const Text('Disputes',
              style: TextStyle(
                  fontSize  : 18,
                  fontWeight: FontWeight.w800,
                  color     : AppColors.textPrimary)),
          const SizedBox(width: 12),
          _FilterChip(
              label   : 'Open',
              selected: _filter == 'open',
              color   : Colors.redAccent,
              onTap   : () => setState(() => _filter = 'open')),
          const SizedBox(width: 6),
          _FilterChip(
              label   : 'All',
              selected: _filter == 'all',
              color   : AppColors.primaryBlue,
              onTap   : () => setState(() => _filter = 'all')),
        ]),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          key   : ValueKey(_filter),
          stream: _disputesStream(_filter),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(
                  color: AppColors.primaryBlue));
            }
            if (snap.hasError) {
              return _ErrorCard(
                  message: 'Error loading disputes.\n${snap.error}');
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return _EmptyState(
                  icon   : Icons.gavel_outlined,
                  message: _filter == 'open'
                      ? 'No open disputes'
                      : 'No disputes found');
            }
            return ListView.separated(
              padding         : const EdgeInsets.all(16),
              itemCount       : docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder     : (_, i) => _DisputeCard(
                data : docs[i].data() as Map<String, dynamic>,
                docId: docs[i].id,
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _LogsTab extends StatelessWidget {
  const _LogsTab();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color  : Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child  : const Row(children: [
          Text('Action Logs',
              style: TextStyle(
                  fontSize  : 18,
                  fontWeight: FontWeight.w800,
                  color     : AppColors.textPrimary)),
        ]),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream : _logsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(
                  color: AppColors.primaryBlue));
            }
            if (snap.hasError) {
              return _ErrorCard(message: 'Error loading logs.\n${snap.error}');
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const _EmptyState(
                  icon: Icons.history, message: 'No logs yet');
            }
            return ListView.separated(
              padding         : const EdgeInsets.all(16),
              itemCount       : docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder     : (_, i) => _LogTile(
                  data: docs[i].data() as Map<String, dynamic>),
            );
          },
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

// ── Stat Card ─────────────────────────────────────────────────────────────────

class _StatData {
  final String label, value, sub;
  final IconData icon;
  final Color    color;
  const _StatData({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
  });
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) => Container(
    padding   : const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color       : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border      : Border.all(color: Colors.grey.shade100),
      boxShadow   : [
        BoxShadow(
            color     : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset    : const Offset(0, 3)),
      ],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color       : data.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(data.icon, color: data.color, size: 18),
      ),
      const SizedBox(height: 14),
      Text(data.value,
          style: const TextStyle(
              color     : AppColors.textPrimary,
              fontSize  : 26,
              fontWeight: FontWeight.w800,
              height    : 1)),
      const SizedBox(height: 3),
      Text(data.label,
          style: const TextStyle(
              color     : AppColors.textPrimary,
              fontSize  : 12,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(data.sub,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 10)),
    ]),
  );
}

// ── Listing Admin Card ────────────────────────────────────────────────────────

class _ListingAdminCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String               docId;
  const _ListingAdminCard({required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    final status          = data['status']                                   as String? ?? 'pending';
    final title           = data['title']                                    as String? ?? 'Untitled';
    final price           = data['price'];
    final seller          = data['sellerName'] ?? data['vendorName']         as String? ?? 'Unknown';
    final category        = data['categoryName'] ?? data['category']         as String? ?? '';
    final condition       = data['condition']                                as String? ?? '';
    final city            = data['city']                                     as String? ?? '';
    final description     = data['description']                              as String? ?? '';
    final rejectionReason = data['rejectionReason']                          as String? ?? '';
    final featured        = data['featured'] == true;
    final imageUrl        =
        (data['images'] as List?)?.firstOrNull?.toString() ??
            data['image'] as String? ?? '';

    final statusColor = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(
          color: status == 'pending'
              ? AppColors.accentOrange.withOpacity(0.3)
              : status == 'rejected'
              ? Colors.redAccent.withOpacity(0.2)
              : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Content ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Thumbnail
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl.isNotEmpty
                    ? Image.network(imageUrl,
                    width: 80, height: 80, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _ImgPlaceholder())
                    : _ImgPlaceholder(),
              ),
              if (featured)
                Positioned(
                  top: 4, left: 4,
                  child: Container(
                    padding   : const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.amber, shape: BoxShape.circle),
                    child: const Icon(Icons.star_rounded,
                        size: 10, color: Colors.white),
                  ),
                ),
            ]),
            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              color     : AppColors.textPrimary,
                              fontSize  : 14,
                              fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (featured) ...[
                      _Badge(label: 'Featured', color: Colors.amber, small: true),
                      const SizedBox(width: 4),
                    ],
                    _Badge(
                        label: status.toUpperCase(),
                        color: statusColor,
                        small: true),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if ((seller as String).isNotEmpty) seller,
                      if (city.isNotEmpty)               city,
                      if (category.isNotEmpty)           category,
                      if (condition.isNotEmpty)          condition,
                    ].join('  •  '),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text('Rs. $price',
                      style: const TextStyle(
                          color     : AppColors.primaryBlue,
                          fontSize  : 15,
                          fontWeight: FontWeight.w800)),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(description,
                        style: const TextStyle(
                            color  : AppColors.textSecondary,
                            fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ]),
        ),

        // ── Rejection reason ───────────────────────────────────────────────
        if (rejectionReason.isNotEmpty)
          _InfoBanner(
              icon   : Icons.info_outline,
              text   : 'Rejected: $rejectionReason',
              color  : Colors.redAccent,
              bgAlpha: 0.05),

        // ── Actions ────────────────────────────────────────────────────────
        _CardFooter(
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            if (status == 'pending') ...[
              _ActionBtn(
                label: 'Approve',
                icon : Icons.check_rounded,
                color: AppColors.successGreen,
                onTap: () => _approveItem(docId),
              ),
              _ActionBtn(
                label: 'Reject',
                icon : Icons.close_rounded,
                color: Colors.redAccent,
                onTap: () => _showRejectDialog(context),
              ),
            ] else ...[
              _ActionBtn(
                label: featured ? 'Unfeature' : 'Feature',
                icon : featured
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: Colors.amber,
                onTap: () => _featureItem(docId, !featured),
              ),
              if (status == 'rejected')
                _ActionBtn(
                  label: 'Re-approve',
                  icon : Icons.check_circle_outline_rounded,
                  color: AppColors.successGreen,
                  onTap: () => _approveItem(docId),
                ),
              _ActionBtn(
                label: 'Delete',
                icon : Icons.delete_outline_rounded,
                color: Colors.redAccent,
                onTap: () => _showDeleteConfirm(context),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  void _showRejectDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => _InputDialog(
        title       : 'Reject Listing',
        hint        : 'Reason for rejection…',
        confirmText : 'Reject',
        confirmColor: Colors.redAccent,
        controller  : ctrl,
        onConfirm   : () {
          if (ctrl.text.trim().isNotEmpty) {
            _rejectItem(docId, ctrl.text.trim());
          }
        },
      ),
    );
  }

  Future<void> _showDeleteConfirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(
        title  : 'Delete Listing',
        message: 'This action cannot be undone.',
        confirm: 'Delete',
        danger : true,
      ),
    );
    if (ok == true) _deleteItem(docId);
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved':
      case 'active'  : return AppColors.successGreen;
      case 'rejected': return Colors.redAccent;
      default        : return AppColors.accentOrange;
    }
  }
}

// ── User Card ─────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String               uid;
  const _UserCard({required this.data, required this.uid});

  @override
  Widget build(BuildContext context) {
    final name           = data['name']             as String? ?? 'Unknown';
    final email          = data['email']            as String? ?? '';
    final phone          = data['phone']            as String? ?? '';
    final city           = data['city']             as String? ?? '';
    final role           = data['role']             as String? ?? 'buyer';
    final isSuspended    = data['isSuspended']      == true;
    final isDisabled     = data['isDisabled']       == true;
    final cnicStatus     = data['cnicStatus']       as String? ?? 'pending';
    final livenessStatus = data['livenessStatus']   as String? ?? 'notCompleted';
    final suspReason     = data['suspensionReason'] as String? ?? '';
    final rating         = (data['rating']          as num? ?? 0).toDouble();
    final listings       = data['listingsCount']    ?? 0;
    final deals          = data['completedDeals']   ?? 0;
    final createdAt      = data['createdAt']        as Timestamp?;
    final profileImage   = data['profileImage']     as String?;

    final isBlocked = isSuspended || isDisabled;

    return Container(
      decoration: BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(
          color: isBlocked
              ? Colors.redAccent.withOpacity(0.3)
              : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius         : 26,
              backgroundColor: AppColors.primaryBlueLight,
              backgroundImage:
              profileImage != null ? NetworkImage(profileImage) : null,
              child: profileImage == null
                  ? Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color     : AppColors.primaryBlue,
                    fontWeight: FontWeight.w800,
                    fontSize  : 18),
              )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    Text(name,
                        style: const TextStyle(
                            color     : AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize  : 14)),
                    _Badge(
                        label: role.toUpperCase(),
                        color: role == 'vendor'
                            ? Colors.purple
                            : role == 'admin'
                            ? Colors.deepPurple
                            : AppColors.primaryBlue,
                        small: true),
                    if (isSuspended)
                      _Badge(label: 'SUSPENDED', color: Colors.redAccent, small: true),
                    if (isDisabled)
                      _Badge(label: 'DISABLED', color: Colors.grey, small: true),
                  ]),
                  const SizedBox(height: 3),
                  if (email.isNotEmpty)
                    Text(email,
                        style: const TextStyle(
                            color  : AppColors.textSecondary,
                            fontSize: 12)),
                ],
              ),
            ),
          ]),
        ),

        // ── Details ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            if (phone.isNotEmpty)
              _InfoChip(icon: Icons.phone_rounded, label: phone),
            if (city.isNotEmpty)
              _InfoChip(icon: Icons.location_on_rounded, label: city),
            if (createdAt != null)
              _InfoChip(
                  icon : Icons.calendar_today_rounded,
                  label: _fmtDate(createdAt.toDate())),
            _InfoChip(
                icon : Icons.verified_user_rounded,
                label: 'CNIC: $cnicStatus',
                color: cnicStatus == 'verified'
                    ? AppColors.successGreen
                    : AppColors.accentOrange),
            _InfoChip(
                icon : Icons.face_rounded,
                label: 'Liveness: $livenessStatus',
                color: livenessStatus == 'completed'
                    ? AppColors.successGreen
                    : AppColors.accentOrange),
          ]),
        ),

        // ── Vendor stats ─────────────────────────────────────────────────────
        if (role == 'vendor')
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(children: [
              _StatPill(icon: Icons.storefront_rounded, label: '$listings Listings'),
              const SizedBox(width: 8),
              _StatPill(icon: Icons.handshake_rounded, label: '$deals Deals'),
              const SizedBox(width: 8),
              _StatPill(
                  icon : Icons.star_rounded,
                  label: rating.toStringAsFixed(1),
                  color: Colors.amber),
            ]),
          ),

        // ── Suspension reason ────────────────────────────────────────────────
        if (isSuspended && suspReason.isNotEmpty)
          _InfoBanner(
              icon   : Icons.warning_amber_rounded,
              text   : 'Reason: $suspReason',
              color  : Colors.redAccent,
              bgAlpha: 0.05),

        // ── Actions ──────────────────────────────────────────────────────────
        _CardFooter(
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            if (!isSuspended)
              _ActionBtn(
                  label: 'Suspend',
                  icon : Icons.block_rounded,
                  color: AppColors.accentOrange,
                  onTap: () => _showSuspendDialog(context))
            else
              _ActionBtn(
                  label: 'Unsuspend',
                  icon : Icons.check_circle_outline_rounded,
                  color: AppColors.successGreen,
                  onTap: () => _unsuspendUser(uid)),
            if (cnicStatus != 'verified')
              _ActionBtn(
                  label: 'Verify CNIC',
                  icon : Icons.verified_rounded,
                  color: AppColors.primaryBlue,
                  onTap: () => _verifyUserCNIC(uid)),
            if (role != 'admin')
              _ActionBtn(
                  label: role == 'vendor' ? 'Make Buyer' : 'Make Vendor',
                  icon : Icons.swap_horiz_rounded,
                  color: Colors.purple,
                  onTap: () => _changeUserRole(
                      uid, role == 'vendor' ? 'buyer' : 'vendor')),
          ]),
        ),
      ]),
    );
  }

  void _showSuspendDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => _InputDialog(
        title       : 'Suspend User',
        hint        : 'Reason for suspension…',
        confirmText : 'Suspend',
        confirmColor: AppColors.accentOrange,
        controller  : ctrl,
        onConfirm   : () {
          if (ctrl.text.trim().isNotEmpty) {
            _suspendUser(uid, ctrl.text.trim());
          }
        },
      ),
    );
  }

  static String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ── Dispute Card ──────────────────────────────────────────────────────────────

class _DisputeCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String               docId;
  const _DisputeCard({required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    final title        = data['title']          as String? ?? 'Dispute';
    final description  = data['description']    as String? ?? '';
    final status       = data['status']         as String? ?? 'open';
    final reportedBy   = data['reportedBy']     as String? ?? '';
    final reportedUser = data['reportedUserId'] as String? ?? '';
    final relatedItem  = data['relatedItemId']  as String? ?? '';
    final resolution   = data['resolution']     as String? ?? '';
    final adminNote    = data['adminNote']       as String? ?? '';
    final createdAt    = data['createdAt']       as Timestamp?;
    final isOpen       = status == 'open';

    final Color    statusColor;
    final IconData statusIcon;
    switch (status) {
      case 'resolved' :
        statusColor = AppColors.successGreen;
        statusIcon  = Icons.check_circle_rounded;
        break;
      case 'dismissed':
        statusColor = AppColors.textSecondary;
        statusIcon  = Icons.cancel_rounded;
        break;
      default:
        statusColor = Colors.redAccent;
        statusIcon  = Icons.warning_amber_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(
          color: isOpen
              ? Colors.redAccent.withOpacity(0.25)
              : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(statusIcon, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color     : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize  : 14)),
              ),
              _Badge(
                  label: status.toUpperCase(),
                  color: statusColor,
                  small: true),
            ]),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(description,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (reportedBy.isNotEmpty)
                _InfoChip(
                    icon : Icons.person_outline_rounded,
                    label: 'By: ${_truncate(reportedBy)}'),
              if (reportedUser.isNotEmpty)
                _InfoChip(
                    icon : Icons.report_outlined,
                    label: 'Against: ${_truncate(reportedUser)}'),
              if (relatedItem.isNotEmpty)
                _InfoChip(
                    icon : Icons.storefront_outlined,
                    label: 'Item: ${_truncate(relatedItem)}'),
              if (createdAt != null)
                _InfoChip(
                    icon : Icons.access_time_rounded,
                    label: _fmtDate(createdAt.toDate())),
            ]),
            if (resolution.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InfoBanner(
                  icon   : Icons.task_alt_rounded,
                  text   : 'Resolution: $resolution',
                  color  : AppColors.successGreen,
                  bgAlpha: 0.06),
            ],
            if (adminNote.isNotEmpty) ...[
              const SizedBox(height: 6),
              _InfoBanner(
                  icon   : Icons.sticky_note_2_outlined,
                  text   : 'Note: $adminNote',
                  color  : AppColors.primaryBlue,
                  bgAlpha: 0.06),
            ],
          ]),
        ),

        if (isOpen)
          _CardFooter(
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              _ActionBtn(
                  label: 'Resolve',
                  icon : Icons.task_alt_rounded,
                  color: AppColors.primaryBlue,
                  onTap: () => _showResolveDialog(context)),
              _ActionBtn(
                  label: 'Dismiss',
                  icon : Icons.cancel_outlined,
                  color: AppColors.textSecondary,
                  onTap: () => _showDismissDialog(context)),
              _ActionBtn(
                  label: 'Add Note',
                  icon : Icons.note_add_outlined,
                  color: Colors.teal,
                  onTap: () => _showNoteDialog(context)),
            ]),
          ),
      ]),
    );
  }

  void _showResolveDialog(BuildContext context) {
    final resCtrl    = TextEditingController();
    final actionCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Resolve Dispute',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color     : AppColors.textPrimary,
                fontSize  : 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: resCtrl,
            minLines  : 2,
            maxLines  : 4,
            style     : const TextStyle(
                color: AppColors.textPrimary, fontSize: 13),
            decoration: _inputDeco('Resolution details…'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: actionCtrl,
            style     : const TextStyle(
                color: AppColors.textPrimary, fontSize: 13),
            decoration: _inputDeco('Action taken (e.g., refund issued)…'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child    : const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () {
              _resolveDispute(
                  docId, resCtrl.text.trim(), actionCtrl.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Mark Resolved',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _showDismissDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => _InputDialog(
        title       : 'Dismiss Dispute',
        hint        : 'Reason for dismissal…',
        confirmText : 'Dismiss',
        confirmColor: AppColors.textSecondary,
        controller  : ctrl,
        onConfirm   : () => _dismissDispute(docId, ctrl.text.trim()),
      ),
    );
  }

  void _showNoteDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => _InputDialog(
        title       : 'Add Admin Note',
        hint        : 'Internal note…',
        confirmText : 'Save Note',
        confirmColor: Colors.teal,
        controller  : ctrl,
        onConfirm   : () => _addDisputeNote(docId, ctrl.text.trim()),
      ),
    );
  }

  static String _truncate(String s) =>
      s.length > 8 ? '${s.substring(0, 8)}…' : s;

  static String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';
}

// ── Log Tile ──────────────────────────────────────────────────────────────────

class _LogTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LogTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final action     = data['action']     as String?    ?? 'unknown';
    final ts         = data['timestamp']  as Timestamp?;
    final details    = data['details']    as Map<String, dynamic>? ?? {};
    final adminEmail = data['adminEmail'] as String?    ?? '';

    final (icon, color) = _iconAndColor(action);

    String timeStr = '';
    if (ts != null) {
      final dt = ts.toDate();
      timeStr =
      '${dt.day}/${dt.month}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      padding   : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border      : Border.all(color: Colors.grey.shade100),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color       : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(
                    color        : AppColors.textPrimary,
                    fontSize     : 11,
                    fontWeight   : FontWeight.w700,
                    letterSpacing: 0.4),
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  details.entries.map((e) => '${e.key}: ${e.value}').join(' • '),
                  style  : const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (adminEmail.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(adminEmail,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10)),
              ],
            ],
          ),
        ),
        Text(timeStr,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 10)),
      ]),
    );
  }

  (IconData, Color) _iconAndColor(String action) {
    switch (action) {
      case 'approve_item'   : return (Icons.check_circle_rounded,         AppColors.successGreen);
      case 'reject_item'    : return (Icons.cancel_rounded,               Colors.redAccent);
      case 'delete_item'    : return (Icons.delete_rounded,               Colors.red);
      case 'feature_item'   : return (Icons.star_rounded,                 Colors.amber);
      case 'unfeature_item' : return (Icons.star_border_rounded,          Colors.amber);
      case 'suspend_user'   : return (Icons.block_rounded,                AppColors.accentOrange);
      case 'unsuspend_user' : return (Icons.check_circle_outline_rounded, AppColors.successGreen);
      case 'change_role'    : return (Icons.swap_horiz_rounded,           Colors.purple);
      case 'verify_cnic'    : return (Icons.verified_rounded,             AppColors.primaryBlue);
      case 'resolve_dispute': return (Icons.gavel_rounded,                AppColors.primaryBlue);
      case 'dismiss_dispute': return (Icons.cancel_outlined,              AppColors.textSecondary);
      case 'add_note'       : return (Icons.note_add_outlined,            Colors.teal);
      default               : return (Icons.history_rounded,              AppColors.textSecondary);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final String   title, subtitle;
  final IconData icon;
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color       : AppColors.primaryBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: AppColors.primaryBlue, size: 20),
    ),
    const SizedBox(width: 12),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              color     : AppColors.textPrimary,
              fontSize  : 18,
              fontWeight: FontWeight.w800)),
      Text(subtitle,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 12)),
    ]),
  ]);
}

class _FilterChip extends StatelessWidget {
  final String       label;
  final bool         selected;
  final Color        color;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration  : const Duration(milliseconds: 150),
      padding   : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color       : selected
            ? color.withOpacity(0.1)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border      : Border.all(
            color: selected
                ? color.withOpacity(0.4)
                : Colors.grey.shade200),
      ),
      child: Text(label,
          style: TextStyle(
              color     : selected ? color : AppColors.textSecondary,
              fontSize  : 12,
              fontWeight: FontWeight.w600)),
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding   : const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color       : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border      : Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color     : color,
                fontSize  : 12,
                fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  final bool   small;
  const _Badge(
      {required this.label, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 10,
        vertical  : small ? 2 : 4),
    decoration: BoxDecoration(
      color       : color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: TextStyle(
            color        : color,
            fontSize     : small ? 9 : 11,
            fontWeight   : FontWeight.w700,
            letterSpacing: 0.3)),
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color?   color;
  const _InfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding   : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color       : c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: c),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color     : c,
                fontSize  : 10,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color?   color;
  const _StatPill({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primaryBlue;
    return Container(
      padding   : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color       : c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border      : Border.all(color: c.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color     : c,
                fontSize  : 11,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String   text;
  final Color    color;
  final double   bgAlpha;
  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.color,
    required this.bgAlpha,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin  : const EdgeInsets.fromLTRB(14, 0, 14, 10),
    padding : const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color       : color.withOpacity(bgAlpha),
      borderRadius: BorderRadius.circular(8),
      border      : Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text,
            style: TextStyle(color: color, fontSize: 11)),
      ),
    ]),
  );
}

class _CardFooter extends StatelessWidget {
  final Widget child;
  const _CardFooter({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding   : const EdgeInsets.fromLTRB(14, 8, 14, 12),
    decoration: BoxDecoration(
      color       : Colors.grey.shade50,
      borderRadius: const BorderRadius.only(
        bottomLeft : Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
    ),
    child: child,
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color       : AppColors.primaryBlueLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: AppColors.primaryBlue, size: 32),
      ),
      const SizedBox(height: 14),
      Text(message,
          style: const TextStyle(
              color     : AppColors.textSecondary,
              fontSize  : 14,
              fontWeight: FontWeight.w600)),
    ]),
  );
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding   : const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color       : Colors.red.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border      : Border.all(color: Colors.red.withOpacity(0.2)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12)),
          ),
        ]),
      ),
    ),
  );
}

class _ImgPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 80, height: 80,
    decoration: BoxDecoration(
      color       : AppColors.primaryBlueLight,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.image_not_supported_outlined,
        color: AppColors.primaryBlue, size: 24),
  );
}

// ── Dialogs ───────────────────────────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  final String title, message, confirm;
  final bool   danger;
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirm,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Text(title,
        style: const TextStyle(
            fontWeight: FontWeight.w800,
            color     : AppColors.textPrimary,
            fontSize  : 16)),
    content: Text(message,
        style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 13)),
    actions: [
      TextButton(
          onPressed: () => Navigator.pop(context, false),
          child    : const Text('Cancel')),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: danger ? Colors.redAccent : AppColors.primaryBlue,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: () => Navigator.pop(context, true),
        child: Text(confirm,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    ],
  );
}

class _InputDialog extends StatelessWidget {
  final String               title, hint, confirmText;
  final Color                confirmColor;
  final TextEditingController controller;
  final VoidCallback         onConfirm;
  const _InputDialog({
    required this.title,
    required this.hint,
    required this.confirmText,
    required this.confirmColor,
    required this.controller,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Text(title,
        style: const TextStyle(
            fontWeight: FontWeight.w800,
            color     : AppColors.textPrimary,
            fontSize  : 16)),
    content: TextField(
      controller: controller,
      minLines  : 2,
      maxLines  : 4,
      style     : const TextStyle(
          color: AppColors.textPrimary, fontSize: 13),
      decoration: _inputDeco(hint),
    ),
    actions: [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child    : const Text('Cancel')),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: confirmColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: () {
          onConfirm();
          Navigator.pop(context);
        },
        child: Text(confirmText,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    ],
  );
}

InputDecoration _inputDeco(String hint) => InputDecoration(
  hintText      : hint,
  hintStyle     : const TextStyle(color: AppColors.textSecondary, fontSize: 13),
  filled        : true,
  fillColor     : const Color(0xFFF5F7FB),
  contentPadding: const EdgeInsets.all(12),
  border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide  : BorderSide(color: Colors.grey.shade200)),
  enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide  : BorderSide(color: Colors.grey.shade200)),
  focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide  : const BorderSide(color: AppColors.primaryBlue)),
);