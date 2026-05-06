import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ShieldColors {
  static const Color activeTeal = Color(0xFF007F80);
  static const Color safeZoneGreen = Color(0xFF059669);
  static const Color urgentRed = Color(0xFFDC2626);
  static const Color alertRed = Color(0xFFDC2626); // alias for urgentRed
  static const Color nightIndigo = Color(0xFF312E81);
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF3F4F6);
  static const Color softMint = Color(0xFFE6F4F2);

  static const Color textBody = Color(0xFF1F2937);
  static const Color textLabel = Color(0xFF374151);
  static const Color tealWash = Color(0x11007F80);
}

class ShieldDesign {
  static const double borderRadius = 12.0;
  static const BorderRadius roundedTwelve = BorderRadius.all(
    Radius.circular(borderRadius),
  );

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ShieldColors.activeTeal,
      primary: ShieldColors.activeTeal,
      secondary: ShieldColors.nightIndigo,
      surface: ShieldColors.backgroundWhite,
      error: ShieldColors.urgentRed,
    ),
    scaffoldBackgroundColor: ShieldColors.backgroundWhite,
    textTheme: GoogleFonts.interTextTheme().copyWith(
      bodyLarge: GoogleFonts.inter(color: ShieldColors.textBody),
      bodyMedium: GoogleFonts.inter(color: ShieldColors.textBody),
      labelMedium: GoogleFonts.inter(color: ShieldColors.textLabel),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ShieldColors.activeTeal,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: roundedTwelve),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: const CardThemeData(
      color: ShieldColors.backgroundWhite,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: roundedTwelve),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: roundedTwelve),
      filled: true,
      fillColor: Colors.white,
    ),
  );
}
