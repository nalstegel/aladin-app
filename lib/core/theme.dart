import 'package:flutter/material.dart';

import '../models/enums.dart';

/// Barvna shema aplikacije. Statusi imajo fiksne barve, da jih delavec
/// prepozna že po pogledu, brez branja.
class AppColors {
  static const primary = Color(0xFF2563EB);
  static const surface = Color(0xFFF6F7F9);
  static const card = Colors.white;
  static const border = Color(0xFFE4E7EC);
  static const textMuted = Color(0xFF667085);

  static const awaitingPickup = Color(0xFF7C3AED);
  static const awaitingWash = Color(0xFFF59E0B);
  static const drying = Color(0xFF0EA5E9);
  static const finishing = Color(0xFF8B5CF6);
  static const ready = Color(0xFF16A34A);
  static const returned = Color(0xFF64748B);
  static const danger = Color(0xFFDC2626);

  static Color forRug(RugStatus s) => switch (s) {
        RugStatus.awaitingPickup => awaitingPickup,
        RugStatus.awaitingWash => awaitingWash,
        RugStatus.drying => drying,
        RugStatus.finishing => finishing,
        RugStatus.ready => ready,
        RugStatus.returned => returned,
      };

  static Color forOrder(OrderStatus s) => switch (s) {
        OrderStatus.scheduledPickup => awaitingPickup,
        OrderStatus.inProduction => awaitingWash,
        OrderStatus.awaitingCollection => ready,
        OrderStatus.awaitingDelivery => ready,
        OrderStatus.completed => returned,
        OrderStatus.cancelled => danger,
      };

  static Color forChannel(OrderChannel c) => switch (c) {
        OrderChannel.delivery => primary,
        OrderChannel.dropoff => const Color(0xFF0891B2),
        OrderChannel.b2b => const Color(0xFF7C3AED),
      };
}

class AppIcons {
  static IconData forRug(RugStatus s) => switch (s) {
        RugStatus.awaitingPickup => Icons.local_shipping_outlined,
        RugStatus.awaitingWash => Icons.water_drop_outlined,
        RugStatus.drying => Icons.air,
        RugStatus.finishing => Icons.straighten,
        RugStatus.ready => Icons.check_circle,
        RugStatus.returned => Icons.assignment_turned_in_outlined,
      };

  static IconData forChannel(OrderChannel c) => switch (c) {
        OrderChannel.delivery => Icons.local_shipping_outlined,
        OrderChannel.dropoff => Icons.storefront_outlined,
        OrderChannel.b2b => Icons.apartment_outlined,
      };
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(surface: AppColors.surface),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Color(0xFF101828),
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: Color(0xFF101828)),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.border),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
  );
}
