import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fixio/constants/app_colors.dart';
import 'package:fixio/routes/app_routes.dart';
import 'package:fixio/services/firebase_auth_service.dart';

class SignupDetailsScreen extends StatefulWidget {
  const SignupDetailsScreen({Key? key}) : super(key: key);

  @override
  State<SignupDetailsScreen> createState() => _SignupDetailsScreenState();
}

class _SignupDetailsScreenState extends State<SignupDetailsScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _name     = TextEditingController();
  final TextEditingController _phone    = TextEditingController();
  final TextEditingController _city     = TextEditingController();
  final TextEditingController _password = TextEditingController();

  DateTime? _dob;
  File?     _profileImage;
  bool      _loading     = false;
  bool      _obscurePass = true;
  String?   _error;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _selectDOB() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.primaryBlue,
            surface: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImageSourceSheet(),
    );
    if (source == null) return;
    final pickedFile = await ImagePicker().pickImage(
      source:       source,
      imageQuality: 70,
      maxWidth:     800,
      maxHeight:    800,
    );
    if (pickedFile != null) {
      setState(() => _profileImage = File(pickedFile.path));
    }
  }

  Future<void> _completeSignup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      setState(() => _error = "Please select your date of birth");
      return;
    }
    setState(() {
      _loading = true;
      _error   = null;
    });

    // Pass the profile image File directly — FirebaseAuthService uploads it
    // to Firebase Storage and stores the download URL in Firestore.
    final result = await FirebaseAuthService().finalizeAccount(
      password:         _password.text.trim(),
      name:             _name.text.trim(),
      phone:            _phone.text.trim(),
      city:             _city.text.trim(),
      dob:              _dob!,
      profileImageFile: _profileImage, // ← uploaded to Storage if not null
    );

    if (!mounted) return;
    if (result == null) {
      Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.home, (route) => false);
    } else {
      setState(() {
        _loading = false;
        _error   = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            children: [
              // ── Top Bar ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    FixioBackButton(onTap: () => Navigator.pop(context)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlueLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "Step 3 of 3",
                        style: TextStyle(
                          fontSize:   12,
                          fontWeight: FontWeight.w600,
                          color:      AppColors.primaryBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),

                        Text(
                          "Finalize profile",
                          style: TextStyle(
                            fontSize:      28,
                            fontWeight:    FontWeight.bold,
                            color:         AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Almost there! Fill in your details.",
                          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                        ),

                        const SizedBox(height: 28),

                        // ── Avatar Picker ────────────────────────────
                        Center(
                          child: GestureDetector(
                            onTap: _loading ? null : _pickImage,
                            child: Stack(
                              children: [
                                Container(
                                  width:  96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primaryBlueLight,
                                    border: Border.all(color: AppColors.border, width: 2),
                                  ),
                                  child: _profileImage != null
                                      ? ClipOval(
                                    child: Image.file(
                                      _profileImage!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                      : Icon(
                                    Icons.person_outline_rounded,
                                    color: AppColors.primaryBlue,
                                    size: 44,
                                  ),
                                ),
                                Positioned(
                                  bottom: 2,
                                  right:  2,
                                  child: Container(
                                    width:  28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color:  AppColors.primaryBlue,
                                      shape:  BoxShape.circle,
                                      border: Border.all(color: AppColors.background, width: 2),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt_rounded,
                                      color: Colors.white,
                                      size:  13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text(
                            _profileImage == null ? "Tap to add photo" : "Tap to change photo",
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── Form Fields ──────────────────────────────
                        _FieldLabel("Full name"),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _name,
                          hint:       "Ahmad Ali",
                          icon:       Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 16),

                        _FieldLabel("Phone number"),
                        const SizedBox(height: 8),
                        _buildField(
                          controller:    _phone,
                          hint:          "03XX-XXXXXXX",
                          icon:          Icons.phone_outlined,
                          inputType:     TextInputType.phone,
                          extraValidator: (v) {
                            if (v != null && v.length < 10) {
                              return "Enter a valid phone number";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        _FieldLabel("City"),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _city,
                          hint:       "Lahore",
                          icon:       Icons.location_city_outlined,
                        ),
                        const SizedBox(height: 16),

                        _FieldLabel("Create password"),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _password,
                          hint:       "Min. 6 characters",
                          icon:       Icons.lock_outline_rounded,
                          isPass:     true,
                        ),
                        const SizedBox(height: 16),

                        // ── DOB Picker ───────────────────────────────
                        _FieldLabel("Date of birth"),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _loading ? null : _selectDOB,
                          child: Container(
                            height: 54,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color:        AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border:       Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.cake_outlined,
                                    color: AppColors.textSecondary, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _dob == null
                                        ? "Select date"
                                        : "${_dob!.day}/${_dob!.month}/${_dob!.year}",
                                    style: TextStyle(
                                      color:    _dob == null
                                          ? AppColors.textSecondary
                                          : AppColors.textPrimary,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Icon(Icons.calendar_today_rounded,
                                    color: AppColors.textSecondary, size: 16),
                              ],
                            ),
                          ),
                        ),

                        // ── Error ────────────────────────────────────
                        if (_error != null) ...[
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color:        Colors.redAccent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border:       Border.all(color: Colors.redAccent.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: Colors.redAccent, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 32),

                        // ── Submit Button ────────────────────────────
                        SizedBox(
                          width:  double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _completeSignup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:         AppColors.primaryBlue,
                              foregroundColor:         Colors.white,
                              disabledBackgroundColor: AppColors.primaryBlue.withOpacity(0.5),
                              elevation:               0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _loading
                                ? const SizedBox(
                              width:  22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color:       Colors.white,
                              ),
                            )
                                : const Text(
                              "Save & Continue",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String                hint,
    required IconData              icon,
    bool                           isPass     = false,
    TextInputType?                 inputType,
    String? Function(String?)?     extraValidator,
  }) {
    return TextFormField(
      controller:   controller,
      obscureText:  isPass ? _obscurePass : false,
      keyboardType: inputType ?? TextInputType.text,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return "This field is required";
        if (isPass && v.length < 6) return "Password must be at least 6 characters";
        return extraValidator?.call(v);
      },
      decoration: InputDecoration(
        hintText:    hint,
        hintStyle:   TextStyle(color: AppColors.textSecondary, fontSize: 14),
        prefixIcon:  Icon(icon, color: AppColors.textSecondary, size: 20),
        suffixIcon: isPass
            ? IconButton(
          icon: Icon(
            _obscurePass
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AppColors.textSecondary,
            size:  20,
          ),
          onPressed: () => setState(() => _obscurePass = !_obscurePass),
        )
            : null,
        filled:    true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   const BorderSide(color: Colors.redAccent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        errorStyle:     const TextStyle(color: Colors.redAccent, fontSize: 12),
      ),
    );
  }
}

// ── Field Label ───────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize:   13,
        fontWeight: FontWeight.w600,
        color:      AppColors.textPrimary,
      ),
    );
  }
}

// ── Image Source Bottom Sheet ─────────────────────────────────────────────────
class _ImageSourceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border:       Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width:  36,
            height: 4,
            decoration: BoxDecoration(
              color:        AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Select photo",
            style: TextStyle(
              color:      AppColors.textPrimary,
              fontSize:   16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SourceOption(
                icon:  Icons.photo_library_rounded,
                label: "Gallery",
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              _SourceOption(
                icon:  Icons.camera_alt_rounded,
                label: "Camera",
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;

  const _SourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width:  72,
            height: 72,
            decoration: BoxDecoration(
              color:        AppColors.primaryBlueLight,
              borderRadius: BorderRadius.circular(18),
              border:       Border.all(color: AppColors.primaryBlue.withOpacity(0.2)),
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color:      AppColors.textPrimary,
              fontSize:   13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared back button ────────────────────────────────────────────────────────
class FixioBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const FixioBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width:  40,
        height: 40,
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: AppColors.border),
        ),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: AppColors.textPrimary,
          size:  18,
        ),
      ),
    );
  }
}