import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'dart:async';
import 'package:image_picker/image_picker.dart'; 
import 'package:permission_handler/permission_handler.dart'; 
import 'constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart';
import 'package:logger/logger.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // --- STATE VARIABLES ---
  int _currentTabIndex = 0;
  bool _isEditingPersonal = false;
  bool _isSubmitting = false;
  bool _isLoadingProfile = true;
  bool _isUpdatingPassword = false;
  String? _errorMessage;
  
  XFile? _pickedImage; 
  Uint8List? _webImageBytes; 

  final logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0, 
      errorMethodCount: 5,
      lineLength: 80,
      colors: true, 
      printEmojis: true,
    ),
  );

  // --- FETCHED DATA --- 
  String _fullName = '';
  String _empId = '';
  String _jobTitle = '';
  String _department = '';
  String _workEmail = '';
  String _workMode = '';
  String _joiningDate = '';

  // --- TEXT CONTROLLERS ---
  late TextEditingController _fullNameCtrl; 
  late TextEditingController _personalEmailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emergencyCtrl;
  late TextEditingController _addressCtrl;

  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController(text: "");
    _personalEmailCtrl = TextEditingController(text: "");
    _phoneCtrl = TextEditingController(text: "");
    _emergencyCtrl = TextEditingController(text: "");
    _addressCtrl = TextEditingController(text: "");
    
    _fetchEmployeeProfile();
  }

  @override
  void dispose() {
    _personalEmailCtrl.dispose();
    _phoneCtrl.dispose();
    _emergencyCtrl.dispose();
    _addressCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  // =========================================================================
  // FETCH EMPLOYEE PROFILE FROM BACKEND & LOAD SAVED AVATAR
  // =========================================================================
  Future<void> _fetchEmployeeProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? loggedInEmpId = prefs.getString('emp_id');

      if (loggedInEmpId == null) {
        _handleProfileError('Session expired. Please log in again.');
        return;
      }

      final Uri requestUri = Uri.parse('${ApiConstants.getProfile}?emp_id=$loggedInEmpId');
      final response = await http.get(requestUri).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['status'] == 'success') {
          final employeeData = responseData['data'];

          // 👇 NEW: Load the globally saved avatar instantly!
          final savedWeb = prefs.getString('profile_image_web');
          final savedMobile = prefs.getString('profile_image_mobile');
          
          setState(() {
            if (kIsWeb && savedWeb != null) {
              _webImageBytes = base64Decode(savedWeb);
            } else if (!kIsWeb && savedMobile != null) {
              _pickedImage = XFile(savedMobile);
            }

            _fullName = employeeData['fullName'] ?? 'N/A';
            _empId = employeeData['empId'] ?? 'N/A';
            _jobTitle = employeeData['jobTitle'] ?? 'N/A';
            _department = employeeData['department'] ?? 'N/A';
            _workEmail = employeeData['workEmail'] ?? 'N/A';
            _workMode = employeeData['workMode'] ?? 'N/A';
            _joiningDate = employeeData['joiningDate'] ?? 'N/A';
            
            _fullNameCtrl.text = employeeData['fullName'] ?? employeeData['full_name'] ?? ''; 
            _personalEmailCtrl.text = employeeData['personalEmail'] ?? employeeData['personal_email'] ?? '';
            _phoneCtrl.text = employeeData['phoneNumber'] ?? employeeData['phone_number'] ?? '';
            _emergencyCtrl.text = employeeData['emergencyContact'] ?? employeeData['emergency_contact'] ?? '';
            _addressCtrl.text = employeeData['residentialAddress'] ?? employeeData['residential_address'] ?? employeeData['address'] ?? '';
            
            _isLoadingProfile = false;
          });
        } else {
          _handleProfileError(responseData['message'] ?? 'Unknown error from server');
        }
      } else {
        _handleProfileError('Server error: ${response.statusCode}');
      }
    } on TimeoutException {
      _handleProfileError('Request timed out. Please check your internet connection.');
    } catch (e) {
      _handleProfileError('Network error: $e');
    }
  }

  void _handleProfileError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoadingProfile = false;
      _errorMessage = message;
      _fullName = 'Guest User';
      _empId = 'N/A';
      _jobTitle = 'N/A';
      _department = 'N/A';
      _workEmail = 'N/A';
      _workMode = 'N/A';
      _joiningDate = 'N/A';
    });
  }

  // =========================================================================
  // PHOTO PICKING LOGIC (SAVES TO GLOBAL MEMORY)
  // =========================================================================
  Future<void> _pickProfilePicture() async {
    if (!kIsWeb) {
      Map<Permission, PermissionStatus> statuses = await [Permission.camera, Permission.photos].request();
      if (!mounted) return;
      if (statuses[Permission.camera]!.isDenied || statuses[Permission.photos]!.isDenied) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Camera & Photo permissions are required to change your picture.")));
        return;
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (builder) => _buildPhotoPickerSheet(),
    );
  }

  Widget _buildPhotoPickerSheet() {
    final picker = ImagePicker();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 24),
          Text("Update Profile Photo", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kTextDark)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPhotoOption(Icons.camera_alt_rounded, "Camera", () async {
                Navigator.pop(context);
                final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
                if (image != null) _saveImageGlobally(image);
              }),
              _buildPhotoOption(Icons.photo_library_rounded, "Gallery", () async {
                Navigator.pop(context);
                final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                if (image != null) _saveImageGlobally(image);
              }),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // 👇 NEW: Locks the image into the phone's memory so the Dashboard can see it!
  Future<void> _saveImageGlobally(XFile image) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (kIsWeb) {
      final bytes = await image.readAsBytes();
      await prefs.setString('profile_image_web', base64Encode(bytes));
      setState(() {
        _webImageBytes = bytes;
        _pickedImage = image; 
      });
    } else {
      await prefs.setString('profile_image_mobile', image.path);
      setState(() => _pickedImage = image);
    }
  }

  Widget _buildPhotoOption(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: kPrimaryGreen.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: kPrimaryGreen, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: GoogleFonts.inter(color: kTextDark, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // --- UI HELPER: WEB-SAFE AVATAR ---
  Widget _buildAvatarImage() {
    if (kIsWeb && _webImageBytes != null) {
      return Image.memory(_webImageBytes!, width: 100, height: 100, fit: BoxFit.cover);
    } 
    
    if (!kIsWeb && _pickedImage != null) {
      return Image.network(
        _pickedImage!.path, 
        width: 100, height: 100, fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 50),
      );
    }

    return Container(
      width: 100, height: 100,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [kPrimaryGreen, kSecondaryGreen])),
      child: Center(
        child: Text(
          _fullName.isNotEmpty ? _fullName.substring(0, 2).toUpperCase() : "??",
          style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  // --- ACTIONS ---
  Future<void> _submitToHR() async {
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _isEditingPersonal = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update request submitted to HR successfully!", style: GoogleFonts.inter(fontWeight: FontWeight.bold)), backgroundColor: kPrimaryGreen, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))));
  }

  Future<void> _updatePassword() async {
    if (_currentPassCtrl.text.isEmpty || _newPassCtrl.text.isEmpty || _confirmPassCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All password fields are required"), backgroundColor: Colors.redAccent));
      return;
    }

    if (_newPassCtrl.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New password must be at least 8 characters"), backgroundColor: Colors.redAccent));
      return;
    }

    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New passwords do not match"), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isUpdatingPassword = true);

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.updatePassword),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'employee_id': _empId, 'current_password': _currentPassCtrl.text, 'new_password': _newPassCtrl.text},
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      final Map<String, dynamic> responseData = json.decode(response.body);

      if (responseData['status'] == 'success') {
        setState(() {
          _isUpdatingPassword = false;
          _currentPassCtrl.clear();
          _newPassCtrl.clear();
          _confirmPassCtrl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Password updated successfully!", style: GoogleFonts.inter(fontWeight: FontWeight.bold)), backgroundColor: kPrimaryGreen, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), duration: const Duration(seconds: 3)));
      } else {
        setState(() => _isUpdatingPassword = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(responseData['message'] ?? 'Failed to update password', style: GoogleFonts.inter(fontWeight: FontWeight.bold)), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), duration: const Duration(seconds: 3)));
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _isUpdatingPassword = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request timed out. Please check your internet connection."), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating, duration: Duration(seconds: 3)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdatingPassword = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e", style: GoogleFonts.inter(fontWeight: FontWeight.bold)), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), duration: const Duration(seconds: 3)));
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.logout_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text("Log Out", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kTextDark)),
          ],
        ),
        content: Text("Are you sure you want to securely log out of your account?", style: GoogleFonts.inter(color: kTextMuted, height: 1.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: GoogleFonts.inter(color: kTextMuted, fontWeight: FontWeight.w600))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('isLoggedIn', false); 
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
            },
            child: Text("Log Out", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              pinned: false,
              centerTitle: false,
              title: Text("My Profile", style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: kTextDark, letterSpacing: -0.5)),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildGlassProfileCard(),
                  const SizedBox(height: 24),
                  _buildCustomTabSwitcher(),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildCurrentTabContent(),
                  ),
                  const SizedBox(height: 40), 
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: Text("Secure Log Out", style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: Colors.redAccent.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  const SizedBox(height: 100), 
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // WIDGET: GLASSMORPHIC PROFILE CARD
  // =========================================================================
  Widget _buildGlassProfileCard() {
    if (_isLoadingProfile) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.5)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
            child: SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: kPrimaryGreen),
                    const SizedBox(height: 16),
                    Text('Loading profile...', style: GoogleFonts.inter(color: kTextMuted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.red.withValues(alpha: 0.3)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text('Error Loading Profile', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                const SizedBox(height: 8),
                Text(_errorMessage!, style: GoogleFonts.inter(color: kTextMuted, textStyle: const TextStyle(fontSize: 12))),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _fetchEmployeeProfile,
                  style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen),
                  child: Text('Retry', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.5)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipOval(
                    child: _buildAvatarImage(),
                  ),
                  GestureDetector(
                    onTap: _pickProfilePicture,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
                      child: const Icon(Icons.camera_alt_rounded, size: 16, color: kPrimaryGreen),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              Text(_fullName, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: kTextDark)),
              const SizedBox(height: 4),
              Text("$_jobTitle | $_department", style: GoogleFonts.inter(fontSize: 14, color: kTextMuted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildProfileStat("Emp ID", _empId, kTextDark),
                  Container(width: 1, height: 40, color: Colors.black.withValues(alpha: 0.1)),
                  _buildProfileStat("Status", "Active", Colors.green),
                ],
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(color: kPrimaryGreen.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.email_rounded, size: 18, color: kPrimaryGreen),
                    const SizedBox(width: 8),
                    Text(_workEmail, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: kPrimaryGreen)),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileStat(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: valueColor)),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: kTextMuted, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildCustomTabSwitcher() {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(25)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / 3;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: _currentTabIndex * tabWidth,
                top: 0,
                bottom: 0,
                width: tabWidth,
                child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(21), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, 2))])),
              ),
              Row(
                children: [
                  _buildTabButton("Personal", 0),
                  _buildTabButton("Organization", 1),
                  _buildTabButton("Security", 2),
                ],
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildTabButton(String title, int index) {
    final isActive = _currentTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentTabIndex = index;
            _isEditingPersonal = false;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: GoogleFonts.inter(fontSize: 14, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? kPrimaryGreen : kTextMuted),
            child: Text(title),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_currentTabIndex) {
      case 0: return _buildPersonalInfoTab();
      case 1: return _buildOrganizationTab();
      case 2: return _buildSecurityTab();
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildPersonalInfoTab() {
    return Container(
      key: const ValueKey("Personal"),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.black.withValues(alpha: 0.03)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Contact Information", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark)),
              if (!_isEditingPersonal)
                TextButton.icon(
                  onPressed: () => setState(() => _isEditingPersonal = true),
                  icon: const Icon(Icons.edit_rounded, size: 16, color: kPrimaryGreen),
                  label: Text("Edit Request", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: kPrimaryGreen)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), backgroundColor: kPrimaryGreen.withValues(alpha: 0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
            ],
          ),
          const Divider(height: 32),
          _buildTextField("Full Name", controller: _fullNameCtrl, isReadOnly: true, icon: Icons.person_rounded),
          const SizedBox(height: 16),
          _buildTextField("Personal Email", controller: _personalEmailCtrl, isReadOnly: !_isEditingPersonal, icon: Icons.email_outlined),
          const SizedBox(height: 16),
          _buildTextField("Phone Number", controller: _phoneCtrl, isReadOnly: !_isEditingPersonal, icon: Icons.phone_outlined),
          const SizedBox(height: 16),
          _buildTextField("Emergency Contact", controller: _emergencyCtrl, isReadOnly: !_isEditingPersonal, icon: Icons.health_and_safety_outlined),
          const SizedBox(height: 16),
          _buildTextField("Residential Address", controller: _addressCtrl, isReadOnly: !_isEditingPersonal, icon: Icons.home_outlined, maxLines: 3),
          
          if (_isEditingPersonal) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => setState(() => _isEditingPersonal = false),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Colors.redAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text("Cancel", style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitToHR,
                    style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                    child: _isSubmitting 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text("Submit to HR", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            )
          ]
        ],
      ),
    );
  }

  Widget _buildOrganizationTab() {
    return Container(
      key: const ValueKey("Org"),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.black.withValues(alpha: 0.03)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Employment Details", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, size: 12, color: kTextMuted),
                    const SizedBox(width: 4),
                    Text("Read Only", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: kTextMuted)),
                  ],
                ),
              )
            ],
          ),
          const Divider(height: 32),
          _buildTextField("Department", initialValue: _department, isReadOnly: true, icon: Icons.domain_rounded),
          const SizedBox(height: 16),
          _buildTextField("Job Title", initialValue: _jobTitle, isReadOnly: true, icon: Icons.work_outline_rounded),
          const SizedBox(height: 16),
          _buildTextField("Date of Joining", initialValue: _joiningDate, isReadOnly: true, icon: Icons.calendar_today_rounded),
          const SizedBox(height: 16),
          _buildTextField("Work Location / Mode", initialValue: _workMode, isReadOnly: true, icon: Icons.business_rounded),
        ],
      ),
    );
  }

  Widget _buildSecurityTab() {
    return Container(
      key: const ValueKey("Security"),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.black.withValues(alpha: 0.03)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Account Security", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark)),
          const Divider(height: 32),
          _buildTextField("Current Password", controller: _currentPassCtrl, isPassword: true, hint: "Enter current password"),
          const SizedBox(height: 16),
          _buildTextField("New Password", controller: _newPassCtrl, isPassword: true, hint: "Min 8 characters"),
          const SizedBox(height: 16),
          _buildTextField("Confirm Password", controller: _confirmPassCtrl, isPassword: true, hint: "Re-enter new password"),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryGreen,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
              ),
              onPressed: _isUpdatingPassword ? null : _updatePassword,
              child: _isUpdatingPassword 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white), strokeWidth: 2.5))
                  : Text("Save New Password", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTextField(String label, {String? initialValue, TextEditingController? controller, bool isReadOnly = false, bool isPassword = false, String? hint, IconData? icon, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: kTextMuted, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: initialValue,
          controller: controller,
          readOnly: isReadOnly,
          obscureText: isPassword,
          maxLines: maxLines,
          style: GoogleFonts.inter(fontSize: 14, color: isReadOnly ? kTextMuted : kTextDark, fontWeight: isReadOnly ? FontWeight.w500 : FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.black.withValues(alpha: 0.2)),
            prefixIcon: icon != null ? Icon(icon, size: 20, color: isReadOnly ? Colors.black.withValues(alpha: 0.2) : kPrimaryGreen) : null,
            filled: true,
            fillColor: isReadOnly ? Colors.black.withValues(alpha: 0.02) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPrimaryGreen, width: 1.5)),
          ),
        ),
      ],
    );
  }
}