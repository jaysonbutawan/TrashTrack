import 'package:flutter/material.dart';

/// Large text and big touch targets — some collectors are not tech-savvy.
ThemeData buildTheme() {
  const green = Color(0xFF2E7D32);
  final scheme = ColorScheme.fromSeed(seedColor: green, primary: green);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  final bigText = base.textTheme.apply(fontSizeFactor: 1.15);
  const buttonText = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
  const buttonSize = Size.fromHeight(60);
  final buttonShape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return base.copyWith(
    textTheme: bigText,
    appBarTheme: AppBarTheme(
      backgroundColor: green,
      foregroundColor: Colors.white,
      titleTextStyle: bigText.titleLarge
          ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          minimumSize: buttonSize, textStyle: buttonText, shape: buttonShape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        textStyle: buttonText,
        shape: buttonShape,
        side: const BorderSide(color: green, width: 2),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: TextStyle(fontSize: 18),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: const TextStyle(fontSize: 17),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    ),
  );
}
