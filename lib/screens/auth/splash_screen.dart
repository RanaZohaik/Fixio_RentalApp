import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fixio/constants/app_colors.dart';
import 'package:fixio/routes/app_routes.dart';
import 'package:google_fonts/google_fonts.dart';

class FixioSplashScreen extends StatefulWidget {
  const FixioSplashScreen({Key? key}) : super(key: key);

  @override
  State<FixioSplashScreen> createState() => _FixioSplashScreenState();
}

class _FixioSplashScreenState extends State<FixioSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    Future.delayed(const Duration(seconds: 3), _checkAuthState);
  }

  // Only this method changed — added admin role check
  void _checkAuthState() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // Check if admin first (admins skip email verification)
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        final role = doc.data()?['role'] as String? ?? 'buyer';

        if (!mounted) return;

        if (role == 'admin') {
          Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
          return;
        }
      } catch (_) {
        // If Firestore fails, fall through to normal flow
      }

      // Regular user — check email verification
      await user.reload();
      if (user.emailVerified) {
        if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.home);
        return;
      }
    }

    if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background Animated Shapes
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                return CustomPaint(
                  painter: FloatingShapesPainter(_controller.value),
                );
              },
            ),
          ),

          // Center Logo + Tagline
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                FixioLogo(size: size.width * 0.25),

                const SizedBox(height: 20),

                // Tagline
                Text(
                  "Find it. Rent it. Own it.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.ubuntu(
                    fontSize: size.width * 0.05,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Enhanced White Circular Logo Widget
class FixioLogo extends StatelessWidget {
  final double size;
  final String imagePath;

  const FixioLogo({
    Key? key,
    this.size = 100,
    this.imagePath = 'assets/images/logo.png',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Colors.white, Colors.grey.shade200],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.6),
          width: 2,
        ),
      ),
      padding: EdgeInsets.all(size * 0.15),
      child: Image.asset(
        imagePath,
        fit: BoxFit.contain,
      ),
    );
  }
}

// Painter for animated floating circles + shapes — unchanged
class FloatingShapesPainter extends CustomPainter {
  final double animation;

  FloatingShapesPainter(this.animation);

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      AppColors.primaryBlueLight,
      AppColors.accentOrange.withOpacity(0.7),
      AppColors.infoTeal.withOpacity(0.7),
      AppColors.successGreen.withOpacity(0.7),
    ];

    final paint = Paint();
    final random = math.Random(42);

    for (int i = 0; i < 12; i++) {
      paint.color = colors[i % colors.length];
      double radius = 30 + random.nextDouble() * 40;
      double x = (size.width - 100) * math.sin(animation * (i + 1));
      double y = (size.height - 100) * math.cos(animation * (i + 1));

      canvas.drawCircle(
        Offset(size.width / 2 + x / 2, size.height / 2 + y / 2),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FloatingShapesPainter oldDelegate) => true;
}