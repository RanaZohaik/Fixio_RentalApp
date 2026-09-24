import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../constants/app_colors.dart';
import 'edit_item_screen.dart';

/// Shows all listings for the logged-in vendor with real-time status updates:
///   • PENDING  — submitted, waiting for admin approval
///   • APPROVED — live on the home screen
///   • REJECTED — rejected with reason shown prominently
class MyListingsTab extends StatefulWidget {
  const MyListingsTab({super.key});

  @override
  State<MyListingsTab> createState() => _MyListingsTabState();
}

class _MyListingsTabState extends State<MyListingsTab> {
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Stream: all listings for this vendor, newest first
  Stream<QuerySnapshot> get _stream => FirebaseFirestore.instance
      .collection('items')
      .where('vendorId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots();

  // ── Delete listing with confirmation ──────────────────────────────────────
  Future<void> _deleteItem(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.09),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Colors.red, size: 30),
              ),
              const SizedBox(height: 16),
              const Text(
                'Delete Listing?',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E)),
              ),
              const SizedBox(height: 8),
              const Text(
                'This action cannot be undone.\nThe listing will be permanently removed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: Color(0xFF6B7280), height: 1.6),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Delete',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('items').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue));
        }

        final docs = snapshot.data?.docs ?? [];

        // ── Empty state ────────────────────────────────────────────────────
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(Icons.inventory_2_outlined,
                      size: 44,
                      color: AppColors.primaryBlue.withOpacity(0.5)),
                ),
                const SizedBox(height: 20),
                const Text('No listings yet',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E))),
                const SizedBox(height: 8),
                Text('Tap + to add your first listing!',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              ],
            ),
          );
        }

        // ── Count by status ────────────────────────────────────────────────
        int approvedCount = 0, pendingCount = 0, rejectedCount = 0, rentCount = 0;
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final st   = data['status'] as String? ?? 'pending';
          if (st == 'approved' || st == 'active') approvedCount++;
          if (st == 'pending')  pendingCount++;
          if (st == 'rejected') rejectedCount++;
          if ((data['listingType'] as String? ?? '') == 'rent') rentCount++;
        }

        return Column(
          children: [
            // ── Summary header ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('My Listings',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w900,
                                  color: Color(0xFF1A1A2E))),
                          Text(
                            '${docs.length} listing${docs.length == 1 ? '' : 's'} total',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // Status summary chips row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      if (approvedCount > 0)
                        _SummaryChip(
                            label: '$approvedCount Approved',
                            color: const Color(0xFF22C55E),
                            bg: const Color(0xFFEFFEF4)),
                      if (approvedCount > 0) const SizedBox(width: 6),
                      if (pendingCount > 0)
                        _SummaryChip(
                            label: '$pendingCount Pending',
                            color: AppColors.accentOrange,
                            bg: AppColors.accentOrange.withOpacity(0.08)),
                      if (pendingCount > 0) const SizedBox(width: 6),
                      if (rejectedCount > 0)
                        _SummaryChip(
                            label: '$rejectedCount Rejected',
                            color: Colors.redAccent,
                            bg: Colors.redAccent.withOpacity(0.08)),
                      if (rejectedCount > 0) const SizedBox(width: 6),
                      if (rentCount > 0)
                        _SummaryChip(
                            label: '$rentCount Rent',
                            color: AppColors.primaryBlue,
                            bg: AppColors.primaryBlue.withOpacity(0.08)),
                    ]),
                  ),
                ],
              ),
            ),

            // ── Rejected items notice banner (if any) ─────────────────────
            if (rejectedCount > 0)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.cancel_outlined,
                      color: Colors.redAccent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontSize: 12, color: Colors.redAccent),
                        children: [
                          TextSpan(
                            text: '$rejectedCount listing${rejectedCount > 1 ? 's were' : ' was'} rejected by admin. ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(
                            text: 'See the rejection reason below and edit the listing to resubmit.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),

            // ── Listing cards ──────────────────────────────────────────────
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, i) {
                  final doc  = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  return _ListingCard(
                    data: data,
                    onEdit: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => EditItemScreen(
                                  docId: doc.id, data: data)));
                    },
                    onDelete: () {
                      HapticFeedback.lightImpact();
                      _deleteItem(doc.id);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Summary chip ──────────────────────────────────────────────────────────────
class _SummaryChip extends StatelessWidget {
  final String label;
  final Color  color, bg;
  const _SummaryChip(
      {required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration:
    BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Text(label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  );
}

// ── Listing card ──────────────────────────────────────────────────────────────
class _ListingCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onEdit, onDelete;
  const _ListingCard(
      {required this.data, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final status          = data['status']          as String? ?? 'pending';
    final title           = data['title']           as String? ?? 'Untitled';
    final price           = data['price'];
    final listingType     = data['listingType']     as String? ?? 'sell';
    final condition       = data['condition']       as String? ?? '';
    final location        = data['location']        as String? ??
        data['city']       as String? ?? '';
    final description     = data['description']     as String? ?? '';
    final rejectionReason = data['rejectionReason'] as String? ?? '';
    final featured        = data['featured'] == true;
    final category        = data['categoryName']    as String? ?? '';
    final imageUrl        =
        (data['images'] as List?)?.firstOrNull?.toString() ??
            data['image']  as String? ?? '';

    final bool   isRent    = listingType == 'rent';
    final Color  typeColor = isRent ? AppColors.accentOrange : AppColors.primaryBlue;
    final String typeLabel = isRent ? 'FOR RENT' : 'FOR SALE';

    final Color    statusColor = _statusColor(status);
    final IconData statusIcon  = _statusIcon(status);
    final String   statusLabel = status == 'approved'
        ? 'Approved'
        : status[0].toUpperCase() + status.substring(1);

    // Border highlight for non-approved states
    final Color borderColor = status == 'pending'
        ? AppColors.accentOrange.withOpacity(0.45)
        : status == 'rejected'
        ? Colors.redAccent.withOpacity(0.4)
        : Colors.transparent;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 1.4),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 4)),
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Top status bar for pending/rejected ────────────────────────
            if (status == 'pending' || status == 'rejected')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                color: statusColor.withOpacity(0.1),
                child: Row(children: [
                  Icon(statusIcon, size: 13, color: statusColor),
                  const SizedBox(width: 6),
                  Text(
                    status == 'pending'
                        ? 'Awaiting admin approval — not visible to buyers yet'
                        : 'Rejected by admin — see reason below',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: statusColor),
                  ),
                ]),
              ),

            // ── Image + details row ────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image with overlaid badges
                Stack(children: [
                  SizedBox(
                    width: 120, height: 136,
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (ctx, child, prog) {
                        if (prog == null) return child;
                        return _ImgFallback(loading: true);
                      },
                      errorBuilder: (_, __, ___) =>
                          _ImgFallback(loading: false),
                    )
                        : _ImgFallback(loading: false),
                  ),
                  // FOR RENT / FOR SALE label
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: typeColor,
                        borderRadius: BorderRadius.circular(7),
                        boxShadow: [
                          BoxShadow(
                              color: typeColor.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Text(typeLabel,
                          style: const TextStyle(
                              fontSize: 7.5, fontWeight: FontWeight.w900,
                              color: Colors.white, letterSpacing: 0.6)),
                    ),
                  ),
                  // Condition badge
                  if (condition.isNotEmpty)
                    Positioned(
                      bottom: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(condition,
                            style: const TextStyle(
                                fontSize: 8, fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  // Featured star
                  if (featured)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.amber, shape: BoxShape.circle),
                        child: const Icon(Icons.star_rounded,
                            size: 10, color: Colors.white),
                      ),
                    ),
                ]),

                // Text details
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1A1A2E),
                                      height: 1.3)),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(
                                label: statusLabel,
                                color: statusColor,
                                icon : statusIcon),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Price
                        if (price != null)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Rs.',
                                  style: TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.w700,
                                      color: const Color(0xFFFF6B35)
                                          .withOpacity(0.8))),
                              const SizedBox(width: 2),
                              Text('$price',
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w900,
                                      color: Color(0xFFFF6B35),
                                      letterSpacing: -0.5, height: 1.0)),
                              if (isRent) ...[
                                const SizedBox(width: 2),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 1),
                                  child: Text('/day',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFFFF6B35)
                                              .withOpacity(0.6))),
                                ),
                              ],
                            ],
                          ),
                        const SizedBox(height: 5),

                        // Category + location
                        if ([category, location]
                            .where((s) => s.isNotEmpty)
                            .isNotEmpty)
                          Text(
                            [
                              if (category.isNotEmpty) category,
                              if (location.isNotEmpty) location,
                            ].join('  •  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),

                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: Color(0xFF9CA3AF),
                                  height: 1.4)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── PENDING notice ─────────────────────────────────────────────
            if (status == 'pending')
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentOrange.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.accentOrange.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.pending_actions_rounded,
                      size: 16, color: AppColors.accentOrange),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Under Admin Review',
                          style: TextStyle(
                              color: AppColors.accentOrange,
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Your listing is being reviewed. It will appear on the home screen once approved.',
                          style: TextStyle(
                              color: AppColors.accentOrange,
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),

            // ── REJECTED notice with reason ────────────────────────────────
            if (status == 'rejected')
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.cancel_outlined,
                          size: 16, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      const Text(
                        'Listing Rejected by Admin',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ]),
                    if (rejectionReason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '📋 Reason: $rejectionReason',
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'You can edit the listing below and resubmit for review.',
                      style: TextStyle(
                          color: Colors.redAccent, fontSize: 11),
                    ),
                  ],
                ),
              ),

            // ── APPROVED notice ────────────────────────────────────────────
            if (status == 'approved' || status == 'active')
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.successGreen.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.successGreen.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 14, color: AppColors.successGreen),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Live on the home screen — buyers can see this listing.',
                      style: TextStyle(
                          color: AppColors.successGreen,
                          fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (featured) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded,
                              size: 10, color: Colors.amber),
                          SizedBox(width: 3),
                          Text('Featured',
                              style: TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.w700,
                                  color: Colors.amber)),
                        ],
                      ),
                    ),
                  ],
                ]),
              ),

            // ── Divider ────────────────────────────────────────────────────
            Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: const Color(0xFFF1F5F9)),

            // ── Action buttons ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onEdit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.primaryBlue.withOpacity(0.2)),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_outlined,
                                size: 14, color: AppColors.primaryBlue),
                            const SizedBox(width: 6),
                            Text(
                              status == 'rejected'
                                  ? 'Edit & Resubmit'
                                  : 'Edit Listing',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: AppColors.primaryBlue),
                            ),
                          ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.2)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 14, color: Colors.red),
                      SizedBox(width: 5),
                      Text('Delete',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: Colors.red)),
                    ]),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String   label;
  final Color    color;
  final IconData icon;
  const _StatusBadge(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 5, height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
    ]),
  );
}

// ── Color / icon helpers ──────────────────────────────────────────────────────
Color _statusColor(String s) {
  switch (s) {
    case 'active':
    case 'approved':
      return const Color(0xFF22C55E);
    case 'rejected':
      return Colors.redAccent;
    default: // pending
      return AppColors.accentOrange;
  }
}

IconData _statusIcon(String s) {
  switch (s) {
    case 'active':
    case 'approved':
      return Icons.check_circle_rounded;
    case 'rejected':
      return Icons.cancel_rounded;
    default:
      return Icons.pending_actions_rounded;
  }
}

// ── Image fallback ────────────────────────────────────────────────────────────
class _ImgFallback extends StatelessWidget {
  final bool loading;
  const _ImgFallback({required this.loading});

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF3F6FB),
    child: Center(
      child: loading
          ? const SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.primaryBlue))
          : Icon(Icons.image_outlined,
          size: 26, color: Colors.grey.withOpacity(0.4)),
    ),
  );
}