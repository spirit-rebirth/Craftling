import 'package:flutter/material.dart';

ThemeData buildCraftlingTheme() {
  const sand = Color(0xFFF5EFE6);
  const ink = Color(0xFF1E2430);

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: sand,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF1C5C54),
      secondary: Color(0xFFC66A3D),
      surface: Color(0xFFFFFBF6),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: ink,
    ),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
      fontFamily: 'Georgia',
    ),
  );
}
