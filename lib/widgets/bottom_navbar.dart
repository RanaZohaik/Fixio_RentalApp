import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../utils/nav_controller.dart';

class FixioBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const FixioBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Glassmorphic background
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: 85,
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.85),
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow,
                    offset: const Offset(0, -3),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(
                      context: context,
                      index: 0,
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                      label: "Home"),
                  _navItem(
                      context: context,
                      index: 1,
                      icon: Icons.grid_view_outlined,
                      activeIcon: Icons.grid_view_rounded,
                      label: "Browse"),
                  const SizedBox(width: 65),
                  _navItem(
                      context: context,
                      index: 3,
                      icon: Icons.chat_bubble_outline,
                      activeIcon: Icons.chat_bubble_rounded,
                      label: "Chat"),
                  _navItem(
                      context: context,
                      index: 4,
                      icon: Icons.person_outline,
                      activeIcon: Icons.person_rounded,
                      label: "Profile"),
                ],
              ),
            ),
          ),
        ),

        // Floating CTA — verification-gated
        Positioned(
          top: -25,
          left: 0,
          right: 0,
          child: Center(
            child: _UploadButton(),
          ),
        ),
      ],
    );
  }

  Widget _navItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final bool active = index == currentIndex;

    return GestureDetector(
      // Use onTapDown for instant response — fires on finger touch,
      // not on finger lift, eliminating the ~150ms delay
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        if (!active) onTap(index);
      },
      behavior: HitTestBehavior.opaque, // makes entire area tappable
      child: SizedBox(
        width: 72,
        height: 85,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: active
                  ? BoxDecoration(
                color: AppColors.primaryBlueLight.withOpacity(0.45),
                borderRadius: BorderRadius.circular(14),
              )
                  : const BoxDecoration(),
              child: Icon(
                active ? activeIcon : icon,
                size: 24,
                color: active
                    ? AppColors.primaryBlueDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? AppColors.primaryBlueDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Upload button as separate StatefulWidget to avoid rebuild issues ──────────
class _UploadButton extends StatefulWidget {
  @override
  State<_UploadButton> createState() => _UploadButtonState();
}

class _UploadButtonState extends State<_UploadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.mediumImpact();
        NavController.handleUploadTap(context);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.91 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          height: 55,
          width: 55,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppColors.primaryBlue.withOpacity(0.9),
                AppColors.accentOrange.withOpacity(0.9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: AppColors.accentOrange.withOpacity(0.15),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.storefront_outlined,
              size: 26, color: Colors.white),
        ),
      ),
    );
  }
}