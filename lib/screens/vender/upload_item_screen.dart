import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../constants/app_colors.dart';
import '../../utils/icon_mapper.dart';

class UploadItemScreen extends StatefulWidget {
  const UploadItemScreen({super.key});

  @override
  State<UploadItemScreen> createState() => _UploadItemScreenState();
}

class _UploadItemScreenState extends State<UploadItemScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _titleCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _priceCtrl    = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _phoneCtrl    = TextEditingController();

  final List<File> _images    = [];
  final int        _maxImages = 3;

  bool    _isUploading    = false;
  double  _uploadProgress = 0.0;
  String? _selectedCategory;
  String? _selectedCondition;
  String  _listingType  = 'sell';
  String  _rentDuration = 'day';

  final ImagePicker _picker = ImagePicker();

  final List<Map<String, dynamic>> _conditions = [
    {'value': 'New',       'icon': Icons.fiber_new_outlined},
    {'value': 'Like New',  'icon': Icons.star_outline_rounded},
    {'value': 'Good',      'icon': Icons.thumb_up_outlined},
    {'value': 'Fair',      'icon': Icons.thumbs_up_down_outlined},
    {'value': 'For Parts', 'icon': Icons.build_outlined},
  ];

  final List<Map<String, dynamic>> _categories = [
    {'id': 'electronics', 'name': 'Electronics', 'icon': 'electronics'},
    {'id': 'vehicles',    'name': 'Vehicles',    'icon': 'car'},
    {'id': 'tools',       'name': 'Tools',       'icon': 'tools'},
    {'id': 'furniture',   'name': 'Furniture',   'icon': 'chair'},
    {'id': 'appliances',  'name': 'Appliances',  'icon': 'appliances'},
    {'id': 'mobiles',     'name': 'Mobiles',     'icon': 'phone'},
    {'id': 'fashion',     'name': 'Fashion',     'icon': 'fashion'},
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _locationCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Pick image ────────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    if (_images.length >= _maxImages) {
      _showSnack('Maximum $_maxImages photos allowed');
      return;
    }
    final XFile? picked = await _picker.pickImage(
      source       : ImageSource.gallery,
      imageQuality : 80,
    );
    if (picked == null) return;
    setState(() => _images.add(File(picked.path)));
  }

  void _removeImage(int index) => setState(() => _images.removeAt(index));

  // ── Upload ────────────────────────────────────────────────────────────────
  Future<void> _uploadItem() async {
    if (!_formKey.currentState!.validate()) return;
    if (_images.isEmpty) {
      _showSnack('Please add at least one photo');
      return;
    }
    if (_selectedCategory == null) {
      _showSnack('Please select a category');
      return;
    }
    if (_selectedCondition == null) {
      _showSnack('Please select item condition');
      return;
    }

    setState(() {
      _isUploading    = true;
      _uploadProgress = 0.0;
    });

    try {
      final uid   = FirebaseAuth.instance.currentUser!.uid;
      final total = _images.length;
      final List<String> imageUrls = [];

      // Upload images
      for (int i = 0; i < total; i++) {
        final fileName   = '${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('items/$uid/$fileName');

        final uploadTask = storageRef.putFile(
          _images[i],
          SettableMetadata(contentType: 'image/jpeg'),
        );

        uploadTask.snapshotEvents.listen((TaskSnapshot snap) {
          final progress = snap.bytesTransferred / snap.totalBytes;
          setState(() => _uploadProgress = (i + progress) / total);
        });

        await uploadTask.whenComplete(() {});
        imageUrls.add(await storageRef.getDownloadURL());
      }

      // Fetch seller name
      String sellerName = 'Unknown Seller';
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        sellerName = userDoc.data()?['name'] as String? ?? 'Unknown Seller';
      } catch (_) {}

      final categoryMap  = _categories.firstWhere((c) => c['id'] == _selectedCategory);
      final categoryName = categoryMap['name'] as String;

      // Save to Firestore — always starts as 'pending'
      await FirebaseFirestore.instance.collection('items').add({
        'title'        : _titleCtrl.text.trim(),
        'description'  : _descCtrl.text.trim(),
        'price'        : double.parse(_priceCtrl.text.trim()),
        'image'        : imageUrls.first,
        'images'       : imageUrls,
        'vendorId'     : uid,
        'categoryId'   : _selectedCategory,
        'categoryName' : categoryName,
        'category'     : categoryName,
        'listingType'  : _listingType,
        'rentDuration' : _listingType == 'rent' ? _rentDuration : null,
        'condition'    : _selectedCondition,
        'location'     : _locationCtrl.text.trim(),
        'city'         : _locationCtrl.text.trim(),
        'sellerName'   : sellerName,
        'phone'        : _phoneCtrl.text.trim(),
        // Status always starts as pending — admin must approve before going live
        'status'           : 'pending',
        'featured'         : false,
        'verifiedVendor'   : true,
        'rejectionReason'  : '',
        'createdAt'        : FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSuccessSheet();
        _clearForm();
      }
    } on FirebaseException catch (e) {
      _showSnack('Firebase error: ${e.message}');
    } catch (e) {
      _showSnack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Success bottom sheet ──────────────────────────────────────────────────
  void _showSuccessSheet() {
    showModalBottomSheet(
      context       : context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.successGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.successGreen, size: 40),
          ),
          const SizedBox(height: 20),
          const Text(
            'Listing Submitted!',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your listing is now under admin review.\nYou\'ll see it in "My Listings" with a Pending badge. Once approved, it will go live on the home screen.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 24),
          // Status steps visual
          _StatusStep(
            icon  : Icons.upload_rounded,
            label : 'Submitted',
            done  : true,
            active: false,
          ),
          _StatusStep(
            icon  : Icons.admin_panel_settings_outlined,
            label : 'Admin Review (pending)',
            done  : false,
            active: true,
          ),
          _StatusStep(
            icon  : Icons.storefront_rounded,
            label : 'Goes Live',
            done  : false,
            active: false,
            isLast: true,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed : () => Navigator.pop(context),
              style     : ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding    : const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Got it',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    setState(() {
      _images.clear();
      _selectedCategory  = null;
      _selectedCondition = null;
      _uploadProgress    = 0.0;
      _listingType       = 'sell';
      _rentDuration      = 'day';
    });
    _titleCtrl.clear();
    _descCtrl.clear();
    _priceCtrl.clear();
    _locationCtrl.clear();
    _phoneCtrl.clear();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content  : Text(msg),
        behavior : SnackBarBehavior.floating,
        shape    : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'List an Item',
          style: TextStyle(
              fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        backgroundColor : AppColors.primaryBlue,
        iconTheme       : const IconThemeData(color: Colors.white),
        elevation       : 0,
        bottom          : PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.primaryBlue,
                AppColors.accentOrange.withOpacity(0.7),
              ]),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Pending-review notice banner ──────────────────────────────
            Container(
              width   : double.infinity,
              padding : const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              color   : AppColors.accentOrange.withOpacity(0.12),
              child   : Row(children: [
                const Icon(Icons.info_outline,
                    color: AppColors.accentOrange, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Listings are reviewed by admin before going live.',
                    style: TextStyle(
                        color      : AppColors.accentOrange,
                        fontSize   : 12,
                        fontWeight : FontWeight.w600),
                  ),
                ),
              ]),
            ),

            // ── Hero Banner ───────────────────────────────────────────────
            Container(
              width   : double.infinity,
              padding : const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                color        : AppColors.primaryBlue,
                borderRadius : BorderRadius.vertical(
                    bottom: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'What are you listing?',
                    style: TextStyle(
                        color      : Colors.white,
                        fontSize   : 20,
                        fontWeight : FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add photos, details and submit for review',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.75), fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // Sell / Rent toggle
                  Container(
                    padding     : const EdgeInsets.all(4),
                    decoration  : BoxDecoration(
                      color        : Colors.white.withOpacity(0.15),
                      borderRadius : BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      _toggleBtn(label: '🏷️  Sell', value: 'sell'),
                      _toggleBtn(label: '🔑  Rent', value: 'rent'),
                    ]),
                  ),
                ],
              ),
            ),

            Padding(
              padding : const EdgeInsets.all(20),
              child   : Form(
                key  : _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Photos ────────────────────────────────────────────
                    _sectionLabel('Photos', Icons.photo_library_outlined),
                    const SizedBox(height: 4),
                    Text(
                      'Add up to $_maxImages photos • First photo is the cover',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 120,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ..._images.asMap().entries
                              .map((e) => _imageThumb(e.value, e.key)),
                          if (_images.length < _maxImages) _addPhotoButton(),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Category ──────────────────────────────────────────
                    _sectionLabel('Category', Icons.grid_view_rounded),
                    const SizedBox(height: 12),
                    _buildCategoryChips(),

                    const SizedBox(height: 28),

                    // ── Condition ─────────────────────────────────────────
                    _sectionLabel('Condition', Icons.auto_awesome_outlined),
                    const SizedBox(height: 12),
                    _buildConditionChips(),

                    const SizedBox(height: 28),

                    // ── Item Details ──────────────────────────────────────
                    _sectionLabel('Item Details', Icons.edit_note_rounded),
                    const SizedBox(height: 12),

                    _buildField(
                      controller : _titleCtrl,
                      label      : 'Item Title',
                      hint       : 'e.g. Honda Civic 2020',
                      icon       : Icons.title,
                      validator  : (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a title' : null,
                    ),
                    const SizedBox(height: 14),

                    _buildField(
                      controller : _descCtrl,
                      label      : 'Description',
                      hint       : 'Describe condition, age, features...',
                      icon       : Icons.description_outlined,
                      maxLines   : 4,
                      validator  : (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a description' : null,
                    ),
                    const SizedBox(height: 14),

                    _buildField(
                      controller : _priceCtrl,
                      label      : _priceLabel(),
                      hint       : 'e.g. 15000',
                      icon       : Icons.payments_outlined,
                      inputType  : TextInputType.number,
                      validator  : (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'Enter a price';
                        if (double.tryParse(v.trim()) == null)
                          return 'Enter a valid number';
                        return null;
                      },
                    ),

                    const SizedBox(height: 28),

                    // ── Rental Duration ───────────────────────────────────
                    if (_listingType == 'rent') ...[
                      _sectionLabel(
                          'Rental Duration', Icons.schedule_outlined),
                      const SizedBox(height: 4),
                      const Text(
                        'How do you want to charge renters?',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      _buildRentalDurationSelector(),
                      const SizedBox(height: 28),
                    ],

                    // ── Contact & Location ────────────────────────────────
                    _sectionLabel(
                        'Contact & Location', Icons.person_pin_outlined),
                    const SizedBox(height: 4),
                    const Text(
                      'Buyers will see this on the item detail screen',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 12),

                    _buildField(
                      controller : _locationCtrl,
                      label      : 'Location',
                      hint       : 'e.g. Karachi, Lahore',
                      icon       : Icons.location_on_outlined,
                      validator  : (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a location' : null,
                    ),
                    const SizedBox(height: 14),

                    _buildField(
                      controller : _phoneCtrl,
                      label      : 'Phone Number',
                      hint       : 'e.g. 03001234567',
                      icon       : Icons.phone_outlined,
                      inputType  : TextInputType.phone,
                      validator  : (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'Enter your phone number';
                        if (v.trim().length < 10)
                          return 'Enter a valid phone number';
                        return null;
                      },
                    ),

                    const SizedBox(height: 30),

                    // ── Upload Progress ───────────────────────────────────
                    if (_isUploading) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Uploading ${_images.length} '
                                'photo${_images.length > 1 ? "s" : ""}...',
                            style: const TextStyle(
                                color      : AppColors.textSecondary,
                                fontSize   : 13,
                                fontWeight : FontWeight.w500),
                          ),
                          Text(
                            '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                                color      : AppColors.primaryBlue,
                                fontSize   : 13,
                                fontWeight : FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value           : _uploadProgress,
                          minHeight       : 8,
                          backgroundColor : AppColors.primaryBlueLight,
                          valueColor      : const AlwaysStoppedAnimation<Color>(
                              AppColors.primaryBlue),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── Submit Button ─────────────────────────────────────
                    SizedBox(
                      width  : double.infinity,
                      height : 56,
                      child  : ElevatedButton(
                        onPressed : _isUploading ? null : _uploadItem,
                        style     : ElevatedButton.styleFrom(
                          backgroundColor        : _listingType == 'sell'
                              ? AppColors.primaryBlue
                              : AppColors.accentOrange,
                          foregroundColor        : Colors.white,
                          disabledBackgroundColor: AppColors.disabled,
                          disabledForegroundColor: AppColors.disabledText,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                        child: _isUploading
                            ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color      : Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Uploading '
                                  '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize   : 15,
                                  fontWeight : FontWeight.bold),
                            ),
                          ],
                        )
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_listingType == 'sell'
                                ? Icons.sell_outlined
                                : Icons.key_outlined),
                            const SizedBox(width: 10),
                            Text(
                              _listingType == 'sell'
                                  ? 'Submit for Review'
                                  : 'Submit for Review · Rent/'
                                  '${_rentDuration[0].toUpperCase()}'
                                  '${_rentDuration.substring(1)}',
                              style: const TextStyle(
                                  fontSize   : 15,
                                  fontWeight : FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _priceLabel() {
    if (_listingType == 'sell') return 'Price (Rs.)';
    if (_rentDuration == 'hour') return 'Rent Price (Rs. / hour)';
    if (_rentDuration == 'week') return 'Rent Price (Rs. / week)';
    return 'Rent Price (Rs. / day)';
  }

  // ── Rental Duration Selector ──────────────────────────────────────────────
  Widget _buildRentalDurationSelector() {
    final options = [
      {
        'value': 'hour',
        'label': 'Per Hour',
        'sub'  : 'Great for tools & equipment',
        'icon' : Icons.hourglass_bottom_rounded,
      },
      {
        'value': 'day',
        'label': 'Per Day',
        'sub'  : 'Best for most rentals',
        'icon' : Icons.wb_sunny_outlined,
      },
      {
        'value': 'week',
        'label': 'Per Week',
        'sub'  : 'Long-term rentals',
        'icon' : Icons.calendar_month_outlined,
      },
    ];

    return Column(
      children: options.map((opt) {
        final selected = _rentDuration == opt['value'];
        return GestureDetector(
          onTap: () =>
              setState(() => _rentDuration = opt['value'] as String),
          child: AnimatedContainer(
            duration  : const Duration(milliseconds: 200),
            margin    : const EdgeInsets.only(bottom: 10),
            padding   : const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color        : selected
                  ? AppColors.accentOrange.withOpacity(0.08)
                  : AppColors.surface,
              borderRadius : BorderRadius.circular(14),
              border       : Border.all(
                color : selected
                    ? AppColors.accentOrange : AppColors.border,
                width : selected ? 2 : 1,
              ),
            ),
            child: Row(children: [
              AnimatedContainer(
                duration     : const Duration(milliseconds: 200),
                width        : 42,
                height       : 42,
                decoration   : BoxDecoration(
                  color        : selected
                      ? AppColors.accentOrange
                      : AppColors.primaryBlueLight,
                  borderRadius : BorderRadius.circular(12),
                ),
                child: Icon(
                  opt['icon'] as IconData,
                  size  : 20,
                  color : selected ? Colors.white : AppColors.primaryBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(opt['label'] as String,
                        style: TextStyle(
                            fontSize   : 15,
                            fontWeight : FontWeight.w700,
                            color      : selected
                                ? AppColors.accentOrange
                                : AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(opt['sub'] as String,
                        style: const TextStyle(
                            fontSize : 12,
                            color    : AppColors.textSecondary)),
                  ],
                ),
              ),
              AnimatedContainer(
                duration  : const Duration(milliseconds: 200),
                width     : 22,
                height    : 22,
                decoration: BoxDecoration(
                  shape  : BoxShape.circle,
                  color  : selected
                      ? AppColors.accentOrange : AppColors.surface,
                  border : Border.all(
                    color : selected
                        ? AppColors.accentOrange : AppColors.border,
                    width : 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check,
                    size: 13, color: Colors.white)
                    : null,
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ── Condition chips ───────────────────────────────────────────────────────
  Widget _buildConditionChips() {
    return Wrap(
      spacing    : 10,
      runSpacing : 10,
      children   : _conditions.map((cond) {
        final selected = _selectedCondition == cond['value'];
        return GestureDetector(
          onTap: () =>
              setState(() => _selectedCondition = cond['value'] as String),
          child: AnimatedContainer(
            duration  : const Duration(milliseconds: 180),
            padding   : const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color        : selected
                  ? AppColors.primaryBlue : AppColors.surface,
              borderRadius : BorderRadius.circular(12),
              border       : Border.all(
                  color: selected
                      ? AppColors.primaryBlue : AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(cond['icon'] as IconData,
                  size  : 15,
                  color : selected ? Colors.white : AppColors.primaryBlue),
              const SizedBox(width: 6),
              Text(cond['value'] as String,
                  style: TextStyle(
                      fontSize   : 13,
                      fontWeight : FontWeight.w600,
                      color      : selected
                          ? Colors.white : AppColors.textPrimary)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ── Toggle Btn ────────────────────────────────────────────────────────────
  Widget _toggleBtn({required String label, required String value}) {
    final active = _listingType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _listingType = value),
        child: AnimatedContainer(
          duration  : const Duration(milliseconds: 200),
          padding   : const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color        : active ? Colors.white : Colors.transparent,
            borderRadius : BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign : TextAlign.center,
            style     : TextStyle(
              color      : active
                  ? AppColors.primaryBlue
                  : Colors.white.withOpacity(0.8),
              fontWeight : active ? FontWeight.bold : FontWeight.w500,
              fontSize   : 15,
            ),
          ),
        ),
      ),
    );
  }

  // ── Image thumbnail ───────────────────────────────────────────────────────
  Widget _imageThumb(File file, int index) {
    return Container(
      width   : 110,
      height  : 110,
      margin  : const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        borderRadius : BorderRadius.circular(14),
        border       : Border.all(
          color : index == 0 ? AppColors.primaryBlue : AppColors.border,
          width : index == 0 ? 2 : 1,
        ),
        image: DecorationImage(
            image: FileImage(file), fit: BoxFit.cover),
      ),
      child: Stack(children: [
        if (index == 0)
          Positioned(
            bottom : 6,
            left   : 6,
            child  : Container(
              padding : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color        : AppColors.primaryBlue,
                borderRadius : BorderRadius.circular(6),
              ),
              child: const Text('Cover',
                  style: TextStyle(
                      color      : Colors.white,
                      fontSize   : 10,
                      fontWeight : FontWeight.bold)),
            ),
          ),
        Positioned(
          top   : 5,
          right : 5,
          child : GestureDetector(
            onTap: () => _removeImage(index),
            child: Container(
              width      : 22,
              height     : 22,
              decoration : const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Add photo button ──────────────────────────────────────────────────────
  Widget _addPhotoButton() {
    return GestureDetector(
      onTap: _isUploading ? null : _pickImage,
      child: Container(
        width      : 110,
        height     : 110,
        decoration : BoxDecoration(
          color        : AppColors.primaryBlueLight,
          borderRadius : BorderRadius.circular(14),
          border       : Border.all(
              color: AppColors.primaryBlue.withOpacity(0.3), width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_a_photo_outlined,
              color: AppColors.primaryBlue, size: 30),
          const SizedBox(height: 6),
          Text(
            _images.isEmpty ? 'Add Photo' : 'Add More',
            style: const TextStyle(
                color      : AppColors.primaryBlue,
                fontSize   : 11,
                fontWeight : FontWeight.w600),
          ),
          Text('${_images.length}/$_maxImages',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10)),
        ]),
      ),
    );
  }

  // ── Category chips ────────────────────────────────────────────────────────
  Widget _buildCategoryChips() {
    return Wrap(
      spacing    : 10,
      runSpacing : 10,
      children   : _categories.map((cat) {
        final selected = _selectedCategory == cat['id'];
        return GestureDetector(
          onTap: () =>
              setState(() => _selectedCategory = cat['id'] as String),
          child: AnimatedContainer(
            duration  : const Duration(milliseconds: 180),
            padding   : const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color        : selected
                  ? AppColors.primaryBlue : AppColors.surface,
              borderRadius : BorderRadius.circular(12),
              border       : Border.all(
                color : selected ? AppColors.primaryBlue : AppColors.border,
                width : selected ? 0 : 1,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(getIcon(cat['icon'] as String),
                  size  : 16,
                  color : selected ? Colors.white : AppColors.primaryBlue),
              const SizedBox(width: 6),
              Text(cat['name'] as String,
                  style: TextStyle(
                      fontSize   : 13,
                      fontWeight : FontWeight.w600,
                      color      : selected
                          ? Colors.white : AppColors.textPrimary)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _sectionLabel(String title, IconData icon) {
    return Row(children: [
      Container(
        width      : 32,
        height     : 32,
        decoration : BoxDecoration(
          color        : AppColors.primaryBlueLight,
          borderRadius : BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.primaryBlue),
      ),
      const SizedBox(width: 10),
      Text(title,
          style: const TextStyle(
              fontSize   : 16,
              fontWeight : FontWeight.bold,
              color      : AppColors.textPrimary)),
    ]);
  }

  // ── Text field builder ────────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController  controller,
    required String                 label,
    required String                 hint,
    required IconData               icon,
    String? Function(String?)?      validator,
    TextInputType                   inputType = TextInputType.text,
    int                             maxLines  = 1,
  }) {
    return TextFormField(
      controller   : controller,
      keyboardType : inputType,
      maxLines     : maxLines,
      enabled      : !_isUploading,
      style        : const TextStyle(color: AppColors.textPrimary),
      decoration   : InputDecoration(
        labelText  : label,
        hintText   : hint,
        hintStyle  : const TextStyle(color: AppColors.textSecondary),
        labelStyle : const TextStyle(color: AppColors.textSecondary),
        prefixIcon : Icon(icon, color: AppColors.primaryBlue),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(
                color: AppColors.primaryBlue, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(color: Colors.red)),
        filled    : true,
        fillColor : AppColors.surface,
      ),
      validator: validator,
    );
  }
}

// ── Status step widget for success sheet ──────────────────────────────────────
class _StatusStep extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     done;
  final bool     active;
  final bool     isLast;

  const _StatusStep({
    required this.icon,
    required this.label,
    required this.done,
    required this.active,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = done
        ? AppColors.successGreen
        : active
        ? AppColors.accentOrange
        : AppColors.textSecondary.withOpacity(0.4);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color : color.withOpacity(0.12),
              shape : BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          if (!isLast)
            Container(
              width: 2, height: 22,
              color: color.withOpacity(0.25),
            ),
        ]),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            label,
            style: TextStyle(
                fontSize  : 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color     : active
                    ? AppColors.accentOrange
                    : done
                    ? AppColors.successGreen
                    : AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}