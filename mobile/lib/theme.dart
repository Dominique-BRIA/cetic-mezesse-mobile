import 'package:flutter/material.dart';

// Mêmes couleurs que le client web (dépôt cetic-mezesse-web, src/styles.css).
class Couleurs extends ThemeExtension<Couleurs> {
  const Couleurs({
    required this.fond,
    required this.motif,
    required this.surface2,
    required this.bord,
    required this.encre2,
    required this.encre3,
    required this.primairePale,
    required this.succes,
    required this.danger,
    required this.alerte,
    required this.serie1,
    required this.serie2,
    required this.grille,
  });

  final Color fond, motif, surface2, bord, encre2, encre3, primairePale, succes, danger, alerte, serie1, serie2, grille;

  static const clair = Couleurs(
    fond: Color(0xFFCFE5F5),
    motif: Color(0xFF96C0E2),
    surface2: Color(0xFFF4F8FC),
    bord: Color(0xFFD6E1EC),
    encre2: Color(0xFF4E5D70),
    encre3: Color(0xFF7A899B),
    primairePale: Color(0xFFE4EFFA),
    succes: Color(0xFF1E764C),
    danger: Color(0xFFB3261E),
    alerte: Color(0xFF9A5A00),
    serie1: Color(0xFF1F5FA8),
    serie2: Color(0xFFC8641C),
    grille: Color(0xFFE3EAF1),
  );

  static const sombre = Couleurs(
    fond: Color(0xFF0C1826),
    motif: Color(0xFF1D324A),
    surface2: Color(0xFF19293C),
    bord: Color(0xFF273A51),
    encre2: Color(0xFFA0B1C4),
    encre3: Color(0xFF74869C),
    primairePale: Color(0xFF1C324C),
    succes: Color(0xFF5CC48C),
    danger: Color(0xFFF0786E),
    alerte: Color(0xFFE6AA50),
    serie1: Color(0xFF4A8AD2),
    serie2: Color(0xFFD27A2C),
    grille: Color(0xFF22364D),
  );

  @override
  Couleurs copyWith() => this;

  @override
  Couleurs lerp(Couleurs? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension CouleursContexte on BuildContext {
  Couleurs get c => Theme.of(this).extension<Couleurs>()!;
}

ThemeData construireTheme(Brightness b) {
  final sombre = b == Brightness.dark;
  final c = sombre ? Couleurs.sombre : Couleurs.clair;
  final primaire = sombre ? const Color(0xFF6AA8EA) : const Color(0xFF1D5FA8);
  final surface = sombre ? const Color(0xFF142131) : Colors.white;
  final encre = sombre ? const Color(0xFFE2EAF3) : const Color(0xFF14202E);
  final schema = ColorScheme(
    brightness: b,
    primary: primaire,
    onPrimary: sombre ? const Color(0xFF0C1826) : Colors.white,
    secondary: primaire,
    onSecondary: sombre ? const Color(0xFF0C1826) : Colors.white,
    error: c.danger,
    onError: Colors.white,
    surface: surface,
    onSurface: encre,
    surfaceContainerHighest: c.surface2,
    outline: c.bord,
    outlineVariant: c.bord,
  );
  final bordure = OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.bord));
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: schema,
    scaffoldBackgroundColor: Colors.transparent,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: encre,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: c.bord)),
      titleTextStyle: TextStyle(color: encre, fontSize: 17, fontWeight: FontWeight.w700),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent, shape: const RoundedRectangleBorder()),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c.bord)),
    ),
    dividerTheme: DividerThemeData(color: c.bord, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: bordure,
      enabledBorder: bordure,
      focusedBorder: bordure.copyWith(borderSide: BorderSide(color: primaire, width: 1.6)),
      errorBorder: bordure.copyWith(borderSide: BorderSide(color: c.danger)),
      labelStyle: TextStyle(color: c.encre2),
      floatingLabelStyle: TextStyle(color: primaire),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: encre,
        side: BorderSide(color: c.bord),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    listTileTheme: ListTileThemeData(iconColor: c.encre2, dense: true),
    dialogTheme: DialogThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
  );
}
