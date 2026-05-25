import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_constants.dart'; 
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:local_auth/local_auth.dart'; 
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; 
import 'dart:ui'; 
import 'constants.dart';
import 'home_screen.dart'; 

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // --- BIOMETRIC & VAULT VARIABLES ---
  final LocalAuthentication auth = LocalAuthentication();
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  bool _canCheckBiometrics = false;
  bool _hasSavedCredentials = false;

  @override
  void initState() {
    super.initState();
    
    // Entrance Animations Setup
    _animController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 800)
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut)
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutQuart)
    );
    
    _animController.forward();
    
    // Check for Biometrics on Startup
    _checkBiometricAvailability();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // =====================================================================
  // BIOMETRIC LOGIC
  // =====================================================================
  Future<void> _checkBiometricAvailability() async {
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await auth.isDeviceSupported();
      
      // Look inside the secure vault
      String? savedEmail = await secureStorage.read(key: 'saved_email');
      String? savedPassword = await secureStorage.read(key: 'saved_password');

      if (mounted) {
        setState(() {
          _canCheckBiometrics = canAuthenticate;
          _hasSavedCredentials = (savedEmail != null && savedPassword != null);
        });
      }
    } catch (e) {
      debugPrint("Error checking biometrics: $e");
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      // THE FIX: Using the universal syntax to bypass the analyzer lock bug
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Scan your face or fingerprint to log in to Workack',
      );

      if (didAuthenticate) {
        // Unlock the vault and grab the credentials
        String? savedEmail = await secureStorage.read(key: 'saved_email');
        String? savedPassword = await secureStorage.read(key: 'saved_password');
        
        if (savedEmail != null && savedPassword != null) {
          // Fill the hidden fields and trigger the PHP login automatically
          _emailController.text = savedEmail;
          _passwordController.text = savedPassword;
          _handleLogin(isBiometricLogin: true);
        }
      }
    } catch (e) {
      _showErrorSnackBar("Biometric authentication failed or was canceled.");
    }
  }

  // =====================================================================
// SERVER LOGIN LOGIC
// =====================================================================
Future<void> _handleLogin({bool isBiometricLogin = false}) async {
  if (_formKey.currentState!.validate() || isBiometricLogin) {
    setState(() => _isLoading = true);
    
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.login), 
        body: {
          "email": _emailController.text.trim(),
          "password": _passwordController.text,
        },
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return; // Guard async gap

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);

        if (responseData['status'] == 'success') {
          final userData = responseData['data'];
          
          // --- 🚨 CRITICAL SAAS FIX: SAVE COMPANY ID 🚨 ---
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLoggedIn', true);
          await prefs.setString('emp_id', userData['empId']?.toString() ?? ''); 
          await prefs.setString('full_name', userData['fullName']?.toString() ?? '');
          
          // IMPORTANT: Ensure your PHP returns 'company_id' in the JSON response
          await prefs.setString('company_id', userData['company_id']?.toString() ?? '');
          // --------------------------------------------------

          // BIOMETRIC PROMPT FLOW
          if (!isBiometricLogin && _canCheckBiometrics) {
            bool? wantsBiometrics = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: Text("Enable Fast Login?", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                content: Text("Use Fingerprint or Face ID for future logins?", style: GoogleFonts.inter()),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kPrimaryGreen),
                    onPressed: () => Navigator.pop(context, true), 
                    child: const Text("Enable", style: TextStyle(color: Colors.white))
                  ),
                ],
              ),
            );

            if (wantsBiometrics == true) {
              await secureStorage.write(key: 'saved_email', value: _emailController.text.trim());
              await secureStorage.write(key: 'saved_password', value: _passwordController.text);
            }
          }

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else {
          _showErrorSnackBar(responseData['message'] ?? 'Login failed.');
        }
      } else {
        _showErrorSnackBar('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Network error. Please check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // Fallback for buildInputDecoration
  InputDecoration _buildLocalInputDecoration({required String hint, required IconData prefixIcon, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: kTextMuted),
      prefixIcon: Icon(prefixIcon, color: kPrimaryGreen),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPrimaryGreen, width: 2)),
    );
  }

  // =====================================================================
  // UI LAYOUT
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9), 
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -50,
            child: _buildBackgroundOrb(250, kPrimaryGreen.withValues(alpha: 0.15)),
          ),
          Positioned(
            bottom: -50,
            left: -100,
            child: _buildBackgroundOrb(300, kSecondaryGreen.withValues(alpha: 0.1)),
          ),
          
          SafeArea(
            child: Center( 
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: SlideTransition(
                              position: _slideAnimation,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildAppHeader(),
                                  const SizedBox(height: 40),

                                  Container(
                                    padding: const EdgeInsets.all(32),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.04),
                                          blurRadius: 24,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Form(
                                      key: _formKey,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Welcome Back",
                                            style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: kTextDark, letterSpacing: -0.5),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "Enter your credentials to manage your workforce.",
                                            style: GoogleFonts.inter(fontSize: 14, color: kTextMuted, height: 1.4),
                                          ),
                                          
                                          const SizedBox(height: 32),

                                          // Email Input
                                          Text("Email Address", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: kTextDark, letterSpacing: 0.5)),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: _emailController,
                                            keyboardType: TextInputType.emailAddress,
                                            style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                                            validator: (value) {
                                              if (value == null || value.isEmpty) return 'Please enter your email';
                                              if (!value.contains('@')) return 'Enter a valid email address';
                                              return null;
                                            },
                                            decoration: _buildLocalInputDecoration(hint: "name@company.com", prefixIcon: Icons.email_outlined),
                                          ),

                                          const SizedBox(height: 20),

                                          // Password Input
                                          Text("Password", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: kTextDark, letterSpacing: 0.5)),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: _passwordController,
                                            obscureText: !_isPasswordVisible,
                                            style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                                            validator: (value) {
                                              if (value == null || value.isEmpty) return 'Please enter your password';
                                              if (value.length < 6) return 'Password must be at least 6 characters';
                                              return null;
                                            },
                                            decoration: _buildLocalInputDecoration(
                                              hint: "••••••••",
                                              prefixIcon: Icons.lock_outline_rounded,
                                              suffixIcon: IconButton(
                                                icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility, color: kTextMuted, size: 20),
                                                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                                              ),
                                            ),
                                          ),

                                          const SizedBox(height: 24),

                                          // Actions Row
                                          Row(
                                            children: [
                                              Expanded(
                                                child: SizedBox(
                                                  height: 56,
                                                  child: ElevatedButton(
                                                    onPressed: _isLoading ? null : () => _handleLogin(),
                                                    style: ElevatedButton.styleFrom(
                                                      padding: EdgeInsets.zero,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                      elevation: 8,
                                                      shadowColor: kPrimaryGreen.withValues(alpha: 0.3),
                                                    ),
                                                    child: Ink(
                                                      decoration: BoxDecoration(
                                                        gradient: const LinearGradient(colors: [kPrimaryGreen, kSecondaryGreen], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                                        borderRadius: BorderRadius.circular(16),
                                                      ),
                                                      child: Container(
                                                        alignment: Alignment.center,
                                                        child: _isLoading 
                                                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                                                          : Text("Sign In", style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              
                                              // Biometric Fast Login Button
                                              if (_canCheckBiometrics && _hasSavedCredentials) ...[
                                                const SizedBox(width: 16),
                                                SizedBox(
                                                  height: 56,
                                                  width: 56,
                                                  child: OutlinedButton(
                                                    onPressed: _isLoading ? null : _authenticateWithBiometrics,
                                                    style: OutlinedButton.styleFrom(
                                                      padding: EdgeInsets.zero,
                                                      side: const BorderSide(color: kPrimaryGreen, width: 2),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                    ),
                                                    child: const Icon(Icons.fingerprint_rounded, color: kPrimaryGreen, size: 28),
                                                  ),
                                                ),
                                              ]
                                            ],
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
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPER WIDGETS ---
  Widget _buildAppHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: kPrimaryGreen.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/images/logo.png', 
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: kPrimaryGreen,
                child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 40),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "Workack",
          style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, color: kTextDark, letterSpacing: -1),
        ),
        const SizedBox(height: 4),
        Text(
          "Smart Attendance System",
          style: GoogleFonts.inter(fontSize: 13, color: kTextMuted, fontWeight: FontWeight.w500, letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _buildBackgroundOrb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}