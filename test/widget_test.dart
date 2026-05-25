import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/main.dart';

void main() {
  // Required to mock native plugins (like SharedPreferences) in a test environment
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Sets up a "fake" memory for the test to use
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App builds and navigates from Splash to Onboarding', (WidgetTester tester) async {
    // 1. Build the app. 
    // THE FIX: Added 'isLoggedIn: false' to satisfy the new main.dart requirements!
    await tester.pumpWidget(const AttendanceApp(
      onboardingCompleted: false,
      isLoggedIn: false,
    ));

    // 2. Verify the Splash Screen is showing. 
    expect(find.byIcon(Icons.work_rounded), findsOneWidget);

    // 3. Advance time by 3 seconds to ensure the 2-second Splash timer finishes
    await tester.pump(const Duration(seconds: 3));
    
    // 4. Settle all animations (the transition between screens)
    await tester.pumpAndSettle();

    // 5. Verify the Splash screen icon is now gone
    expect(find.byIcon(Icons.work_rounded), findsNothing);
    
    // 6. Verify we have landed on the Onboarding Screen
    expect(find.text('Effortless Workforce\nManagement'), findsOneWidget);
    
    // 7. Verify the "Skip" button exists on the Onboarding Screen
    expect(find.text('Skip'), findsOneWidget);
  });
}