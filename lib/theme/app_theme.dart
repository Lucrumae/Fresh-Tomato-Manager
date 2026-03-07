import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Accent colors user can pick ────────────────────────────────────────────────
enum AccentColor {
  green  (Color(0xFF00E5A0), Color(0xFF00B87A), 'Hijau'),
  blue   (Color(0xFF4F7EFF), Color(0xFF2D5FE0), 'Biru'),
  orange (Color(0xFFFF8C00), Color(0xFFE67300), 'Oranye'),
  red    (Color(0xFFEF4444), Color(0xFFCC2222), 'Merah'),
  purple (Color(0xFF9B59FC), Color(0xFF7B3FDC), 'Ungu'),
  pink   (Color(0xFFFF6B9D), Color(0xFFE0417A), 'Pink'),
  yellow (Color(0xFFF59E0B), Color(0xFFD4850A), 'Kuning');

  final Color main;
  final Color dark;
  final String label;
  const AccentColor(this.main, this.dark, this.label);
}

class AppTheme {
  // ── Light palette ──────────────────────────────────────────────────────────
  static const Color background    = Color(0xFFF5F6FA);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color cardBg        = Color(0xFFFFFFFF);
  static const Color border        = Color(0xFFE8EAF0);
  static const Color textPrimary   = Color(0xFF1A1D2E);
  static const Color textSecondary = Color(0xFF4A5068);
  static const Color textMuted     = Color(0xFF9399B0);

  // ── Dark palette ───────────────────────────────────────────────────────────
  static const Color darkBackground    = Color(0xFF0F1117);
  static const Color darkSurface       = Color(0xFF1A1D2E);
  static const Color darkCardBg        = Color(0xFF1E2235);
  static const Color darkBorder        = Color(0xFF2A2E45);
  static const Color darkTextPrimary   = Color(0xFFEDEFF7);
  static const Color darkTextSecondary = Color(0xFF8A90AA);
  static const Color darkTextMuted     = Color(0xFF555A72);

  // ── Brand / status (static, not accent-dependent) ─────────────────────────
  static const Color primary      = Color(0xFF4F7EFF);
  static const Color primaryLight = Color(0xFFEEF2FF);
  static const Color secondary    = Color(0xFF7C5CFC);
  static const Color success      = Color(0xFF22C55E);
  static const Color warning      = Color(0xFFF59E0B);
  static const Color danger       = Color(0xFFEF4444);

  // Default accent color (const fallback)
  static const Color terminal = Color(0xFF00E5A0);

  // ── Build theme with a given accent ──────────────────────────────────────
  static ThemeData light([AccentColor accent = AccentColor.green]) =>
      _build(false, accent);
  static ThemeData dark([AccentColor accent = AccentColor.green]) =>
      _build(true, accent);

  static ThemeData _build(bool isDark, AccentColor accent) {
    final bg     = isDark ? darkBackground    : background;
    final surf   = isDark ? darkSurface       : surface;
    final card   = isDark ? darkCardBg        : cardBg;
    final bord   = isDark ? darkBorder        : border;
    final txtPri = isDark ? darkTextPrimary   : textPrimary;
    final txtSec = isDark ? darkTextSecondary : textSecondary;
    final txtMut = isDark ? darkTextMuted     : textMuted;
    final acc    = accent.main;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: acc, onPrimary: Colors.white,
        secondary: secondary, onSecondary: Colors.white,
        error: danger, onError: Colors.white,
        surface: surf, onSurface: txtPri,
        background: bg, onBackground: txtPri,
      ),
      scaffoldBackgroundColor: bg,
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge:  GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, color: txtPri),
        displayMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, color: txtPri),
        titleLarge:    GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: txtPri),
        titleMedium:   GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: txtPri),
        titleSmall:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: txtPri),
        bodyLarge:     GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w400, color: txtSec),
        bodyMedium:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: txtSec),
        bodySmall:     GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: txtMut),
        labelLarge:    GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: txtPri),
      ),
      cardTheme: CardTheme(
        color: card, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: bord),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surf, elevation: 0, centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: txtPri),
        iconTheme: IconThemeData(color: txtPri),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: isDark ? darkCardBg : const Color(0xFFF8F9FE),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: bord),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: bord),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: acc, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(color: txtMut, fontSize: 14),
        prefixIconColor: txtMut,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: acc, foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      dividerTheme: DividerThemeData(color: bord, thickness: 1),
      dialogTheme: DialogTheme(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17, fontWeight: FontWeight.w600, color: txtPri),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14, color: txtSec),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        textStyle: GoogleFonts.inter(fontSize: 14, color: txtPri),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: bord),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1E2235) : const Color(0xFF1A1D2E),
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surf,
        surfaceTintColor: Colors.transparent,
        indicatorColor: acc.withOpacity(0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: acc, size: 22);
          }
          return IconThemeData(color: txtMut, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: acc);
          }
          return GoogleFonts.inter(fontSize: 10, color: txtMut);
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? acc : null),
        trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? acc.withOpacity(0.4) : null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? acc : null),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? acc : null),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: acc,
        selectionColor: acc.withOpacity(0.3),
        selectionHandleColor: acc,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: acc),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: acc,
        foregroundColor: Colors.white,
      ),
      extensions: [
        AppColors(
          background: bg, surface: surf, cardBg: card, border: bord,
          textPrimary: txtPri, textSecondary: txtSec, textMuted: txtMut,
          isDark: isDark, accent: acc,
        )
      ],
    );
  }
}

// ── Theme extension ────────────────────────────────────────────────────────────
class AppColors extends ThemeExtension<AppColors> {
  final Color background, surface, cardBg, border;
  final Color textPrimary, textSecondary, textMuted;
  final Color accent;
  final bool isDark;

  const AppColors({
    required this.background, required this.surface,
    required this.cardBg, required this.border,
    required this.textPrimary, required this.textSecondary,
    required this.textMuted, required this.isDark,
    required this.accent,
  });

  @override
  AppColors copyWith({
    Color? background, Color? surface, Color? cardBg, Color? border,
    Color? textPrimary, Color? textSecondary, Color? textMuted,
    bool? isDark, Color? accent,
  }) => AppColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    cardBg: cardBg ?? this.cardBg,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    isDark: isDark ?? this.isDark,
    accent: accent ?? this.accent,
  );

  @override
  AppColors lerp(AppColors? other, double t) => this;
}

// ── Reusable card widget ───────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    return Material(
      color: c.cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}
