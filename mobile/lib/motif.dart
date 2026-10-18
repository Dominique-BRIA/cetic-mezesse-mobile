// Fond de l'application : le même motif que sur le web (dépôt cetic-mezesse-web, src/components/MotifFond.tsx),
// redessiné à partir des mêmes tracés SVG.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import 'theme.dart';

String _engrenage(int dents, double rExt, double rInt) {
  final b = StringBuffer();
  final pas = pi * 2 / dents;
  String p(double r, double a) => '${(r * cos(a)).toStringAsFixed(2)} ${(r * sin(a)).toStringAsFixed(2)}';
  for (var i = 0; i < dents; i++) {
    final a = i * pas;
    b.write('${i == 0 ? 'M' : 'L'}${p(rInt, a - pas * 0.3)} L${p(rExt, a - pas * 0.18)} L${p(rExt, a + pas * 0.18)} L${p(rInt, a + pas * 0.3)} ');
  }
  return '${b}Z M4 0 A4 4 0 1 0 -4 0 A4 4 0 1 0 4 0';
}

String _rapporteur() {
  final b = StringBuffer('M-22 8 A22 22 0 0 1 22 8 Z M-10 8 A10 10 0 0 1 10 8 ');
  for (var i = 1; i < 12; i++) {
    final a = pi - i * pi / 12;
    final l = i % 3 == 0 ? 5 : 3;
    b.write('M${(22 * cos(a)).toStringAsFixed(2)} ${(-22 * sin(a) + 8).toStringAsFixed(2)} '
        'L${((22 - l) * cos(a)).toStringAsFixed(2)} ${(-(22 - l) * sin(a) + 8).toStringAsFixed(2)} ');
  }
  return b.toString();
}

String _touches() {
  final b = StringBuffer();
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 4; c++) {
      b.write('M${-9 + c * 6} ${-4 + r * 6} h3 v3 h-3 Z ');
    }
  }
  return b.toString();
}

String _spirales() => List.generate(6, (i) => 'M-15 ${-17 + i * 7} a2 2 0 1 0 0.01 0').join(' ');

final Map<String, String> _objets = {
  'equerre': 'M-16 -20 L-16 20 L16 20 Z M-10 -6 L-10 14 L6 14 Z M-16 -12 h4 M-16 -4 h4 M-16 4 h4 M-16 12 h4',
  'compas': 'M0 -21 a3 3 0 1 0 0.01 0 M0 -15 L-11 20 M0 -15 L11 20 L10 16 M-6 4 Q0 8 6 4 M-1.5 -24 V-27 M1.5 -24 V-27',
  'cle': 'M-12 -3 H10 M-12 3 H10 M-25 0 a7 7 0 1 0 14 0 a7 7 0 1 0 -14 0 M-21 0 l1.5 -2.6 h3 l1.5 2.6 l-1.5 2.6 h-3 Z M10 -3 C12 -9 20 -10 23 -6 L18 -2 L18 2 L23 6 C20 10 12 9 10 3',
  'ampoule': 'M0 -20 C-10 -20 -15 -12 -13 -5 C-12 0 -7 3 -6 8 H6 C7 3 12 0 13 -5 C15 -12 10 -20 0 -20 Z M-5 12 H5 M-4 16 H4 M-3 -4 L0 2 L3 -4 M-2 20 H2',
  'livre': 'M-21 -12 Q-10 -16 0 -11 Q10 -16 21 -12 V16 Q10 12 0 17 Q-10 12 -21 16 Z M0 -11 V17 M-16 -6 Q-9 -8 -4 -5 M-16 0 Q-9 -2 -4 1 M4 -5 Q9 -8 16 -6',
  'crayon': 'M-20 -4 H12 L20 0 L12 4 H-20 Z M12 -4 V4 M-14 -4 V4 M17 -1.4 L20 0 L17 1.4',
  'regle': 'M-28 -6 H28 V6 H-28 Z M-22 -6 V-1 M-16 -6 V-3 M-10 -6 V-1 M-4 -6 V-3 M2 -6 V0 M8 -6 V-3 M14 -6 V-1 M20 -6 V-3',
  'engrenage': _engrenage(9, 15, 11.5),
  'multimetre': 'M-14 -21 H14 a3 3 0 0 1 3 3 V18 a3 3 0 0 1 -3 3 H-14 a3 3 0 0 1 -3 -3 V-18 a3 3 0 0 1 3 -3 Z M-11 -16 H11 V-6 H-11 Z M-6 6 a6 6 0 1 0 12 0 a6 6 0 1 0 -12 0 M0 6 L4 2 M-9 17 a1.5 1.5 0 1 0 0.01 0 M9 17 a1.5 1.5 0 1 0 0.01 0 M-7 -11 h5 M2 -13 v4',
  'calculatrice': 'M-14 -22 H14 V22 H-14 Z M-10 -18 H10 V-9 H-10 Z ${_touches()}',
  'tournevis': 'M-22 -5 H-8 a2 2 0 0 1 2 2 V3 a2 2 0 0 1 -2 2 H-22 a2 2 0 0 1 -2 -2 V-3 a2 2 0 0 1 2 -2 Z M-20 -5 V5 M-16 -5 V5 M-12 -5 V5 M-6 0 H20 M20 -2 V2',
  'resistance': 'M-26 0 H-14 L-11 -6 L-5 6 L1 -6 L7 6 L13 -6 L16 0 H26 M-26 0 a1.5 1.5 0 1 0 0.01 0',
  'toque': 'M0 -14 L22 -4 L0 6 L-22 -4 Z M-12 1 V11 Q0 18 12 11 V1 M22 -4 V8 M20 13 L22 8 L24 13 Z',
  'rapporteur': _rapporteur(),
  'eprouvette': 'M-4 -20 V14 a4 4 0 0 0 8 0 V-20 M-7 -20 H7 M-4 4 H4 M-1 9 a1 1 0 1 0 0.01 0 M1 0 a1 1 0 1 0 0.01 0',
  'cahier': 'M-12 -22 H16 V22 H-12 Z ${_spirales()} M-6 -12 H11 M-6 -6 H11 M-6 0 H8 M-6 6 H11',
};

const Map<String, String> _petits = {
  'plus': 'M-4 0 H4 M0 -4 V4',
  'rond': 'M-3 0 a3 3 0 1 0 6 0 a3 3 0 1 0 -6 0',
  'triangle': 'M0 -4 L4 3 H-4 Z',
  'zigzag': 'M-7 0 L-4 -3 L-1 0 L2 -3 L5 0',
  'etoile': 'M0 -5 L1.5 -1.5 L5 -1.5 L2.2 0.8 L3.2 4.5 L0 2.3 L-3.2 4.5 L-2.2 0.8 L-5 -1.5 L-1.5 -1.5 Z',
};

const _placement = [
  ('equerre', 52.0, 48.0, -12.0), ('ampoule', 150.0, 58.0, 10.0), ('regle', 252.0, 44.0, -28.0), ('cahier', 352.0, 56.0, 8.0),
  ('cle', 46.0, 152.0, -40.0), ('livre', 152.0, 146.0, -8.0), ('multimetre', 250.0, 156.0, 12.0), ('toque', 350.0, 148.0, -10.0),
  ('calculatrice', 54.0, 252.0, 14.0), ('compas', 148.0, 250.0, -18.0), ('engrenage', 252.0, 248.0, 0.0), ('crayon', 348.0, 254.0, 35.0),
  ('resistance', 50.0, 352.0, -20.0), ('tournevis', 150.0, 350.0, 40.0), ('rapporteur', 252.0, 352.0, -14.0), ('eprouvette', 350.0, 346.0, 22.0),
];

const _petitsPlaces = [
  ('plus', 100.0, 100.0), ('rond', 200.0, 104.0), ('triangle', 300.0, 98.0), ('etoile', 4.0, 100.0),
  ('zigzag', 100.0, 200.0), ('plus', 204.0, 200.0), ('rond', 300.0, 202.0), ('triangle', 2.0, 200.0),
  ('etoile', 102.0, 300.0), ('triangle', 200.0, 298.0), ('zigzag', 300.0, 300.0), ('rond', 4.0, 302.0),
  ('triangle', 100.0, 4.0), ('plus', 200.0, 2.0), ('etoile', 302.0, 4.0), ('zigzag', 4.0, 2.0),
];

// La tuile de 400 × 400 est calculée une seule fois.
final Path _tuile = () {
  final p = Path();
  Matrix4 m(double x, double y, double r, double s) => Matrix4.identity()
    ..translateByDouble(x, y, 0, 1)
    ..rotateZ(r * pi / 180)
    ..scaleByDouble(s, s, 1, 1);
  for (final (nom, x, y, r) in _placement) {
    p.addPath(parseSvgPathData(_objets[nom]!).transform(m(x, y, r, 0.95).storage), Offset.zero);
  }
  for (var i = 0; i < _petitsPlaces.length; i++) {
    final (nom, x, y) = _petitsPlaces[i];
    p.addPath(parseSvgPathData(_petits[nom]!).transform(m(x, y, i * 23.0, 1).storage), Offset.zero);
  }
  return p;
}();

class _Peintre extends CustomPainter {
  _Peintre(this.fond, this.trait);
  final Color fond;
  final Color trait;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fond);
    const echelle = 0.8; // un peu plus petit que sur grand écran
    const pas = 400 * echelle;
    final crayon = Paint()
      ..color = trait
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var y = 0.0; y < size.height; y += pas) {
      for (var x = 0.0; x < size.width; x += pas) {
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(echelle);
        canvas.drawPath(_tuile, crayon);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_Peintre old) => old.fond != fond || old.trait != trait;
}

class MotifFond extends StatelessWidget {
  const MotifFond({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Stack(
      children: [
        Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _Peintre(c.fond, c.motif)))),
        child,
      ],
    );
  }
}
