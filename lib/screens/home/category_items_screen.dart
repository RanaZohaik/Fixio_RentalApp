import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_colors.dart';
import '../../services/chat_service.dart';
import '../../widgets/item_card_widget.dart';
import 'item_detail_screen.dart';

/// FIX: This screen now properly queries Firestore by categoryId
/// so tapping a category on the HomeScreen shows only matching items.
class CategoryItemsScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const CategoryItemsScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<CategoryItemsScreen> createState() => _CategoryItemsScreenState();
}

class _CategoryItemsScreenState extends State<CategoryItemsScreen> {
  bool _isGridView = true;
  String _sortBy = 'newest';

  Stream<QuerySnapshot> get _itemsStream {
    Query query = FirebaseFirestore.instance
        .collection('items')
        .where('categoryId', isEqualTo: widget.categoryId);

    // Only apply orderBy when no composite index issues
    // Firestore requires an index for multi-field queries; newest sort is safe alone
    return query.snapshots();
  }

  List<QueryDocumentSnapshot> _sortDocs(List<QueryDocumentSnapshot> docs) {
    final sorted = List.of(docs);
    switch (_sortBy) {
      case 'newest':
        sorted.sort((a, b) {
          final ta = ((a.data() as Map)['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final tb = ((b.data() as Map)['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });
        break;
      case 'oldest':
        sorted.sort((a, b) {
          final ta = ((a.data() as Map)['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final tb = ((b.data() as Map)['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return ta.compareTo(tb);
        });
        break;
      case 'priceLow':
        sorted.sort((a, b) {
          final pa = ((a.data() as Map)['price'] as num?)?.toDouble() ?? 0;
          final pb = ((b.data() as Map)['price'] as num?)?.toDouble() ?? 0;
          return pa.compareTo(pb);
        });
        break;
      case 'priceHigh':
        sorted.sort((a, b) {
          final pa = ((a.data() as Map)['price'] as num?)?.toDouble() ?? 0;
          final pb = ((b.data() as Map)['price'] as num?)?.toDouble() ?? 0;
          return pb.compareTo(pa);
        });
        break;
    }
    return sorted;
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SortSheet(
        current: _sortBy,
        onSelect: (val) => setState(() => _sortBy = val),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryBlue, Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.categoryName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            "Items in this category",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Sort button
                    _HeaderBtn(
                      icon: Icons.sort_rounded,
                      onTap: _showSortSheet,
                    ),
                    const SizedBox(width: 8),
                    // Toggle view
                    _HeaderBtn(
                      icon: _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                      onTap: () => setState(() => _isGridView = !_isGridView),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Items List/Grid ──────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _itemsStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryBlue),
                  );
                }
                if (snap.hasError) {
                  return _ErrorView(error: snap.error.toString());
                }

                final rawDocs = snap.data?.docs ?? [];
                final docs = _sortDocs(rawDocs);

                if (docs.isEmpty) {
                  return _EmptyView(categoryName: widget.categoryName);
                }

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: Text(
                          "${docs.length} item${docs.length != 1 ? 's' : ''} found",
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (_isGridView)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.60,
                          ),
                          delegate: SliverChildBuilderDelegate(
                                (_, i) {
                              final data = docs[i].data() as Map<String, dynamic>;
                              return _ItemWithFav(data: data, docId: docs[i].id);
                            },
                            childCount: docs.length,
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (_, i) {
                              final data = docs[i].data() as Map<String, dynamic>;
                              return _ListTile(data: data, docId: docs[i].id);
                            },
                            childCount: docs.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header Button ─────────────────────────────────────────────────────────────
class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ── Item with Favorite overlay ────────────────────────────────────────────────
class _ItemWithFav extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const _ItemWithFav({required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    final svc = ChatService();
    return Stack(
      children: [
        ItemCardWidget(data: data, docId: docId),
        Positioned(
          top: 8,
          right: 8,
          child: StreamBuilder<bool>(
            stream: svc.isFavoriteStream(docId),
            builder: (_, snap) {
              final isFav = snap.data ?? false;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  svc.toggleFavorite(docId, data);
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isFav ? Colors.red.withOpacity(0.12) : Colors.white.withOpacity(0.88),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 16,
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

// ── List Tile ─────────────────────────────────────────────────────────────────
class _ListTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const _ListTile({required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'Untitled';
    final price = data['price'];
    final location = data['location'] as String? ?? '';
    final isRent = data['listingType'] == 'rent';
    final rawImages = data['images'];
    final imageUrl = (rawImages is List && rawImages.isNotEmpty)
        ? rawImages.first.toString()
        : (data['image'] as String? ?? '');
    final tileColor = isRent ? AppColors.accentOrange : AppColors.primaryBlue;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ItemDetailScreen(data: data, docId: docId)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                bottomLeft: Radius.circular(18),
              ),
              child: SizedBox(
                width: 110,
                height: 110,
                child: imageUrl.isNotEmpty
                    ? Image.network(imageUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _Placeholder())
                    : _Placeholder(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: tileColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isRent ? 'For Rent' : 'For Sale',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: tileColor),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (price != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Rs. $price",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tileColor),
                      ),
                    ],
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 11, color: AppColors.textSecondary),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              location,
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey[300]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF0F2F5),
    child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 32),
  );
}

// ── Empty View ────────────────────────────────────────────────────────────────
class _EmptyView extends StatelessWidget {
  final String categoryName;
  const _EmptyView({required this.categoryName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.primaryBlueLight,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.inbox_outlined, size: 56, color: AppColors.primaryBlue),
            ),
            const SizedBox(height: 20),
            Text(
              "No items in $categoryName",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Be the first to list an item in this category!",
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error View ────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              "Something went wrong",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sort Sheet ────────────────────────────────────────────────────────────────
class _SortSheet extends StatelessWidget {
  final String current;
  final void Function(String) onSelect;
  const _SortSheet({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final options = [
      ('newest', 'Newest First', Icons.access_time_rounded),
      ('oldest', 'Oldest First', Icons.history_rounded),
      ('priceLow', 'Price: Low to High', Icons.arrow_upward_rounded),
      ('priceHigh', 'Price: High to Low', Icons.arrow_downward_rounded),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 18),
          const Text(
            "Sort By",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          ...options.map((opt) {
            final active = current == opt.$1;
            return GestureDetector(
              onTap: () {
                Navigator.pop(context);
                onSelect(opt.$1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: active ? AppColors.primaryBlue.withOpacity(0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active ? AppColors.primaryBlue.withOpacity(0.4) : Colors.grey.withOpacity(0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(opt.$3, size: 18, color: active ? AppColors.primaryBlue : AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Text(
                      opt.$2,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: active ? AppColors.primaryBlue : AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (active) const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.primaryBlue),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}