import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../constants/app_colors.dart';
import 'my_listings_tab.dart';
import 'analytics_tab.dart';
import 'earnings_tab.dart';
import 'upload_item_screen.dart';

class VendorDashboardScreen extends StatefulWidget {
  const VendorDashboardScreen({super.key});

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _vendorName = '';
  String? _vendorImage;
  int _listingCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadVendorInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadVendorInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final itemSnap = await FirebaseFirestore.instance
        .collection('items')
        .where('vendorId', isEqualTo: uid)
        .get();
    if (mounted) {
      setState(() {
        _vendorName = doc.data()?['name'] ?? 'Vendor';
        _vendorImage = doc.data()?['profileImage'];
        _listingCount = itemSnap.docs.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: Column(
        children: [
          // ── Elegant Header ────────────────────────────────────────────
          _VendorDashboardHeader(
            vendorName: _vendorName,
            vendorImage: _vendorImage,
            listingCount: _listingCount,
            tabController: _tabController,
            onBack: () => Navigator.pop(context),
          ),

          // ── Tab Views ─────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                MyListingsTab(),
                AnalyticsTab(),
                EarningsTab(),
              ],
            ),
          ),
        ],
      ),

      // ── FAB ───────────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UploadItemScreen()),
        ),
        backgroundColor: AppColors.primaryBlue,
        elevation: 6,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'List Item',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }
}

// ── Vendor Dashboard Header ───────────────────────────────────────────────────
class _VendorDashboardHeader extends StatelessWidget {
  final String vendorName;
  final String? vendorImage;
  final int listingCount;
  final TabController tabController;
  final VoidCallback onBack;

  const _VendorDashboardHeader({
    required this.vendorName,
    required this.vendorImage,
    required this.listingCount,
    required this.tabController,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryBlue, Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Vendor Dashboard",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          "Welcome back, $vendorName",
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Vendor avatar
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundImage: vendorImage != null
                          ? NetworkImage(vendorImage!) as ImageProvider
                          : const AssetImage('assets/profile_placeholder.png'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Quick summary chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _SummaryPill(
                    icon: Icons.inventory_2_rounded,
                    label: "$listingCount Listings",
                    color: Colors.white.withOpacity(0.25),
                  ),
                  const SizedBox(width: 10),
                  _SummaryPill(
                    icon: Icons.verified_rounded,
                    label: "Verified Vendor",
                    color: Colors.greenAccent.withOpacity(0.25),
                    textColor: Colors.greenAccent,
                    iconColor: Colors.greenAccent,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Tab bar
            TabBar(
              controller: tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.list_alt_rounded, size: 16),
                      SizedBox(width: 6),
                      Text("Listings"),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bar_chart_rounded, size: 16),
                      SizedBox(width: 6),
                      Text("Analytics"),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.insights_rounded, size: 16),
                      SizedBox(width: 6),
                      Text("Earnings"),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? textColor;
  final Color? iconColor;

  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.color,
    this.textColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor ?? Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor ?? Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}