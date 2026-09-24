import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../constants/app_colors.dart';
import '../../models/category_model.dart';
import '../../services/category_service.dart';
import '../../services/chat_service.dart';
import '../../utils/icon_mapper.dart';
import '../../widgets/bottom_navbar.dart';
import '../../widgets/item_card_widget.dart';
import 'package:fixio/screens/vender/upload_item_screen.dart';
import '../home/profile_screen.dart';
import '../chat/chat_list_screen.dart';
import 'category_items_screen.dart';
import 'item_detail_screen.dart';
import '../home/browse_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final TextEditingController _searchCtrl    = TextEditingController();
  final CategoryService       _categoryService = CategoryService();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
          () => setState(
              () => _searchQuery = _searchCtrl.text.toLowerCase().trim()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return "Good Morning ☀️";
    if (h < 17) return "Good Afternoon 🌤️";
    return "Good Evening 🌙";
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text("Please Login")),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnap) {
        final username = userSnap.data?.data()?['name'] ?? 'User';

        return Scaffold(
          backgroundColor: AppColors.background,
          body: IndexedStack(
            // Map nav indices to stack children:
            // 0 → Home, 1 → Browse, 2 → (Upload — handled via push), 3 → Chat, 4 → Profile
            index: _stackIndex(_currentIndex),
            children: [
              _buildHomeContent(username),
              const BrowsePage(),
              _buildChatPage(),
              const ProfileScreen(),
            ],
          ),
          bottomNavigationBar: FixioBottomNav(
            currentIndex: _currentIndex,
            onTap: (index) {
              if (index == 2) {
                // Upload — push full-screen, don't switch IndexedStack
                _handleUploadTap(context);
              } else {
                setState(() => _currentIndex = index);
              }
            },
          ),
        );
      },
    );
  }

  /// Maps bottom-nav indices (0,1,2,3,4) to IndexedStack children (0,1,2,3).
  /// Index 2 (Upload) is handled by push, so 3→2 and 4→3.
  int _stackIndex(int navIndex) {
    if (navIndex >= 3) return navIndex - 1; // 3→2 (chat), 4→3 (profile)
    return navIndex;                         // 0→0 (home), 1→1 (browse)
  }

  /// Checks if the user is a verified vendor before allowing item upload.
  Future<void> _handleUploadTap(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc  = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    final role             = data?['role'] as String? ?? 'buyer';
    final verificationStatus = data?['verificationStatus'] as String? ?? 'unverified';

    if (!context.mounted) return;

    // Must be a verified vendor to list items
    if (role == 'vendor' && verificationStatus == 'verified') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UploadItemScreen()),
      );
    } else {
      _showUploadGateDialog(context, verificationStatus);
    }
  }

  void _showUploadGateDialog(BuildContext context, String verificationStatus) {
    final isPending = verificationStatus == 'pending';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isPending
                  ? Icons.hourglass_top_rounded
                  : Icons.verified_user_rounded,
              color: isPending ? Colors.orange : AppColors.primaryBlue,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                isPending
                    ? "Verification Pending"
                    : "Verification Required",
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Text(
          isPending
              ? "Your verification is under review. You'll be able to list items once approved."
              : "You need to verify your CNIC to become a vendor and list items.\n\nIt only takes a few minutes!",
          style: const TextStyle(
              color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Later")),
          if (!isPending)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                // Navigate to profile tab then open verification
                setState(() => _currentIndex = 4);
              },
              child: const Text("Verify Now",
                  style: TextStyle(
                      color:      Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  // ── Home Content ──────────────────────────────────────────────────────────
  Widget _buildHomeContent(String username) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ── Greeting ──────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Hi, $username",
                        style: const TextStyle(
                          fontSize:   20,
                          fontWeight: FontWeight.bold,
                          color:      AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _greeting(),
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  // Notification bell — goes to notifications screen
                  _NotificationBell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const _NotificationsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Search Bar ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color:        AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border:       Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(color: AppColors.shadow, blurRadius: 8)
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    const Icon(Icons.search, color: AppColors.textSecondary),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText:       "Search items or categories...",
                          hintStyle:      TextStyle(color: AppColors.textSecondary),
                          border:         InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: AppColors.textSecondary, size: 20),
                        onPressed: () => _searchCtrl.clear(),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Categories Title ──────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Categories",
                    style: TextStyle(
                      fontSize:   18,
                      fontWeight: FontWeight.bold,
                      color:      AppColors.textPrimary,
                    ),
                  ),
                  TextButton(
                    // Switch to Browse tab (index 1)
                    onPressed: () => setState(() => _currentIndex = 1),
                    child: const Text(
                      "See All",
                      style: TextStyle(
                          color:      AppColors.primaryBlue,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Categories Row ────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 100,
              child: StreamBuilder<List<CategoryModel>>(
                stream: _categoryService.getCategories(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primaryBlue),
                    );
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        "Error: ${snap.error}",
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final cats = snap.data ?? [];
                  if (cats.isEmpty) {
                    return const Center(
                      child: Text(
                        "No categories.\nAdd in Firestore with isActive: true",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding:          const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection:  Axis.horizontal,
                    itemCount:        cats.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (context, i) =>
                        _CategoryChip(cat: cats[i]),
                  );
                },
              ),
            ),
          ),

          // ── Fresh Listings Title ──────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Fresh Listings",
                    style: TextStyle(
                      fontSize:   18,
                      fontWeight: FontWeight.bold,
                      color:      AppColors.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width:  8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.successGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        "Live",
                        style: TextStyle(
                          fontSize:   12,
                          color:      AppColors.successGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Items Grid ────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('items')
                .where('status', whereIn: ['approved', 'active'])
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primaryBlue),
                    ),
                  ),
                );
              }
              if (snap.hasError) {
                return SliverToBoxAdapter(
                  child: _EmptyState(
                    icon:    Icons.error_outline,
                    color:   Colors.red,
                    message: snap.error.toString(),   // ← shows real error
                  ),
                );
              }
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const SliverToBoxAdapter(
                  child: _EmptyState(
                    icon:    Icons.inbox_outlined,
                    color:   AppColors.disabled,
                    message: "No items yet.\nTap + to list your first item!",
                  ),
                );
              }

              final all      = snap.data!.docs;
              final filtered = _searchQuery.isEmpty
                  ? all
                  : all.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final t =
                (d['title'] ?? '').toString().toLowerCase();
                final c = (d['categoryName'] ?? '')
                    .toString()
                    .toLowerCase();
                return t.contains(_searchQuery) ||
                    c.contains(_searchQuery);
              }).toList();

              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: _EmptyState(
                    icon:    Icons.search_off,
                    color:   AppColors.disabled,
                    message: 'No results for "$_searchQuery"',
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverGrid(
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:  2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.60,
                  ),
                  delegate: SliverChildBuilderDelegate(
                        (context, i) {
                      final data  = filtered[i].data()
                      as Map<String, dynamic>;
                      final docId = filtered[i].id;
                      return _ItemCardWithFavorite(
                          data: data, docId: docId);
                    },
                    childCount: filtered.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChatPage() => const ChatListScreen();
}

// ─────────────────────────────────────────────────────────────────────────────
// Item card with inline favorite toggle
// ─────────────────────────────────────────────────────────────────────────────
class _ItemCardWithFavorite extends StatelessWidget {
  final Map<String, dynamic> data;
  final String               docId;

  const _ItemCardWithFavorite({required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    final svc = ChatService();

    return Stack(
      children: [
        ItemCardWidget(data: data, docId: docId),
        Positioned(
          top:   8,
          right: 8,
          child: StreamBuilder<bool>(
            stream: svc.isFavoriteStream(docId),
            builder: (context, snap) {
              final isFav = snap.data ?? false;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  svc.toggleFavorite(docId, data);
                },
                child: Container(
                  width:  32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isFav
                        ? Colors.red.withOpacity(0.12)
                        : Colors.white.withOpacity(0.88),
                    shape:     BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withOpacity(0.12),
                        blurRadius: 6,
                        offset:     const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    isFav
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size:  16,
                    color: isFav ? Colors.red : Colors.grey[600],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Notification Bell ─────────────────────────────────────────────────────────
class _NotificationBell extends StatelessWidget {
  final VoidCallback onTap;
  const _NotificationBell({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Show unread badge from Firestore
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: uid.isNotEmpty
          ? FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .snapshots()
          : const Stream.empty(),
      builder: (context, snap) {
        final unreadCount = snap.data?.docs.length ?? 0;
        return Stack(
          children: [
            Container(
              width:  44,
              height: 44,
              decoration: BoxDecoration(
                color:        AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border:       Border.all(color: AppColors.border),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.notifications_outlined,
                    size: 22, color: AppColors.textPrimary),
                onPressed: onTap,
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top:   8,
                child: Container(
                  width:  8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Category Chip ─────────────────────────────────────────────────────────────
class _CategoryChip extends StatelessWidget {
  final CategoryModel cat;
  const _CategoryChip({required this.cat});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryItemsScreen(
              categoryId:   cat.id,
              categoryName: cat.name,
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width:  62,
            height: 62,
            decoration: BoxDecoration(
              color:        AppColors.primaryBlueLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.primaryBlue.withOpacity(0.2)),
            ),
            child: Icon(getIcon(cat.icon),
                color: AppColors.primaryBlue, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            cat.name,
            style: const TextStyle(
              fontSize:   11,
              fontWeight: FontWeight.w600,
              color:      AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   message;
  const _EmptyState(
      {required this.icon, required this.color, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 40),
      child: Column(
        children: [
          Icon(icon, size: 64, color: color),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color:  AppColors.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inline Notifications Screen (reused from profile_screen) ──────────────────
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
        title:     const Text("Notifications",
            style: TextStyle(fontWeight: FontWeight.w800)),
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
                child:
                CircularProgressIndicator(color: AppColors.primaryBlue));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("No notifications yet",
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 16)),
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

              // Mark as read on tap
              return GestureDetector(
                onTap: () {
                  if (!read) {
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('notifications')
                        .doc(docs[i].id)
                        .update({'read': true});
                  }
                },
                child: Container(
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
                                      fontSize: 12,
                                      color:    AppColors.textSecondary)),
                            ],
                          ],
                        ),
                      ),
                      if (!read)
                        Container(
                          width:  8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.primaryBlue,
                              shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}