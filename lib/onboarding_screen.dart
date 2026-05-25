import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'login_screen.dart'; // Must import this to navigate!

class OnboardingContent {
  final String image;
  final String title;
  final String description;

  OnboardingContent({
    required this.image,
    required this.title,
    required this.description,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late PageController _controller;
  double _currentPage = 0;

  final List<OnboardingContent> contents = [
    OnboardingContent(
      image: 'assets/images/mockup_1.png',
      title: 'Effortless Workforce\nManagement',
      description: 'Automate daily check-ins and manage your team efficiently.',
    ),
    OnboardingContent(
      image: 'assets/images/mockup_2.png', // Change to mockup_2.png if you have it
      title: 'Precision in Every\nData Point',
      description: 'Monitor real-time attendance and track leave balances easily.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _controller.addListener(() {
      setState(() {
        _currentPage = _controller.page ?? 0;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingCompleted', true);
    if (!mounted) return;
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()), 
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9), // A light premium grey to blend with the mockup background
      body: Stack(
        children: [
          // LAYER 1: Full Bleed Hero Image (Takes exactly 65% of the screen height)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.65, // THE FIX: Explicitly sizing the image area
            child: PageView.builder(
              controller: _controller,
              itemCount: contents.length,
              itemBuilder: (_, i) {
                double scale = 1.0;
                // Prevents layout errors before the controller is fully attached
                if (_controller.hasClients) {
                  scale = (1 - (_currentPage - i).abs() * 0.15).clamp(0.85, 1.0);
                }
                
                return Transform.scale(
                  scale: scale,
                  child: Image.asset(
                    contents[i].image,
                    fit: BoxFit.fitWidth, // THE FIX: Forces the image to touch the left and right edges!
                    alignment: Alignment.bottomCenter, // THE FIX: Anchors the image down so it meets the white card
                    errorBuilder: (c, e, s) => const Icon(Icons.image_not_supported, size: 50, color: kTextMuted),
                  ),
                );
              },
            ),
          ),

          // LAYER 2: Skip Button (Safely pushed down from the notch)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 20,
            child: TextButton(
              onPressed: _completeOnboarding,
              child: Text(
                "Skip",
                style: GoogleFonts.inter(
                  color: kTextDark.withValues(alpha: 0.6), 
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),

          // LAYER 3: Sleek Bottom Content Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(24, 32, 24, MediaQuery.of(context).padding.bottom + 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(40)), // Cleaner radius declaration
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05), 
                    blurRadius: 30, 
                    offset: const Offset(0, -10), // Projects a soft shadow upward onto the image
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min, // THE FIX: Forces the card to wrap tightly around the text
                children: [
                  // Animated Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      contents.length,
                      (index) => buildDot(index),
                    ),
                  ),
                  const SizedBox(height: 32), 
                  
                  // Text Content
                  Text(
                    contents[_currentPage.round()].title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 26, 
                      fontWeight: FontWeight.w800,
                      color: kTextDark,
                      height: 1.2,
                      letterSpacing: -0.5, // Premium typography touch
                    ),
                  ),
                  const SizedBox(height: 12), 
                  Text(
                    contents[_currentPage.round()].description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: kTextMuted,
                      height: 1.5,
                    ),
                  ),
                  
                  const SizedBox(height: 40), 

                  // Gradient Button
                  SizedBox(
                    width: double.infinity,
                    height: 56, 
                    child: ElevatedButton(
                      onPressed: () {
                        if (_currentPage.round() == contents.length - 1) {
                          _completeOnboarding();
                        } else {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutQuart, 
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 5,
                        shadowColor: kPrimaryGreen.withValues(alpha: 0.3), 
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [kPrimaryGreen, kSecondaryGreen]),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: Text(
                            _currentPage.round() == contents.length - 1 ? "Get Started" : "Next",
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 6, 
      width: _currentPage.round() == index ? 24 : 6,
      decoration: BoxDecoration(
        color: _currentPage.round() == index ? kPrimaryGreen : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}