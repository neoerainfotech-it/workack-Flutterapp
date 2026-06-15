import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'constants.dart';
import 'onboarding_screen.dart';
import 'login_screen.dart';
import 'permission_screen.dart'; // Mapped for multi-tenant hardware verification steps
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, 
  ));

  final prefs = await SharedPreferences.getInstance();
  final bool onboardingCompleted = prefs.getBool('onboardingCompleted') ?? false;
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  runApp(AttendanceApp(
    onboardingCompleted: onboardingCompleted, 
    isLoggedIn: isLoggedIn, 
  ));
}

class AttendanceApp extends StatelessWidget {
  final bool onboardingCompleted;
  final bool isLoggedIn; 
  
  const AttendanceApp({
    super.key, 
    required this.onboardingCompleted,
    required this.isLoggedIn,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Workack Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: kMilkWhite,
        primaryColor: kPrimaryGreen,
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
        useMaterial3: true,
      ),
      home: SplashScreen(
        onboardingCompleted: onboardingCompleted,
        isLoggedIn: isLoggedIn,
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final bool onboardingCompleted;
  final bool isLoggedIn; 

  const SplashScreen({
    super.key, 
    required this.onboardingCompleted,
    required this.isLoggedIn,
  });

  // 🟢 FIXED: Removed 'const' because building state contexts dynamically cannot be evaluated compile-time
  @override
  Widget build(BuildContext context) => _SplashScreenState().build(context); 
  
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      
      // 🟢 ROUTING ROUTE TRANSITION MATRIX:
      // Controls whether a user needs to see onboarding, login credentials, or hardware validation.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) {
            if (widget.onboardingCompleted) {
              // If logged in, intercept them with PermissionScreen before landing on HomeScreen
              return widget.isLoggedIn ? const PermissionScreen() : const LoginScreen();
            } else {
              return const OnboardingScreen();
            }
          },
        ),
      );
    });
  }

  // =========================================================================
  // THE PERFORMANCE FIX: Pre-caching Images
  // =========================================================================
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Low-latency asset allocation pre-loaded into RAM to optimize rendering threads
    precacheImage(const AssetImage('assets/images/logo.png'), context);
    precacheImage(const AssetImage('assets/images/mockup_1.png'), context);
    precacheImage(const AssetImage('assets/images/mockup_2.png'), context);
    precacheImage(const AssetImage('assets/images/mockup_3.png'), context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryGreen, 
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 76, height: 76,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.apartment_rounded, 
                      color: Colors.white, 
                      size: 40
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              "WORKACK",
              style: GoogleFonts.inter(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}