import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'constants.dart';
import 'home_screen.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isCameraGranted = false;
  bool _isLocationGranted = false;
  bool _isStorageGranted = false;
  bool _checkingPermissions = true;

  @override
  void initState() {
    super.initState();
    _checkCurrentPermissionStatus();
  }

  // 🟢 FIXED: Safe Post-Frame navigation handling + Android Storage policy bypass logic
  Future<void> _checkCurrentPermissionStatus() async {
    if (kIsWeb) {
      // Web handles permissions dynamically at runtime
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigateToHome();
      });
      return;
    }

    final cameraStatus = await Permission.camera.status;
    final locationStatus = await Permission.locationWhenInUse.status;
    
    bool storageCheckResult = false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android no longer declares manifest storage strings, handling it via System Photo Picker implicitly
      storageCheckResult = true; 
    } else {
      final iosStorageStatus = await Permission.storage.status;
      storageCheckResult = iosStorageStatus.isGranted;
    }

    if (!mounted) return;

    setState(() {
      _isCameraGranted = cameraStatus.isGranted;
      _isLocationGranted = locationStatus.isGranted;
      _isStorageGranted = storageCheckResult;
      _checkingPermissions = false;
    });

    // If all permissions are already granted, skip this screen safely post-frame
    if (_isCameraGranted && _isLocationGranted && _isStorageGranted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigateToHome();
      });
    }
  }

  // Request required permissions sequentially
  Future<void> _requestAllPermissions() async {
    setState(() => _checkingPermissions = true);

    // 1. Request Location
    final locationReq = await Permission.locationWhenInUse.request();
    if (locationReq.isGranted) {
      // Request background location for continuous geofence updates
      await Permission.locationAlways.request();
    }

    // 2. Request Camera
    final cameraReq = await Permission.camera.request();

    // 3. Evaluate Storage handling rules per OS platform baseline
    bool storageReqResult = false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      storageReqResult = true; // Auto-pass on Android to comply with new Google Play storage policies
    } else {
      final iosStorageReq = await Permission.storage.request();
      storageReqResult = iosStorageReq.isGranted;
    }

    if (!mounted) return;

    // Update UI flags with current runtime permissions status
    setState(() {
      _isCameraGranted = cameraReq.isGranted;
      _isLocationGranted = locationReq.isGranted;
      _isStorageGranted = storageReqResult;
      _checkingPermissions = false;
    });

    // If all core hardware validations clear, transition straight to the dashboard
    if (_isCameraGranted && _isLocationGranted && _isStorageGranted) {
      _navigateToHome();
    } else {
      // If any core permission is permanently denied, show settings bypass dialog
      if (cameraReq.isPermanentlyDenied || locationReq.isPermanentlyDenied) {
        _showSettingsDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Please accept the required permissions to proceed.",
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.orangeAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text("Permissions Blocked", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text(
          "Workack requires Camera and Location access permanently to operate. Please allow them manually in your device system settings.",
          style: GoogleFonts.inter(),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: kTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen),
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text("Open Settings", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermissions) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: kPrimaryGreen)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 30),
              // Header Icon Component
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kPrimaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.security_rounded, color: kPrimaryGreen, size: 40),
              ),
              const SizedBox(height: 24),
              Text(
                "Hardware Access Required",
                style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, color: kTextDark, letterSpacing: -0.5),
              ),
              const SizedBox(height: 12),
              Text(
                "To ensure tamper-proof check-ins and smooth background clock-outs, Workack requires secure access to your hardware utilities.",
                style: GoogleFonts.inter(fontSize: 15, color: kTextMuted, height: 1.5),
              ),
              const SizedBox(height: 40),
              
              // Permission Checklist Item View Tree
              Expanded(
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildPermissionRow(
                      icon: Icons.location_on_rounded,
                      title: "Location Services",
                      subtitle: "Validates your operational geofence proximity presence rules.",
                      isGranted: _isLocationGranted,
                    ),
                    const Divider(height: 32, color: Color(0xFFF1F5F9)),
                    _buildPermissionRow(
                      icon: Icons.camera_alt_rounded,
                      title: "Front Facing Camera",
                      subtitle: "Triggers AI Biometric Face Scanning identity loops.",
                      isGranted: _isCameraGranted,
                    ),
                    const Divider(height: 32, color: Color(0xFFF1F5F9)),
                    _buildPermissionRow(
                      icon: Icons.folder_shared_rounded,
                      title: "Storage & Photos Access",
                      subtitle: defaultTargetPlatform == TargetPlatform.android 
                        ? "Uses secure system dialog layers to manage file attachments cleanly."
                        : "Caches avatar frames and structural shifts history maps locally.",
                      isGranted: _isStorageGranted,
                    ),
                  ],
                ),
              ),

              // Bottom Confirmation CTA Trigger Call Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _requestAllPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                    shadowColor: kPrimaryGreen.withOpacity(0.3),
                  ),
                  child: Text(
                    "Grant Necessary Access",
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withOpacity(0.02)),
          ),
          child: Icon(icon, color: isGranted ? kPrimaryGreen : kTextMuted, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(fontSize: 13, color: kTextMuted, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Trailing status flag chip component
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isGranted ? kPrimaryGreen.withOpacity(0.1) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            isGranted ? "Allowed" : "Required",
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isGranted ? kPrimaryGreen : kTextMuted,
            ),
          ),
        ),
      ],
    );
  }
}