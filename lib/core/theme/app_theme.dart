import 'package:flutter/material.dart';

class AppTheme {
  // Color palette - Modern AgriTech
  static const Color primaryGreen = Color(0xFF00A36C); // Jade Green - Vibrant & Modern
  static const Color primaryGreenLight = Color(0xFFE8F5E9); // Very light tint for backgrounds
  static const Color primaryGreenDark = Color(0xFF006940); // Deep contrast
  
  static const Color secondaryTeal = Color(0xFF00897B); // Teal 600
  static const Color accentOrange = Color(0xFFFF9800); // For warnings/delays

  static const Color backgroundLight = Color(0xFFF8F9FB); // Cool light grey, cleaner than cream
  static const Color cardWhite = Colors.white;
  
  static const Color textPrimary = Color(0xFF1A1C1E); // Soft black
  static const Color textSecondary = Color(0xFF42474E); // Dark grey
  static const Color textTertiary = Color(0xFF72777F); // Light grey

  static const Color warningRed = Color(0xFFBA1A1A);
  static const Color successGreen = Color(0xFF006D44);

  // Status colors
  static const Color statusScheduled = Color(0xFFB96C15); 
  static const Color statusUpcoming = Color(0xFFD88C00); 
  static const Color statusOngoing = Color(0xFF00A36C); 
  static const Color statusPlanned = Color(0xFF006590); 
  static const Color statusCompleted = Color(0xFF006D42); 
  static const Color statusDelayed = Color(0xFFBA1A1A); 

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        secondary: secondaryTeal,
        tertiary: accentOrange,
        surface: backgroundLight,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        error: warningRed,
      ),
      scaffoldBackgroundColor: backgroundLight,
      fontFamily: 'Inter', // Assuming standard system font if Inter not linked, but cleaner setup

      // AppBar theme - Clean & Minimal
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: backgroundLight, // Transparent/Light feel
        foregroundColor: textPrimary,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        surfaceTintColor: Colors.transparent,
      ),

      // Card theme - Soft & Floating
      cardTheme: CardThemeData(
        elevation: 0, // Flat by default, we use shadows manually or outline
        color: cardWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Input decoration theme - Filled & Soft
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none, // Clean look
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: warningRed, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: warningRed, width: 2),
        ),
        hintStyle: TextStyle(color: textTertiary),
      ),

      // Elevated button theme - Pill shape & Vibrant
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100), // Pill shape
          ),
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          shadowColor: primaryGreen.withValues(alpha: 0.4),
        ),
      ),

      // Outlined button theme
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
           shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
          side: const BorderSide(color: primaryGreen),
          foregroundColor: primaryGreen,
          textStyle: const TextStyle(
             fontSize: 16,
             fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryGreen,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          splashFactory: NoSplash.splashFactory,
        ),
      ),

      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
      ),
      
      dividerTheme: DividerThemeData(
        color: Colors.grey.withValues(alpha: 0.2),
        thickness: 1,
      ),

      // Text theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -1.0,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: textSecondary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: textSecondary,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: textTertiary,
        ),
      ),
    );
  }

  // Helper method to get status color
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return statusScheduled;
      case 'upcoming':
        return statusUpcoming;
      case 'ongoing':
        return statusOngoing;
      case 'planned':
        return statusPlanned;
      case 'completed':
        return statusCompleted;
      case 'delayed':
        return statusDelayed;
      default:
        return textTertiary;
    }
  }
}
