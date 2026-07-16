import 'package:flutter/material.dart';

/// Central app theme. Change the seed color here to restyle the whole app.
abstract final class AppTheme {
  static const Color seedColor = Color(0xFF00695C); // calm clinical teal

  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      );
}
