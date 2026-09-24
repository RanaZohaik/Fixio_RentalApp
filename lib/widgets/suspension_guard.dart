import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';

/// Wrap your entire authenticated widget tree with this.
/// It listens in real-time to the user's Firestore doc and immediately
/// signs them out + shows a blocked screen if [isSuspended] becomes true.
///
/// Usage in your router / home builder:
///   if (user != null) return SuspensionGuard(child: HomeScreen());
class SuspensionGuard extends StatelessWidget {
  final Widget child;
  const SuspensionGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return child;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        // While loading the first snapshot, just show the child
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return child;
        }

        final data        = snap.data?.data() as Map<String, dynamic>?;
        final isSuspended = data?['isSuspended'] == true;
        final isDisabled  = data?['isDisabled']  == true;

        if (isSuspended || isDisabled) {
          final reason = data?['suspensionReason'] as String? ?? '';

          // Sign out asynchronously so we don't call setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FirebaseAuth.instance.signOut();
          });

          return _BlockedScreen(
            isSuspended : isSuspended,
            reason      : reason,
          );
        }

        return child;
      },
    );
  }
}

// ── Blocked / Suspended Screen ────────────────────────────────────────────────
class _BlockedScreen extends StatelessWidget {
  final bool   isSuspended;
  final String reason;
  const _BlockedScreen({required this.isSuspended, required this.reason});

  @override
  Widget build(BuildContext context) {
    final isSupended = isSuspended;
    final title      = isSupended ? 'Account Suspended' : 'Account Disabled';
    final subtitle   = isSupended
        ? 'Your account has been suspended by an administrator.'
        : 'This account has been disabled.';
    final iconColor  = isSupended ? Colors.redAccent : Colors.orangeAccent;
    final icon       = isSupended ? Icons.block_rounded : Icons.do_not_disturb_on_rounded;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color        : iconColor.withOpacity(0.1),
                  shape        : BoxShape.circle,
                  border       : Border.all(color: iconColor.withOpacity(0.3), width: 2),
                ),
                child: Icon(icon, color: iconColor, size: 44),
              ),
              const SizedBox(height: 28),

              // Title
              Text(
                title,
                style: const TextStyle(
                  fontSize   : 22,
                  fontWeight : FontWeight.w800,
                  color      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),

              // Subtitle
              Text(
                subtitle,
                textAlign : TextAlign.center,
                style     : const TextStyle(
                  color    : AppColors.textSecondary,
                  fontSize : 14,
                  height   : 1.5,
                ),
              ),

              // Reason box (only when suspended and reason provided)
              if (isSuspended && reason.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  width   : double.infinity,
                  padding : const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color        : Colors.red.withOpacity(0.06),
                    borderRadius : BorderRadius.circular(14),
                    border       : Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: Colors.redAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          reason,
                          style: const TextStyle(
                            color    : Colors.redAccent,
                            fontSize : 13,
                            height   : 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Support note
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color        : Colors.grey.shade100,
                  borderRadius : BorderRadius.circular(12),
                ),
                child: const Text(
                  'If you believe this is a mistake, please contact support.',
                  textAlign : TextAlign.center,
                  style     : TextStyle(
                    color    : AppColors.textSecondary,
                    fontSize : 13,
                    height   : 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}