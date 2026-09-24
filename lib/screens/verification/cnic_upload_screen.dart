import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/app_colors.dart';
import '../../routes/app_routes.dart';
import '../../services/verification_service.dart';

class CnicUploadScreen extends StatefulWidget {
  const CnicUploadScreen({super.key});

  @override
  State<CnicUploadScreen> createState() => _CnicUploadScreenState();
}

class _CnicUploadScreenState extends State<CnicUploadScreen> with SingleTickerProviderStateMixin {
  File? _frontImage;
  File? _backImage;
  bool _isUploading = false;
  late AnimationController _animCtrl;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String side, {bool useCamera = false}) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: useCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
    );
    if (pickedFile == null) return;
    setState(() {
      if (side == "front") _frontImage = File(pickedFile.path);
      if (side == "back") _backImage = File(pickedFile.path);
    });
  }

  void _showPickOptions(String side) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickOptionsSheet(
        onGallery: () { Navigator.pop(context); _pickImage(side); },
        onCamera: () { Navigator.pop(context); _pickImage(side, useCamera: true); },
      ),
    );
  }

  Future<void> _uploadImages() async {
    if (_frontImage == null || _backImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please upload both front and back images"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _isUploading = true);
    try {
      await VerificationService.uploadCnicImage(_frontImage!, side: "front");
      await VerificationService.uploadCnicImage(_backImage!, side: "back");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Documents submitted successfully! ✅"), backgroundColor: Colors.green),
        );
        Navigator.pushNamed(context, AppRoutes.livenessCheck);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bothUploaded = _frontImage != null && _backImage != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: Column(
        children: [
          // ── Header ───────────────────────────────────────────────────
          _CnicHeader(onBack: () => Navigator.pop(context)),

          // ── Scrollable Content ────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Guidance card
                  _GuidanceCard(),
                  const SizedBox(height: 28),

                  // Progress indicator
                  _UploadProgress(frontDone: _frontImage != null, backDone: _backImage != null),
                  const SizedBox(height: 28),

                  // Front side
                  _SideHeader(title: "Front Side", subtitle: "Your photo and name should be clear"),
                  const SizedBox(height: 12),
                  _CnicUploadSlot(
                    side: "front",
                    file: _frontImage,
                    icon: Icons.account_box_outlined,
                    onTap: () => _showPickOptions("front"),
                  ),

                  const SizedBox(height: 24),

                  // Back side
                  _SideHeader(title: "Back Side", subtitle: "Barcode and address must be visible"),
                  const SizedBox(height: 12),
                  _CnicUploadSlot(
                    side: "back",
                    file: _backImage,
                    icon: Icons.flip_to_back_outlined,
                    onTap: () => _showPickOptions("back"),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),

          // ── Submit Button ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, -4)),
              ],
            ),
            child: Column(
              children: [
                if (bothUploaded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          "Both sides uploaded — ready to submit!",
                          style: TextStyle(color: Colors.green[700], fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isUploading ? null : _uploadImages,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: bothUploaded ? Colors.green : AppColors.primaryBlue,
                      elevation: 4,
                      shadowColor: (bothUploaded ? Colors.green : AppColors.primaryBlue).withOpacity(0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: _isUploading
                        ? const SizedBox(
                      height: 24, width: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                        : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          bothUploaded ? Icons.check_circle_outline_rounded : Icons.upload_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          bothUploaded ? "Submit Documents" : "Upload Both Sides First",
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
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

// ── CNIC Header ───────────────────────────────────────────────────────────────
class _CnicHeader extends StatelessWidget {
  final VoidCallback onBack;
  const _CnicHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryBlue, Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 20),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                onPressed: onBack,
              ),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Upload Identity",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                    ),
                    Text(
                      "CNIC verification",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.credit_card_rounded, color: Colors.white, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Upload Progress ───────────────────────────────────────────────────────────
class _UploadProgress extends StatelessWidget {
  final bool frontDone, backDone;
  const _UploadProgress({required this.frontDone, required this.backDone});

  @override
  Widget build(BuildContext context) {
    final progress = (frontDone ? 1 : 0) + (backDone ? 1 : 0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Upload Progress",
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A2E)),
              ),
              Text(
                "$progress / 2 sides",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: progress == 2 ? Colors.green : AppColors.primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress / 2,
              minHeight: 8,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(progress == 2 ? Colors.green : AppColors.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Guidance Card ─────────────────────────────────────────────────────────────
class _GuidanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryBlue.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_rounded, color: AppColors.primaryBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Tips for quick approval",
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryBlue, fontSize: 13),
                ),
                const SizedBox(height: 6),
                ...[
                  "Make sure the card is physically present.",
                  "Avoid flash glare on the card surface.",
                  "Ensure all 4 corners are clearly visible.",
                ].map((tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 4, height: 4,
                        decoration: BoxDecoration(color: AppColors.primaryBlue.withOpacity(0.6), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tip, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Side Header ───────────────────────────────────────────────────────────────
class _SideHeader extends StatelessWidget {
  final String title, subtitle;
  const _SideHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }
}

// ── CNIC Upload Slot ──────────────────────────────────────────────────────────
class _CnicUploadSlot extends StatelessWidget {
  final String side;
  final File? file;
  final IconData icon;
  final VoidCallback onTap;

  const _CnicUploadSlot({
    required this.side,
    required this.file,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUploaded = file != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isUploaded ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isUploaded ? Colors.green : Colors.grey[300]!,
            width: isUploaded ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (isUploaded ? Colors.green : Colors.black).withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          image: isUploaded ? DecorationImage(image: FileImage(file!), fit: BoxFit.cover) : null,
        ),
        child: isUploaded
            ? Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.black.withOpacity(0.3),
              ),
            ),
            // Success badge
            Positioned(
              top: 12, right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text("Uploaded", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text("Tap to retake", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.primaryBlue.withOpacity(0.6)),
            ),
            const SizedBox(height: 14),
            Text(
              "Tap to upload $side side",
              style: TextStyle(
                color: AppColors.primaryBlue.withOpacity(0.8),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Camera or gallery",
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pick Options Sheet ────────────────────────────────────────────────────────
class _PickOptionsSheet extends StatelessWidget {
  final VoidCallback onGallery, onCamera;
  const _PickOptionsSheet({required this.onGallery, required this.onCamera});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          const Text("Choose Source", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SourceBtn(
                icon: Icons.photo_library_rounded,
                label: "Gallery",
                color: AppColors.primaryBlue,
                onTap: onGallery,
              ),
              _SourceBtn(
                icon: Icons.camera_alt_rounded,
                label: "Camera",
                color: AppColors.accentOrange,
                onTap: onCamera,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SourceBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}