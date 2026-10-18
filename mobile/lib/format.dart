// Mise en forme des nombres, dates et rangs (mêmes règles que le web).

String note(num? v, [int decimales = 2]) => v == null ? '—' : v.toStringAsFixed(decimales).replaceAll('.', ',');

String pourcent(num? v) => v == null ? '—' : '${v.toStringAsFixed(1).replaceAll('.', ',')} %';

String rang(Map? r) {
  if (r == null) return '—';
  final n = r['rang'] as int;
  return '$n${n == 1 ? 'er' : 'e'}${r['exAequo'] == true ? ' ex' : ''}';
}

String date(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.parse(iso).toUtc();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String nom(Map? p) => p == null ? '—' : '${p['nom']} ${p['prenoms'] ?? p['prenom'] ?? ''}'.trim();

const roles = {'PROVISEUR': 'Directeur', 'SURVEILLANT_GENERAL': 'Surveillant Général', 'PROFESSEUR': 'Professeur'};

/// Au CETIC, le chef d'établissement est le Directeur, ou la Directrice si la civilité est « Mme ».
String libelleRole(Map? u) {
  final role = u?['role'] as String? ?? '';
  return role == 'PROVISEUR' && u?['sexe'] == 'F' ? 'Directrice' : roles[role] ?? '';
}

/// « 2024-09-02T00:00:00.000Z » ou « 2024-09-02 » → date locale (sans heure) ; null si absent.
DateTime? jour(String? iso) {
  if (iso == null || iso.length < 10) return null;
  final d = DateTime.tryParse(iso.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Date envoyée à l'API : « 2024-09-02 ».
String? isoJour(DateTime? d) => d == null ? null : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const periodes = [
  ('S1', 'Séquence 1'),
  ('S2', 'Séquence 2'),
  ('T1', 'Trimestre 1'),
  ('S3', 'Séquence 3'),
  ('S4', 'Séquence 4'),
  ('T2', 'Trimestre 2'),
  ('S5', 'Séquence 5'),
  ('S6', 'Séquence 6'),
  ('T3', 'Trimestre 3'),
  ('A', 'Année complète'),
];

String libellePeriode(String code) => periodes.firstWhere((p) => p.$1 == code, orElse: () => (code, code)).$2;

/// « 12,5 » ou « 12.5 » → 12.5 ; vide → null ; invalide → NaN.
double? lireNote(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  if (!RegExp(r'^\d{1,2}(\.\d{1,2})?$').hasMatch(t)) return double.nan;
  final v = double.parse(t);
  return v >= 0 && v <= 20 ? v : double.nan;
}

String saisieNote(num? v) {
  if (v == null) return '';
  final s = v.toStringAsFixed(2).replaceAll('.', ',');
  return s.endsWith(',00') ? s.substring(0, s.length - 3) : s;
}

/// Même calcul que l'API (RG-29) : la lettre n'apparaît que s'il y a plusieurs classes.
String nomClasse(int niveau, String? specialite, int rang, int nombre) {
  final lettre = nombre > 1 ? ' ${rang < 26 ? String.fromCharCode(65 + rang) : rang + 1}' : '';
  return '${niveau == 1 ? '1re' : '${niveau}e'} année${specialite == null ? '' : ' $specialite'}$lettre';
}
