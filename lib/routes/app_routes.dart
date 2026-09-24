import 'package:flutter/material.dart';

// AUTH SCREENS
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_email_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/auth/signup_details_screen.dart';
import '../screens/auth/forgot_password_screen.dart';

// HOME MODULE
import '../screens/home/home_screen.dart';
import '../screens/home/notification_screen.dart';
import '../screens/home/profile_screen.dart';
import '../screens/vender/upload_item_screen.dart';
import '../screens/vender/vendor_dashboard_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';

// VERIFICATION
import '../screens/verification/verification_pending_screen.dart';
import '../screens/verification/liveness_check_screen.dart';

class AppRoutes {
  // ------------------- ROUTE NAMES -------------------
  static const String splash               = '/';
  static const String login                = '/login';
  static const String signupEmail          = '/signup-email';
  static const String verifyEmail          = '/verify-email';
  static const String signupDetails        = '/signup-details';
  static const String forgotPassword       = '/forgot-password';

  static const String home                 = '/home';
  static const String notifications        = '/notifications';
  static const String profile              = '/profile';
  static const String upload               = '/upload';
  static const String adminDashboard       = '/admin';
  static const String vendorDashboard      = '/vendor-dashboard';
  static const String verificationPending  = '/verification-pending';
  static const String livenessCheck = '/liveness-check';// ← ADD

  // ------------------- ROUTE GENERATOR -------------------
  static Route<dynamic> generateRoute(RouteSettings settings) {
    final args = settings.arguments as Map<String, dynamic>? ?? {};

    switch (settings.name) {
    // ---------------- AUTH ----------------
      case splash:
        return _page(const FixioSplashScreen());

      case login:
        return _page(const LoginScreen());

      case signupEmail:
        return _page(const SignupEmailScreen());

      case verifyEmail:
        return _page(
          VerifyEmailScreen(
            email: args['email'] ?? '',
          ),
        );

      case signupDetails:
        return _page(const SignupDetailsScreen());

      case forgotPassword:
        return _page(const ForgotPasswordScreen());

    // ---------------- HOME MODULE ----------------
      case home:
        return _page(const HomeScreen());

      case notifications:
        return _page(const NotificationsScreen());

      case profile:
        return _page(const ProfileScreen());

      case upload:
        return _page(const UploadItemScreen());

    // ---------------- DASHBOARDS ----------------
      case adminDashboard:
        return _page(const AdminDashboardScreen());

      case vendorDashboard:
        return _page(const VendorDashboardScreen());

    // ---------------- VERIFICATION ----------------
      case verificationPending:                              // ← ADD
        return _page(const VerificationPendingScreen());

      case livenessCheck:
        return _page(const LivenessCheckScreen());// ← ADD

    // ---------------- DEFAULT (404) ----------------
      default:
        return _errorRoute();
    }
  }

  static MaterialPageRoute _page(Widget screen) =>
      MaterialPageRoute(builder: (_) => screen);

  static Route<dynamic> _errorRoute() {
    return MaterialPageRoute(
      builder: (_) => const Scaffold(
        body: Center(
          child: Text(
            "404 — Screen Not Found",
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}