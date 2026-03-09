import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  VOID — design system
//  Philosophy: "Tools should feel like tools." Raw, precise, functional.
//  Typography  : Outfit (headings/labels) + DM Mono (all data/values)
//  Base Palette: True black + surgical accent
//  Accent      : Emerald green (default) — 6 swappable options
// ═══════════════════════════════════════════════════════════════════════════════

enum AccentColor {
  emerald(Color(0xFF00E887), Color(0xFF00B865), 'Emerald'),
  sky    (Color(0xFF38CFFF), Color(0xFF0DAADF), 'Sky'),
  violet (Color(0xFFAB7BFF), Color(0xFF7C44FF), 'Violet'),
  amber  (Color(0xFFFFB700), Color(0xFFE09400), 'Amber'),
  rose   (Color(0xFFFF5E7D), Color(0xFFE02450), 'Rose'),
  ice    (Color(0xFFB8D4FF), Color(0xFF7AAEFF), 'Ice');

  final Color primary;
  final Color dark;
  final String label;
  const AccentColor(this.primary, this.dark, this.label);
  Color get main => primary;
}

// ─── Raw Palette ───────────────────────────────────────────────────────────────
class V {
  static const d0    = Color(0xFF000000);
  static const d1    = Color(0xFF0F0F0F);
  static const d2    = Color(0xFF1A1A1A);
  static const d3    = Color(0xFF242424);
  static const wire  = Color(0xFF2E2E2E);
  static const wire2 = Color(0xFF3C3C3C);
  static const hi    = Color(0xFFFFFFFF);
  static const mid   = Color(0xFF888888);
  static const lo    = Color(0xFF444444);

  static const l0    = Color(0xFFF8F8F8);
  static const l1    = Color(0xFFEEEEEE);
  static const l2    = Color(0xFFFFFFFF);
  static const l3    = Color(0xFFE5E5E5);
  static const lw    = Color(0xFFDDDDDD);
  static const lw2   = Color(0xFFCCCCCC);
  static const lhi   = Color(0xFF0A0A0A);
  static const lmid  = Color(0xFF555555);
  static const llo   = Color(0xFFAAAAAA);

  static const ok    = Color(0xFF00E887);
  static const warn  = Color(0xFFFFB700);
  static const err   = Color(0xFFFF3B3B);
  static const info  = Color(0xFF38CFFF);
}

// ─── Theme extension ──────────────────────────────────────────────────────────
class VC extends ThemeExtension<VC> {
  final Color bg, panel, elevated, input;
  final Color wire, wire2, hi, mid, lo;
  final Color accent;
  final bool dark;
  const VC({
    required this.bg, required this.panel, required this.elevated,
    required this.input, required this.wire, required this.wire2,
    required this.hi, required this.mid, required this.lo,
    required this.accent, required this.dark,
  });
  @override VC copyWith({
    Color? bg, Color? panel, Color? elevated, Color? input,
    Color? wire, Color? wire2, Color? hi, Color? mid, Color? lo,
    Color? accent, bool? dark,
  }) => VC(
    bg: bg??this.bg, panel: panel??this.panel, elevated: elevated??this.elevated,
    input: input??this.input, wire: wire??this.wire, wire2: wire2??this.wire2,
    hi: hi??this.hi, mid: mid??this.mid, lo: lo??this.lo,
    accent: accent??this.accent, dark: dark??this.dark,
  );
  @override VC lerp(VC? other, double t) => this;
}

// ─── Theme builder ─────────────────────────────────────────────────────────────
class VoidTheme {
  static ThemeData build(bool dark, AccentColor accent) {
    final a   = accent.primary;
    final bg  = dark ? V.d0   : V.l0;
    final pan = dark ? V.d1   : V.l2;
    final el  = dark ? V.d2   : V.l1;
    final inp = dark ? V.d3   : V.l3;
    final wr  = dark ? V.wire : V.lw;
    final wr2 = dark ? V.wire2: V.lw2;
    final t1  = dark ? V.hi   : V.lhi;
    final t2  = dark ? V.mid  : V.lmid;
    final t3  = dark ? V.lo   : V.llo;

    final tt = TextTheme(
      displayLarge:   GoogleFonts.outfit(fontSize:28, fontWeight:FontWeight.w800, color:t1, letterSpacing:-1.2),
      displayMedium:  GoogleFonts.outfit(fontSize:22, fontWeight:FontWeight.w700, color:t1, letterSpacing:-0.8),
      displaySmall:   GoogleFonts.outfit(fontSize:18, fontWeight:FontWeight.w700, color:t1, letterSpacing:-0.5),
      headlineMedium: GoogleFonts.outfit(fontSize:16, fontWeight:FontWeight.w700, color:t1),
      headlineSmall:  GoogleFonts.outfit(fontSize:14, fontWeight:FontWeight.w600, color:t1),
      titleLarge:     GoogleFonts.outfit(fontSize:15, fontWeight:FontWeight.w700, color:t1),
      titleMedium:    GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w600, color:t1),
      titleSmall:     GoogleFonts.outfit(fontSize:11, fontWeight:FontWeight.w600, color:t2, letterSpacing:0.4),
      bodyLarge:      GoogleFonts.dmMono(fontSize:14, fontWeight:FontWeight.w400, color:t2),
      bodyMedium:     GoogleFonts.dmMono(fontSize:12, fontWeight:FontWeight.w400, color:t2),
      bodySmall:      GoogleFonts.dmMono(fontSize:10, fontWeight:FontWeight.w400, color:t3),
      labelLarge:     GoogleFonts.dmMono(fontSize:12, fontWeight:FontWeight.w500, color:t1),
      labelMedium:    GoogleFonts.dmMono(fontSize:11, fontWeight:FontWeight.w500, color:t2),
      labelSmall:     GoogleFonts.dmMono(fontSize:9,  fontWeight:FontWeight.w400, color:t3),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: a, onPrimary: dark ? V.d0 : V.hi,
        secondary: accent.dark, onSecondary: V.hi,
        error: V.err, onError: V.hi,
        surface: pan, onSurface: t1,
        background: bg, onBackground: t1,
      ),
      textTheme: tt,
      cardTheme: CardTheme(color:pan, elevation:0, margin:EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius:BorderRadius.circular(12), side:BorderSide(color:wr))),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? V.d0 : V.l2, elevation:0,
        surfaceTintColor: Colors.transparent, centerTitle:false,
        titleTextStyle: GoogleFonts.outfit(fontSize:15, fontWeight:FontWeight.w700, color:t1),
        iconTheme: IconThemeData(color:t2, size:20),
        actionsIconTheme: IconThemeData(color:t2, size:20),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled:true, fillColor:inp,
        contentPadding: const EdgeInsets.symmetric(horizontal:14, vertical:14),
        border: OutlineInputBorder(borderRadius:BorderRadius.circular(10), borderSide:BorderSide(color:wr)),
        enabledBorder: OutlineInputBorder(borderRadius:BorderRadius.circular(10), borderSide:BorderSide(color:wr)),
        focusedBorder: OutlineInputBorder(borderRadius:BorderRadius.circular(10), borderSide:BorderSide(color:a, width:1.5)),
        errorBorder: OutlineInputBorder(borderRadius:BorderRadius.circular(10), borderSide:const BorderSide(color:V.err)),
        hintStyle: GoogleFonts.dmMono(color:t3, fontSize:12),
        labelStyle: GoogleFonts.outfit(color:t3, fontSize:12),
        prefixIconColor: t3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        backgroundColor:a, foregroundColor:dark?V.d0:V.hi,
        minimumSize:const Size(double.infinity, 50),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),
        elevation:0, textStyle:GoogleFonts.outfit(fontSize:14, fontWeight:FontWeight.w700),
      )),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        foregroundColor:a, textStyle:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w600),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor:t1, side:BorderSide(color:wr2),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),
        textStyle:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w600),
      )),
      dividerTheme: DividerThemeData(color:wr, thickness:1, space:1),
      dialogTheme: DialogTheme(
        backgroundColor:pan, surfaceTintColor:Colors.transparent,
        titleTextStyle:GoogleFonts.outfit(fontSize:16, fontWeight:FontWeight.w700, color:t1),
        contentTextStyle:GoogleFonts.dmMono(fontSize:12, color:t2),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:dark?V.d2:V.lhi,
        contentTextStyle:GoogleFonts.dmMono(color:Colors.white, fontSize:12),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),
        behavior:SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:pan, surfaceTintColor:Colors.transparent,
        shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      ),
      switchTheme: SwitchThemeData(
        thumbColor:WidgetStateProperty.resolveWith((s)=>s.contains(WidgetState.selected)?a:t3),
        trackColor:WidgetStateProperty.resolveWith((s)=>s.contains(WidgetState.selected)?a.withOpacity(0.3):wr2),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor:WidgetStateProperty.resolveWith((s)=>s.contains(WidgetState.selected)?a:null),
        side:BorderSide(color:wr2, width:1.5),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(4)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color:a),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor:a, foregroundColor:dark?V.d0:V.hi,
        elevation:0, shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color:el, surfaceTintColor:Colors.transparent,
        textStyle:GoogleFonts.outfit(fontSize:13, color:t1),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12), side:BorderSide(color:wr)),
      ),
      tabBarTheme: TabBarTheme(
        labelColor:a, unselectedLabelColor:t3, indicatorColor:a,
        labelStyle:GoogleFonts.outfit(fontSize:12, fontWeight:FontWeight.w700),
        unselectedLabelStyle:GoogleFonts.outfit(fontSize:12, fontWeight:FontWeight.w500),
        dividerColor:wr,
      ),
      extensions: [
        VC(bg:bg, panel:pan, elevated:el, input:inp, wire:wr, wire2:wr2,
           hi:t1, mid:t2, lo:t3, accent:a, dark:dark),
      ],
    );
  }
}

// ─── Backward-compat shims ─────────────────────────────────────────────────────
class AppColors extends ThemeExtension<AppColors> {
  final Color background, surface, cardBg, border, textPrimary, textSecondary, textMuted, accent;
  final bool isDark;
  const AppColors({
    required this.background, required this.surface, required this.cardBg,
    required this.border, required this.textPrimary, required this.textSecondary,
    required this.textMuted, required this.isDark, required this.accent,
  });
  @override AppColors copyWith({
    Color? background, Color? surface, Color? cardBg, Color? border,
    Color? textPrimary, Color? textSecondary, Color? textMuted,
    bool? isDark, Color? accent,
  }) => AppColors(
    background:background??this.background, surface:surface??this.surface,
    cardBg:cardBg??this.cardBg, border:border??this.border,
    textPrimary:textPrimary??this.textPrimary, textSecondary:textSecondary??this.textSecondary,
    textMuted:textMuted??this.textMuted, isDark:isDark??this.isDark, accent:accent??this.accent,
  );
  @override AppColors lerp(AppColors? other, double t) => this;
}

class AppTheme {
  static const Color success      = V.ok;
  static const Color warning      = V.warn;
  static const Color danger       = V.err;
  static const Color info         = V.info;
  static const Color primary      = V.ok;
  static const Color primaryLight = Color(0xFF002218);
  static const Color secondary    = Color(0xFF38CFFF);
  static const Color border       = V.wire;
  static const Color darkTxtSec   = V.mid;

  static ThemeData dark([AccentColor accent = AccentColor.emerald])  => _build(true,  accent);
  static ThemeData light([AccentColor accent = AccentColor.emerald]) => _build(false, accent);
  static ThemeData build(bool dark, AccentColor accent) => _build(dark, accent);

  static ThemeData _build(bool d, AccentColor accent) {
    final base = VoidTheme.build(d, accent);
    final vc = base.extension<VC>()!;
    return base.copyWith(extensions: [
      ...base.extensions.values,
      AppColors(
        background:vc.bg, surface:vc.panel, cardBg:vc.panel,
        border:vc.wire, textPrimary:vc.hi, textSecondary:vc.mid,
        textMuted:vc.lo, isDark:d, accent:vc.accent,
      ),
    ]);
  }
}

// ─── Primitive widgets ─────────────────────────────────────────────────────────
class Dot extends StatelessWidget {
  final Color color; final double size; final bool glow;
  const Dot({super.key, required this.color, this.size = 7, this.glow = true});
  @override Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: color, shape: BoxShape.circle,
      boxShadow: glow ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)] : null,
    ),
  );
}

class VCard extends StatelessWidget {
  final Widget child; final EdgeInsets? padding; final VoidCallback? onTap;
  final Color? bg; final bool accentBorder; final double radius;
  const VCard({super.key, required this.child, this.padding, this.onTap,
    this.bg, this.accentBorder = false, this.radius = 12});
  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    final c = bg ?? v.panel;
    final br = BorderRadius.circular(radius);
    return Material(color:c, borderRadius:br, child: InkWell(
      onTap:onTap, borderRadius:br,
      splashColor:v.accent.withOpacity(0.06), highlightColor:v.accent.withOpacity(0.03),
      child: Container(
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: br,
          border: accentBorder
            ? Border(left:BorderSide(color:v.accent, width:2), top:BorderSide(color:v.wire),
                right:BorderSide(color:v.wire), bottom:BorderSide(color:v.wire))
            : Border.all(color:v.wire),
        ),
        child: child,
      ),
    ));
  }
}

class Mono extends StatelessWidget {
  final String text; final double size; final Color? color; final FontWeight weight;
  const Mono(this.text, {super.key, this.size = 20, this.color, this.weight = FontWeight.w600});
  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Text(text, style: GoogleFonts.dmMono(fontSize:size, fontWeight:weight, color:color??v.hi));
  }
}

class Label extends StatelessWidget {
  final String text; final double size; final Color? color;
  final FontWeight weight; final double? spacing;
  const Label(this.text, {super.key, this.size=11, this.color, this.weight=FontWeight.w700, this.spacing});
  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Text(text, style: GoogleFonts.outfit(fontSize:size, fontWeight:weight,
      color:color??v.hi, letterSpacing:spacing));
  }
}

class SectionHeader extends StatelessWidget {
  final String title; final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});
  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Row(children: [
      Text(title, style:GoogleFonts.outfit(fontSize:10, fontWeight:FontWeight.w700,
        color:v.lo, letterSpacing:1.5)),
      const Spacer(),
      if (trailing != null) trailing!,
    ]);
  }
}

class Badge extends StatelessWidget {
  final String text; final Color? color; final double size;
  const Badge(this.text, {super.key, this.color, this.size = 9});
  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    final a = color ?? v.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal:7, vertical:2),
      decoration: BoxDecoration(
        color: a.withOpacity(0.08), borderRadius: BorderRadius.circular(4),
        border: Border.all(color: a.withOpacity(0.22))),
      child: Text(text, style:GoogleFonts.outfit(fontSize:size, fontWeight:FontWeight.w700, color:a)),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child; final EdgeInsets? padding; final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding, this.onTap});
  @override Widget build(BuildContext context) =>
    VCard(onTap:onTap, padding:padding, child:child);
}
