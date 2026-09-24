// lib/utils/nav_controller.dart

import 'package:fixio/screens/vender/my_listings_tab.dart';
import 'package:fixio/screens/vender/upload_item_screen.dart';
import 'package:flutter/material.dart';
import 'package:fixio/screens/vender/vendor_dashboard_screen.dart';
import '../services/verification_service.dart';
import '../screens/verification/verification_pending_screen.dart';

class NavController {
  // Cache the verification result so repeat taps don't re-query Firestore
  static bool? _cachedVerified;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  // ---------------------------------------------------------------------------
  // HANDLE UPLOAD CTA BUTTON TAP
  // Non-blocking — no loading dialog, instant response
  // ---------------------------------------------------------------------------
  static Future<void> handleUploadTap(BuildContext context) async {
    // Use cached result if fresh (avoids Firestore hit on every tap)
    final now = DateTime.now();
    if (_cachedVerified != null &&
        _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheDuration) {
      _navigate(context, _cachedVerified!);
      return;
    }

    // Check in background — show dialog only for the upload CTA, not nav items
    bool isVerified = false;
    try {
      isVerified = await VerificationService.isUserVerified();
      // Cache the result
      _cachedVerified = isVerified;
      _cacheTime      = now;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not check verification: $e"),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    _navigate(context, isVerified);
  }

  static void _navigate(BuildContext context, bool isVerified) {
    if (isVerified) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VendorDashboardScreen()),
      );
    } else {
      _showCnicVerificationDialog(context);
    }
  }

  /// Call this when verification status changes so the next tap re-checks
  static void invalidateCache() {
    _cachedVerified = null;
    _cacheTime      = null;
  }

  // ---------------------------------------------------------------------------
  // CNIC VERIFICATION POPUP
  // ---------------------------------------------------------------------------
  static void _showCnicVerificationDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (_, anim, __, child) {
        final curved =
        CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale:   curved,
          child:   FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (_, __, ___) => const _CnicDialog(),
    );
  }
}

// ---------------------------------------------------------------------------
// CNIC DIALOG WIDGET
// ---------------------------------------------------------------------------
class _CnicDialog extends StatelessWidget {
  const _CnicDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color:      Colors.black.withOpacity(0.18),
                  blurRadius: 40,
                  offset:     const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Gradient header ──
                Container(
                  width:   double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28)),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1565C0),
                        const Color(0xFFFF6D00).withOpacity(0.85),
                      ],
                      begin: Alignment.topLeft,
                      end:   Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:  Colors.white.withOpacity(0.2),
                          shape:  BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(0.45),
                              width: 1.5),
                        ),
                        child: const Icon(Icons.badge_outlined,
                            size: 38, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Verification Required',
                        style: TextStyle(
                          color:       Colors.white,
                          fontSize:    20,
                          fontWeight:  FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Body ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    children: [
                      const Text(
                        'To become a vendor on Fixio, you need to verify your identity with your CNIC first.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.5,
                          color:    Color(0xFF555555),
                          height:   1.55,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          _infoChip(Icons.lock_outline,     'Secure'),
                          const SizedBox(width: 10),
                          _infoChip(Icons.timer_outlined,   'Takes ~2 min'),
                          const SizedBox(width: 10),
                          _infoChip(Icons.verified_outlined, 'One-time only'),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Primary CTA
                      SizedBox(
                        width:  double.infinity,
                        height: 50,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF1565C0),
                                Color(0xFF1E88E5)
                              ],
                              begin: Alignment.topLeft,
                              end:   Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:      const Color(0xFF1565C0)
                                    .withOpacity(0.35),
                                blurRadius: 12,
                                offset:     const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor:     Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                  const VerificationPendingScreen(),
                                  //const VendorDashboardScreen(),


                                ),
                              );
                            },
                            icon:  const Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 20),
                            label: const Text(
                              'Verify CNIC Now',
                              style: TextStyle(
                                color:      Colors.white,
                                fontSize:   15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Maybe Later',
                          style: TextStyle(
                            color:      Color(0xFF999999),
                            fontSize:   13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color:        const Color(0xFFF0F4FF),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: const Color(0xFFD0DCFF)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF1565C0)),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize:   10.5,
                fontWeight: FontWeight.w600,
                color:      Color(0xFF444466),
              ),
            ),
          ],
        ),
      ),
    );
  }
}