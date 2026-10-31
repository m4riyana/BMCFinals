import 'package:flutter/material.dart';

const ink = Color(0xFF211E1B);
const cream = Color(0xFFF3F0DE);
const paper = Color(0xFFFFFEF8);
const red = Color(0xFFA34447);
const beige = Color(0xFFE7DCC2);
const serif = TextStyle(
    fontFamily: 'Libre Baskerville',
    fontWeight: FontWeight.w700,
    height: 1.05,
    color: ink);
const hand = TextStyle(
    fontFamily: 'Caveat',
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w900,
    color: red);

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: red,
                border: Border.all(color: ink, width: 2),
                boxShadow: const [BoxShadow(color: ink, offset: Offset(3, 3))]),
            child: const Icon(Icons.edit_outlined, color: paper, size: 27)),
        const SizedBox(width: 14),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('IBASHO',
              style: TextStyle(
                  fontFamily: 'Libre Baskerville',
                  fontSize: 21,
                  letterSpacing: 5,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text('STATIONERY',
              style: TextStyle(fontSize: 9, letterSpacing: 3, color: red))
        ]),
      ]);
}

class Panel extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  const Panel(
      {super.key,
      required this.child,
      this.color = paper,
      this.padding = const EdgeInsets.all(28)});
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
          color: color,
          border: Border.all(color: ink, width: 2.5),
          boxShadow: const [BoxShadow(color: ink, offset: Offset(6, 7))]),
      child: child);
}

class Speech extends StatelessWidget {
  final String text;
  const Speech(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      decoration: BoxDecoration(
          color: paper,
          border: Border.all(color: ink, width: 2.5),
          borderRadius: BorderRadius.circular(100)),
      child: Text(text,
          textAlign: TextAlign.center,
          style: hand.copyWith(color: ink, fontSize: 16)));
}

class StationeryArt extends StatelessWidget {
  final bool recovery;
  const StationeryArt({super.key, this.recovery = false});
  @override
  Widget build(BuildContext context) => AspectRatio(
      aspectRatio: 1.24,
      child: Panel(
          color: beige,
          padding: EdgeInsets.zero,
          child: Stack(children: [
            Positioned.fill(
                child: CustomPaint(painter: SuppliesPainter(recovery))),
            Positioned(
                top: 20,
                left: 20,
                child: Text(
                    recovery ? 'A FRESH START.' : 'MAKE ROOM FOR IDEAS.',
                    style: hand.copyWith(fontSize: 16))),
            Positioned(
                top: 35,
                right: 20,
                child: Speech(recovery
                    ? 'We will help you\nfind your way back.'
                    : 'Your next\ngreat idea\nstarts here.')),
            Positioned(
                bottom: 16,
                right: 20,
                child:
                    Text('Make it yours!', style: hand.copyWith(fontSize: 20))),
          ])));
}

class SuppliesPainter extends CustomPainter {
  final bool recovery;
  SuppliesPainter(this.recovery);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 600, size.height / 480);
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    void box(Rect rect, Color color) {
      canvas.drawRect(rect, Paint()..color = color);
      canvas.drawRect(rect, line);
    }

    for (double x = 7; x < 600; x += 7) {
      for (double y = 7; y < 480; y += 7) {
        canvas.drawCircle(
            Offset(x, y), .55, Paint()..color = ink.withValues(alpha: .18));
      }
    }
    if (recovery) {
      canvas.save();
      canvas.translate(110, 245);
      canvas.rotate(-.08);
      canvas.drawRect(
          const Rect.fromLTWH(7, 8, 180, 125), Paint()..color = red);
      box(const Rect.fromLTWH(0, 0, 180, 125), paper);
      canvas.drawLine(const Offset(0, 0), const Offset(90, 65), line);
      canvas.drawLine(const Offset(180, 0), const Offset(90, 65), line);
      canvas.restore();
    } else {
      box(const Rect.fromLTWH(35, 140, 245, 285), const Color(0xFFB9AE99));
      for (int row = 0; row < 2; row++) {
        for (int i = 0; i < 5; i++) {
          final h = 83.0 + (i % 3) * 11;
          final rect = Rect.fromLTWH(51 + i * 43, 264 + row * 139 - h, 33, h);
          box(rect, i == 2 ? beige : paper);
          canvas.drawRect(Rect.fromLTWH(rect.left + 2, rect.bottom - 9, 29, 7),
              Paint()..color = red.withValues(alpha: .6));
        }
        canvas.drawLine(
            Offset(46, 269 + row * 139), Offset(270, 269 + row * 139), line);
      }
      box(const Rect.fromLTWH(350, 205, 160, 190), paper);
      box(const Rect.fromLTWH(350, 205, 18, 190), red);
      for (double y = 242; y < 375; y += 20) {
        canvas.drawLine(
            Offset(387, y),
            Offset(492, y),
            Paint()
              ..color = beige
              ..strokeWidth = 2);
      }
      canvas.save();
      canvas.translate(465, 330);
      canvas.rotate(.2);
      box(const Rect.fromLTWH(0, -160, 13, 160), red);
      final tip = Path()
        ..moveTo(0, 0)
        ..lineTo(6.5, 22)
        ..lineTo(13, 0)
        ..close();
      canvas.drawPath(tip, Paint()..color = ink);
      canvas.restore();
      box(const Rect.fromLTWH(300, 345, 43, 68), const Color(0xFFB9AE99));
      for (int i = 0; i < 3; i++) {
        canvas.drawLine(
            Offset(310 + i * 11, 350), Offset(302 + i * 16, 294), line);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SuppliesPainter oldDelegate) =>
      recovery != oldDelegate.recovery;
}

class AuthLayout extends StatelessWidget {
  final Widget form;
  final bool recovery;
  final String chapter;
  const AuthLayout(
      {super.key,
      required this.form,
      required this.chapter,
      this.recovery = false});
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final left = Container(
            color: cream,
            padding: EdgeInsets.all(wide ? 48 : 28),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BrandLogo(),
              const SizedBox(height: 35),
              if (wide) ...[
                Expanded(
                  child: Center(child: StationeryArt(recovery: recovery)),
                ),
                const SizedBox(height: 30)
              ],
              Text('A place for your next idea.',
                  style: hand.copyWith(color: ink, fontSize: 19)),
              const SizedBox(height: 8),
              const Text('Your Space. Your Tools. Your Story.',
                  style: TextStyle(fontSize: 10, letterSpacing: 1)),
            ]));
        final right = Container(
            color: paper,
            padding: EdgeInsets.all(wide ? 44 : 28),
            child: Column(children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: Text(chapter,
                      style: const TextStyle(
                          color: red, fontSize: 9, letterSpacing: 1.5))),
              const SizedBox(height: 48),
              Expanded(
                  child: Center(
                      child: SingleChildScrollView(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 410),
                              child: form)))),
              const SizedBox(height: 32),
              const Text('© 2026 IBASHO STATIONERY',
                  style: TextStyle(
                      fontSize: 9, letterSpacing: 1, color: Colors.black54)),
            ]));
        if (wide) {
          return Row(children: [
            Expanded(child: left),
            Container(width: 2, color: ink),
            Expanded(child: right)
          ]);
        }
        return SingleChildScrollView(
            child: Column(children: [
          SizedBox(width: double.infinity, child: left),
          SizedBox(height: 760, child: right)
        ]));
      }));
}
