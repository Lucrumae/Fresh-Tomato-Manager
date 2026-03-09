import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Accent colors ──────────────────────────────────────────────────────────────
enum AccentColor {
  cyan   (Color(0xFF00D9F5), Color(0xFF00A8C0), 'Cyan'),
  green  (Color(0xFF00E5A0), Color(0xFF00B87A), 'Green'),
  violet (Color(0xFF9B59FC), Color(0xFF7B3FDC), 'Violet'),
  amber  (Color(0xFFF59E0B), Color(0xFFD4850A), 'Amber'),
  rose   (Color(0xFFFF6B9D), Color(0xFFE0417A), 'Rose'),
  blue   (Color(0xFF4F7EFF), Color(0xFF2D5FE0), 'Blue'),
  orange (Color(0xFFFF8C00), Color(0xFFE67300), 'Orange');

  final Color main;
  final Color dark;
  final String label;
  const AccentColor(this.main, this.dark, this.label);
}

class AppTheme {
  static const Color darkBg        = Color(0xFF080B10);
  static const Color darkSurface   = Color(0xFF0E1117);
  static const Color darkCard      = Color(0xFF111620);
  static const Color darkCard2     = Color(0xFF161B28);
  static const Color darkBorder    = Color(0xFF1E2535);
  static const Color darkBorder2   = Color(0xFF252D40);
  static const Color darkTxtPri    = Color(0xFFEDF0F9);
  static const Color darkTxtSec    = Color(0xFF7D8BAA);
  static const Color darkTxtMuted  = Color(0xFF424D65);

  static const Color lightBg       = Color(0xFFF0F2F8);
  static const Color lightSurface  = Color(0xFFFFFFFF);
  static const Color lightCard     = Color(0xFFFFFFFF);
  static const Color lightCard2    = Color(0xFFF8FAFF);
  static const Color lightBorder   = Color(0xFFE2E6F0);
  static const Color lightBorder2  = Color(0xFFD0D6E8);
  static const Color lightTxtPri   = Color(0xFF0D1117);
  static const Color lightTxtSec   = Color(0xFF4A5580);
  static const Color lightTxtMuted = Color(0xFF8E9AB8);

  static const Color success = Color(0xFF00D97E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger  = Color(0xFFFF4D6A);
  static const Color info    = Color(0xFF4F9EE8);
  static const Color primary = Color(0xFF4F7EFF);
  static const Color secondary = Color(0xFF7C5CFC);
  static const Color border = Color(0xFF1E2535);
  static const Color primaryLight = Color(0xFF1A2440);

  static ThemeData dark([AccentColor accent = AccentColor.cyan]) => _build(true, accent);
  static ThemeData light([AccentColor accent = AccentColor.cyan]) => _build(false, accent);

  static ThemeData _build(bool isDark, AccentColor accent) {
    final bg   = isDark ? darkBg       : lightBg;
    final surf = isDark ? darkSurface  : lightSurface;
    final card = isDark ? darkCard     : lightCard;
    final bord = isDark ? darkBorder   : lightBorder;
    final txtP = isDark ? darkTxtPri   : lightTxtPri;
    final txtS = isDark ? darkTxtSec   : lightTxtSec;
    final txtM = isDark ? darkTxtMuted : lightTxtMuted;
    final acc  = accent.main;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: acc, onPrimary: isDark ? Colors.black : Colors.white,
        secondary: accent.dark, onSecondary: Colors.white,
        error: danger, onError: Colors.white,
        surface: surf, onSurface: txtP,
        background: bg, onBackground: txtP,
      ),
      scaffoldBackgroundColor: bg,
      textTheme: TextTheme(
        displayLarge:  GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.w700, color: txtP, letterSpacing: -0.5),
        displayMedium: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.w700, color: txtP, letterSpacing: -0.3),
        titleLarge:    GoogleFonts.spaceGrotesk(fontSize: 17, fontWeight: FontWeight.w700, color: txtP, letterSpacing: -0.2),
        titleMedium:   GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w600, color: txtP),
        titleSmall:    GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w600, color: txtP),
        bodyLarge:     GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w400, color: txtS),
        bodyMedium:    GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w400, color: txtS),
        bodySmall:     GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w400, color: txtM),
        labelLarge:    GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w500, color: txtP),
        labelMedium:   GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: txtS),
        labelSmall:    GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.w400, color: txtM),
      ),
      cardTheme: CardTheme(
        color: card, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: bord),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surf, elevation: 0, centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.spaceGrotesk(fontSize: 17, fontWeight: FontWeight.w700, color: txtP, letterSpacing: -0.2),
        iconTheme: IconThemeData(color: txtS, size: 20),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0E1117) : const Color(0xFFF4F6FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: bord)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: bord)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: acc, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: GoogleFonts.spaceGrotesk(color: txtM, fontSize: 13),
        labelStyle: GoogleFonts.spaceGrotesk(color: txtM, fontSize: 12),
        prefixIconColor: txtM,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: acc, foregroundColor: isDark ? Colors.black : Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
      dividerTheme: DividerThemeData(color: bord, thickness: 1, space: 1),
      dialogTheme: DialogTheme(
        backgroundColor: card, surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: txtP),
        contentTextStyle: GoogleFonts.spaceGrotesk(fontSize: 13, color: txtS),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card, surfaceTintColor: Colors.transparent,
        textStyle: GoogleFonts.spaceGrotesk(fontSize: 13, color: txtP),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: bord)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF161B28) : const Color(0xFF0D1117),
        contentTextStyle: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surf, surfaceTintColor: Colors.transparent,
        indicatorColor: acc.withOpacity(0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return IconThemeData(color: acc, size: 21);
          return IconThemeData(color: txtM, size: 21);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected))
            return GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w700, color: acc);
          return GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w500, color: txtM);
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? acc : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? acc.withOpacity(0.35) : null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? acc : null),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? acc : null),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: acc, selectionColor: acc.withOpacity(0.25), selectionHandleColor: acc,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: acc),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: acc, foregroundColor: isDark ? Colors.black : Colors.white,
        elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      extensions: [
        AppColors(
          background: bg, surface: surf, cardBg: card,
          card2: isDark ? darkCard2 : lightCard2,
          border: bord, border2: isDark ? darkBorder2 : lightBorder2,
          textPrimary: txtP, textSecondary: txtS, textMuted: txtM,
          isDark: isDark, accent: acc,
        )
      ],
    );
  }
}

class AppColors extends ThemeExtension<AppColors> {
  final Color background, surface, cardBg, card2, border, border2;
  final Color textPrimary, textSecondary, textMuted;
  final Color accent;
  final bool isDark;

  const AppColors({
    required this.background, required this.surface,
    required this.cardBg, required this.card2,
    required this.border, required this.border2,
    required this.textPrimary, required this.textSecondary,
    required this.textMuted, required this.isDark, required this.accent,
  });

  @override
  AppColors copyWith({
    Color? background, Color? surface, Color? cardBg, Color? card2,
    Color? border, Color? border2,
    Color? textPrimary, Color? textSecondary, Color? textMuted,
    bool? isDark, Color? accent,
  }) => AppColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    cardBg: cardBg ?? this.cardBg,
    card2: card2 ?? this.card2,
    border: border ?? this.border,
    border2: border2 ?? this.border2,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    isDark: isDark ?? this.isDark,
    accent: accent ?? this.accent,
  );

  @override
  AppColors lerp(AppColors? other, double t) => this;
}

// ── Shared Widgets ─────────────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.color, this.radius = 14});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final bg = color ?? c.cardBg;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: c.accent.withOpacity(0.07),
        highlightColor: c.accent.withOpacity(0.03),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: c.border),
          ),
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool glow;
  const StatusDot({super.key, required this.color, this.size = 7, this.glow = true});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: color, shape: BoxShape.circle,
      boxShadow: glow ? [BoxShadow(color: color.withOpacity(0.55), blurRadius: 6, spreadRadius: 1)] : null,
    ),
  );
}

class MonoValue extends StatelessWidget {
  final String value;
  final double fontSize;
  final Color? color;
  final FontWeight weight;
  const MonoValue(this.value, {super.key, this.fontSize = 20, this.color, this.weight = FontWeight.w700});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).extension<AppColors>()!.textPrimary;
    return Text(value, style: GoogleFonts.jetBrainsMono(fontSize: fontSize, fontWeight: weight, color: c));
  }
}

class TagBadge extends StatelessWidget {
  final String text;
  final Color? color;
  const TagBadge(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final acc = color ?? Theme.of(context).extension<AppColors>()!.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: acc.withOpacity(0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: acc.withOpacity(0.22)),
      ),
      child: Text(text,
        style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w700, color: acc)),
    );
  }
}
