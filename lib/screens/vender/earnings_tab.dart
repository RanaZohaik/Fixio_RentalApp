import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../constants/app_colors.dart';

class EarningsTab extends StatelessWidget {
  const EarningsTab({super.key});

  String _fmt(double v) {
    if (v >= 1000000) return "${(v / 1000000).toStringAsFixed(1)}M";
    if (v >= 1000) return "${(v / 1000).toStringAsFixed(1)}K";
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('items').where('vendorId', isEqualTo: uid).snapshots(),
      builder: (context, itemSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('orders').where('vendorId', isEqualTo: uid).snapshots(),
          builder: (context, orderSnap) {
            if (!itemSnap.hasData) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue));
            }

            final itemDocs = itemSnap.data!.docs;
            final orderDocs = orderSnap.data?.docs ?? [];

            double salePortfolio = 0, rentPortfolio = 0;
            int saleCount = 0, rentCount = 0;
            for (final d in itemDocs) {
              final data = d.data() as Map<String, dynamic>;
              final price = (data['price'] as num?)?.toDouble() ?? 0;
              if (data['listingType'] == 'rent') {
                rentPortfolio += price; rentCount++;
              } else {
                salePortfolio += price; saleCount++;
              }
            }

            double saleRevenue = 0, rentRevenue = 0;
            for (final d in orderDocs) {
              final data = d.data() as Map<String, dynamic>;
              final price = (data['price'] as num?)?.toDouble() ?? 0;
              if (data['type'] == 'rent') rentRevenue += price;
              else saleRevenue += price;
            }

            final totalPortfolio = salePortfolio + rentPortfolio;
            final totalRevenue = saleRevenue + rentRevenue;
            final salePortPct = totalPortfolio == 0 ? 0.0 : salePortfolio / totalPortfolio * 100;
            final rentPortPct = totalPortfolio == 0 ? 0.0 : rentPortfolio / totalPortfolio * 100;

            final Map<String, double> monthRevSale = {};
            final Map<String, double> monthRevRent = {};
            for (final d in orderDocs) {
              final data = d.data() as Map<String, dynamic>;
              final ts = data['createdAt'];
              final price = (data['price'] as num?)?.toDouble() ?? 0;
              if (ts != null) {
                try {
                  final dt = (ts as dynamic).toDate() as DateTime;
                  final key = "${dt.year}-${dt.month.toString().padLeft(2, '0')}";
                  if (data['type'] == 'rent') {
                    monthRevRent[key] = (monthRevRent[key] ?? 0) + price;
                  } else {
                    monthRevSale[key] = (monthRevSale[key] ?? 0) + price;
                  }
                } catch (_) {}
              }
            }

            final now = DateTime.now();
            final months = List.generate(6, (i) {
              final d = DateTime(now.year, now.month - (5 - i), 1);
              return "${d.year}-${d.month.toString().padLeft(2, '0')}";
            });
            const mNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            final shortMonths = months.map((m) => mNames[int.parse(m.split('-')[1])]).toList();
            final saleBars = months.map((m) => monthRevSale[m] ?? 0.0).toList();
            final rentBars = months.map((m) => monthRevRent[m] ?? 0.0).toList();
            final maxRev = [...saleBars, ...rentBars, 1.0].reduce((a, b) => a > b ? a : b);

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Note about earnings model
                  _EarningsInfoBanner(),
                  const SizedBox(height: 20),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Earnings Overview", style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A2E), letterSpacing: -0.5,
                          )),
                          Text("Portfolio & deal value", style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text("Live", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryBlue)),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Hero Revenue Card
                  _HeroRevenueCard(
                    totalRevenue: totalRevenue,
                    totalPortfolio: totalPortfolio,
                    orderCount: orderDocs.length,
                    salePortPct: salePortPct,
                    rentPortPct: rentPortPct,
                    fmt: _fmt,
                  ),
                  const SizedBox(height: 20),

                  // KPI Row
                  Row(children: [
                    Expanded(child: _EarnKpi(
                      label: "Sale Value",
                      value: "Rs. ${_fmt(saleRevenue)}",
                      sub: "${orderDocs.where((d) => (d.data() as Map)['type'] != 'rent').length} deals",
                      color: AppColors.primaryBlue,
                      icon: Icons.storefront_rounded,
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _EarnKpi(
                      label: "Rent Value",
                      value: "Rs. ${_fmt(rentRevenue)}",
                      sub: "${orderDocs.where((d) => (d.data() as Map)['type'] == 'rent').length} deals",
                      color: AppColors.accentOrange,
                      icon: Icons.key_rounded,
                    )),
                  ]),
                  const SizedBox(height: 24),

                  // Monthly chart
                  _SectionLabel(title: "Monthly Activity", icon: Icons.show_chart_rounded),
                  const SizedBox(height: 14),
                  _RevenueChartCard(
                    months: shortMonths,
                    saleBars: saleBars,
                    rentBars: rentBars,
                    maxVal: maxRev,
                  ),
                  const SizedBox(height: 24),

                  // Portfolio breakdown
                  _SectionLabel(title: "Portfolio Breakdown", icon: Icons.account_balance_wallet_outlined),
                  const SizedBox(height: 14),
                  _PortfolioCard(
                    label: "Sale Portfolio",
                    amount: salePortfolio,
                    count: saleCount,
                    icon: Icons.storefront_rounded,
                    color: AppColors.primaryBlue,
                    bgColor: AppColors.primaryBlue.withOpacity(0.07),
                    percentage: salePortPct,
                    fmt: _fmt,
                  ),
                  const SizedBox(height: 12),
                  _PortfolioCard(
                    label: "Rent Portfolio",
                    amount: rentPortfolio,
                    count: rentCount,
                    icon: Icons.key_rounded,
                    color: AppColors.accentOrange,
                    bgColor: AppColors.accentOrange.withOpacity(0.07),
                    percentage: rentPortPct,
                    fmt: _fmt,
                  ),
                  const SizedBox(height: 24),

                  // Averages
                  _SectionLabel(title: "Averages", icon: Icons.calculate_outlined),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Column(children: [
                      _AvgRow(
                        label: "Avg. Sale Price",
                        value: saleCount > 0 ? "Rs. ${_fmt(salePortfolio / saleCount)}" : "—",
                        icon: Icons.trending_up_rounded,
                        color: AppColors.primaryBlue,
                        isFirst: true,
                      ),
                      _AvgRow(
                        label: "Avg. Rent Price",
                        value: rentCount > 0 ? "Rs. ${_fmt(rentPortfolio / rentCount)}" : "—",
                        icon: Icons.trending_up_rounded,
                        color: AppColors.accentOrange,
                      ),
                      _AvgRow(
                        label: "Avg. Deal Value",
                        value: orderDocs.isNotEmpty ? "Rs. ${_fmt(totalRevenue / orderDocs.length)}" : "—",
                        icon: Icons.receipt_long_outlined,
                        color: const Color(0xFF22C55E),
                        isLast: true,
                      ),
                    ]),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Earnings Info Banner ──────────────────────────────────────────────────────
class _EarningsInfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_rounded, color: Colors.amber, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "About Earnings",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1A1A2E)),
                ),
                const SizedBox(height: 3),
                Text(
                  "Fixio connects buyers & sellers directly. Payments are handled between parties — figures shown reflect your listing & deal values.",
                  style: TextStyle(fontSize: 11, color: Colors.grey[700], height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionLabel({required this.title, required this.icon});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 18, color: AppColors.primaryBlue),
    const SizedBox(width: 8),
    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E), letterSpacing: -0.3)),
  ]);
}

// ── Hero Revenue Card ─────────────────────────────────────────────────────────
class _HeroRevenueCard extends StatelessWidget {
  final double totalRevenue, totalPortfolio, salePortPct, rentPortPct;
  final int orderCount;
  final String Function(double) fmt;
  const _HeroRevenueCard({
    required this.totalRevenue,
    required this.totalPortfolio,
    required this.orderCount,
    required this.salePortPct,
    required this.rentPortPct,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF22C55E), Color(0xFF15803D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: const Color(0xFF22C55E).withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Total Deal Value", style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: Text("$orderCount deals", style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text("Rs.", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, height: 1.8)),
            const SizedBox(width: 4),
            Text(fmt(totalRevenue), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -2, height: 1.0)),
          ]),
          const SizedBox(height: 6),
          Text("Portfolio value: Rs. ${fmt(totalPortfolio)}", style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 6,
              child: Row(children: [
                Flexible(flex: salePortPct.round().clamp(0, 100), child: Container(color: Colors.white)),
                Flexible(flex: rentPortPct.round().clamp(0, 100), child: Container(color: Colors.white.withOpacity(0.35))),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _WLegend(label: "Sale ${salePortPct.toStringAsFixed(0)}%"),
            const SizedBox(width: 16),
            _WLegend(label: "Rent ${rentPortPct.toStringAsFixed(0)}%", dim: true),
          ]),
        ],
      ),
    );
  }
}

class _WLegend extends StatelessWidget {
  final String label;
  final bool dim;
  const _WLegend({required this.label, this.dim = false});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: dim ? Colors.white.withOpacity(0.4) : Colors.white, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: dim ? Colors.white.withOpacity(0.65) : Colors.white)),
  ]);
}

// ── Earn KPI ──────────────────────────────────────────────────────────────────
class _EarnKpi extends StatelessWidget {
  final String label, value, sub;
  final Color color;
  final IconData icon;
  const _EarnKpi({required this.label, required this.value, required this.sub, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(height: 10),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
      Text(sub, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
    ]),
  );
}

// ── Revenue Chart Card ────────────────────────────────────────────────────────
class _RevenueChartCard extends StatelessWidget {
  final List<String> months;
  final List<double> saleBars, rentBars;
  final double maxVal;
  const _RevenueChartCard({required this.months, required this.saleBars, required this.rentBars, required this.maxVal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _LegDot(color: AppColors.primaryBlue, label: "Sale"),
          const SizedBox(width: 14),
          _LegDot(color: AppColors.accentOrange, label: "Rent"),
        ]),
        const SizedBox(height: 18),
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(months.length, (i) {
              final sR = maxVal > 0 ? saleBars[i] / maxVal : 0.0;
              final rR = maxVal > 0 ? rentBars[i] / maxVal : 0.0;
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _RBar(ratio: sR, color: AppColors.primaryBlue),
                        const SizedBox(width: 3),
                        _RBar(ratio: rR, color: AppColors.accentOrange),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(months[i], style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }
}

class _RBar extends StatelessWidget {
  final double ratio;
  final Color color;
  const _RBar({required this.ratio, required this.color});
  @override
  Widget build(BuildContext context) {
    final h = (ratio * 110).clamp(4.0, 110.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      width: 10, height: h,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
    );
  }
}

class _LegDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 6),
    Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
  ]);
}

// ── Portfolio Card ────────────────────────────────────────────────────────────
class _PortfolioCard extends StatelessWidget {
  final String label;
  final double amount, percentage;
  final int count;
  final IconData icon;
  final Color color, bgColor;
  final String Function(double) fmt;
  const _PortfolioCard({
    required this.label, required this.amount, required this.count,
    required this.icon, required this.color, required this.bgColor,
    required this.percentage, required this.fmt,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Column(children: [
      Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
          Text("$count listing${count == 1 ? '' : 's'}", style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text("Rs. ${fmt(amount)}", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5)),
          Text("${percentage.toStringAsFixed(0)}% of total", style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
        ]),
      ]),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: percentage / 100,
          minHeight: 6,
          backgroundColor: bgColor,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    ]),
  );
}

// ── Average Row ───────────────────────────────────────────────────────────────
class _AvgRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool isFirst, isLast;
  const _AvgRow({required this.label, required this.value, required this.icon, required this.color, this.isFirst = false, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.09), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)))),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.3)),
        ]),
      ),
      if (!isLast) Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.withOpacity(0.1)),
    ]);
  }
}