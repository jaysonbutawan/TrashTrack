import 'package:flutter/material.dart';

/// Colors of the app: forest green on recycled-paper white, with kraft
/// (sack-brown) as the accent. Large text and big touch targets — some
/// users are not tech-savvy.
abstract final class Brand {
  static const forest = Color(0xFF1E5631);
  static const forestDark = Color(0xFF143D22);
  static const leaf = Color(0xFF4C9A2A);
  static const mint = Color(0xFFE4F1DF);
  static const kraft = Color(0xFFB7792F);
  static const kraftLight = Color(0xFFF6EBDA);
  static const paper = Color(0xFFF7F5EF);
  static const card = Colors.white;
  static const ink = Color(0xFF17251C);
  static const inkSoft = Color(0xFF5A6A5F);
  static const line = Color(0xFFE3DFD3);
  static const danger = Color(0xFFC62828);

  static const available = Color(0xFF2E7D32);
  static const reserved = Color(0xFFC46A00);
  static const collected = Color(0xFF546E7A);
  static const forSale = Color(0xFF3949AB);
  static const free = Color(0xFF00897B);
  static const star = Color(0xFFF2A100);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.forest,
    primary: Brand.forest,
    secondary: Brand.kraft,
    surface: Brand.card,
    onSurface: Brand.ink,
    onSurfaceVariant: Brand.inkSoft,
    outline: Brand.line,
    error: Brand.danger,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  // Typography.englishLike gives sizes, but its styles have inherit: false,
  // so colors must be applied explicitly afterwards — otherwise some widgets
  // (chips, dropdowns) get text with no color.
  final bigText = base.typography.englishLike
      .merge(base.textTheme)
      .apply(
        fontSizeFactor: 1.15,
        bodyColor: Brand.ink,
        displayColor: Brand.ink,
      );
  const buttonText = TextStyle(fontSize: 19, fontWeight: FontWeight.w700);
  const buttonSize = Size.fromHeight(58);
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Brand.line, width: 1.5),
  );

  return base.copyWith(
    scaffoldBackgroundColor: Brand.paper,
    textTheme: bigText,
    appBarTheme: AppBarTheme(
      backgroundColor: Brand.paper,
      foregroundColor: Brand.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: bigText.titleLarge?.copyWith(
        color: Brand.ink,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: Brand.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Brand.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonSize,
        textStyle: buttonText,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        textStyle: buttonText,
        shape: buttonShape,
        foregroundColor: Brand.forest,
        side: const BorderSide(color: Brand.forest, width: 1.8),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Brand.forest,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.card,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
        borderSide: const BorderSide(color: Brand.forest, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: const TextStyle(fontSize: 18, color: Brand.inkSoft),
      hintStyle: const TextStyle(fontSize: 17, color: Brand.inkSoft),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Brand.card,
      selectedColor: Brand.mint,
      checkmarkColor: Brand.forest,
      side: const BorderSide(color: Brand.line, width: 1.5),
      labelStyle: const TextStyle(
        fontSize: 16,
        color: Brand.ink,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        fontSize: 16,
        color: Brand.forest,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Brand.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.card,
      indicatorColor: Brand.mint,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Brand.line, space: 1),
  );
}
