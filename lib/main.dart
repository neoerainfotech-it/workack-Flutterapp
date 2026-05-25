import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'constants.dart';
import 'onboarding_screen.dart';
import 'login_screen.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, 
  ));

  final prefs = await SharedPreferences.getInstance();
  final bool onboardingCompleted = prefs.getBool('onboardingCompleted') ?? false;
  
  // ADD THIS: Check if the user is already logged in
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  runApp(AttendanceApp(
    onboardingCompleted: onboardingCompleted, 
    isLoggedIn: isLoggedIn, // Pass it to the app
  ));
}

class AttendanceApp extends StatelessWidget {
  final bool onboardingCompleted;
  final bool isLoggedIn; // Add this variable
  
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
      // Pass both states to the Splash Screen
      home: SplashScreen(
        onboardingCompleted: onboardingCompleted,
        isLoggedIn: isLoggedIn,
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final bool onboardingCompleted;
  final bool isLoggedIn; // Add this variable

  const SplashScreen({
    super.key, 
    required this.onboardingCompleted,
    required this.isLoggedIn,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

// ... (your existing imports)

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) {
            if (widget.onboardingCompleted) {
              return widget.isLoggedIn ? const HomeScreen() : const LoginScreen();
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
    
    // This tells the phone to load these into RAM right now.
    // When the user hits the Onboarding/Login screens, they appear INSTANTLY.
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
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
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
                    // Graceful fallback if image still fails
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