import 'package:flutter/material.dart';

// Brand Colors
const Color kPrimaryGreen = Color(0xFF006B3C); 
const Color kSecondaryGreen = Color(0xFF008A4E); 
const Color kMilkWhite = Color(0xFFFFFAFA); 
const Color kTextDark = Color(0xFF1E293B); 
const Color kTextMuted = Color(0xFF94A3B8); 

// Shared Decorations
InputDecoration buildInputDecoration({required String hint, required IconData prefixIcon, Widget? suffixIcon}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0x8094A3B8), fontWeight: FontWeight.w400),
    prefixIcon: Icon(prefixIcon, color: kPrimaryGreen, size: 20),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: kPrimaryGreen, width: 2),
    ),
  );
}