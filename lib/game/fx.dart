import 'dart:math' as math;
import 'dart:ui';

/// Lightweight particle and effect system for the arena (no allocations per
/// frame beyond the particles themselves, capped so it never stutters).
class Particle {
  Particle({
    required this.p,
    required this.v,
    required this.life,
    required this.size,
    required this.color,
    this.kind = 0,
    this.rot = 0,
    this.spin = 0,
    this.gravity = 900,
    this.drag = 2.2,
  }) : maxLife = life;

  Offset p;
  Offset v;
  double life;
  final double maxLife;
  final double size;
  final Color color;

  /// 0 = soft dot, 1 = confetti rectangle, 2 = spark streak, 3 = shard.
  final int kind;
  double rot;
  final double spin;
  final double gravity;
  final double drag;

  double get t => (life / maxLife).clamp(0.0, 1.0);
}

class Shockwave {
  Shockwave(this.centre, this.r0, this.r1, this.color, {this.life = 0.45, this.width = 6}) : maxLife = life;
  final Offset centre;
  final double r0, r1;
  final Color color;
  double life;
  final double maxLife;
  final double width;
}

class FxLayer {
  final List<Particle> particles = [];
  final List<Shockwave> waves = [];
  final math.Random _r = math.Random();

  static const _cap = 420;

  double rand(double a, double b) => a + _r.nextDouble() * (b - a);

  void burst(Offset c, double radius, List<Color> colours, {int count = 28, double power = 1}) {
    for (var i = 0; i < count && particles.length < _cap; i++) {
      final a = rand(0, math.pi * 2);
      final sp = rand(260, 620) * power;
      final start = c + Offset(math.cos(a), math.sin(a)) * radius * rand(0.4, 0.9);
      particles.add(
        Particle(
          p: start,
          v: Offset(math.cos(a), math.sin(a)) * sp + const Offset(0, -140),
          life: rand(0.5, 0.95),
          size: rand(4, 9) * (radius > 60 ? 1.2 : 1),
          color: colours[i % colours.length],
          kind: i % 3 == 0 ? 2 : 1,
          rot: rand(0, math.pi),
          spin: rand(-14, 14),
        ),
      );
    }
  }

  void shatter(Offset c, double radius, Color colour) {
    for (var i = 0; i < 22 && particles.length < _cap; i++) {
      final a = rand(0, math.pi * 2);
      final sp = rand(120, 420);
      particles.add(
        Particle(
          p: c + Offset(math.cos(a), math.sin(a)) * radius * rand(0.2, 0.8),
          v: Offset(math.cos(a), math.sin(a)) * sp,
          life: rand(0.55, 0.9),
          size: rand(6, 14),
          color: i.isEven ? colour : const Color(0xFF3A3645),
          kind: 3,
          rot: rand(0, math.pi),
          spin: rand(-8, 8),
          gravity: 1300,
          drag: 1.2,
        ),
      );
    }
  }

  void dust(Offset c, double radius) {
    for (var i = 0; i < 3 && particles.length < _cap; i++) {
      final a = rand(0, math.pi * 2);
      particles.add(
        Particle(
          p: c + Offset(math.cos(a), math.sin(a)) * radius * rand(0, 0.9),
          v: Offset(rand(-80, 80), rand(-160, -40)),
          life: rand(0.35, 0.6),
          size: rand(2, 4),
          color: const Color(0xFFB8AE9C),
          kind: 0,
          gravity: 300,
        ),
      );
    }
  }

  void wave(Offset c, double r0, double r1, Color colour, {double life = 0.45, double width = 6}) =>
      waves.add(Shockwave(c, r0, r1, colour, life: life, width: width));

  void clear() {
    particles.clear();
    waves.clear();
  }

  void update(double dt) {
    for (final p in particles) {
      p.life -= dt;
      p.v = p.v * math.max(0, 1 - p.drag * dt) + Offset(0, p.gravity * dt);
      p.p += p.v * dt;
      p.rot += p.spin * dt;
    }
    particles.removeWhere((p) => p.life <= 0);
    for (final w in waves) {
      w.life -= dt;
    }
    waves.removeWhere((w) => w.life <= 0);
  }

  void render(Canvas canvas) {
    final paint = Paint();
    for (final w in waves) {
      final t = 1 - w.life / w.maxLife;
      final e = 1 - math.pow(1 - t, 3).toDouble();
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = w.width * (1 - t) + 0.5
        ..color = w.color.withValues(alpha: (1 - t) * 0.9);
      canvas.drawCircle(w.centre, w.r0 + (w.r1 - w.r0) * e, paint);
    }
    paint.style = PaintingStyle.fill;
    for (final p in particles) {
      final a = p.t;
      paint.color = p.color.withValues(alpha: math.min(1, a * 1.6));
      switch (p.kind) {
        case 0:
          canvas.drawCircle(p.p, p.size * (0.5 + a * 0.5), paint);
        case 1:
          canvas.save();
          canvas.translate(p.p.dx, p.p.dy);
          canvas.rotate(p.rot);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55 * (0.4 + 0.6 * math.cos(p.rot * 2).abs())),
              const Radius.circular(1.5),
            ),
            paint,
          );
          canvas.restore();
        case 2:
          final dir = p.v.distance < 1 ? const Offset(0, 1) : p.v / p.v.distance;
          paint
            ..strokeWidth = p.size * 0.45
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(p.p, p.p - dir * (p.size * 2.2 * a + 2), paint);
        default:
          canvas.save();
          canvas.translate(p.p.dx, p.p.dy);
          canvas.rotate(p.rot);
          final s = p.size;
          canvas.drawPath(
            Path()
              ..moveTo(0, -s * 0.6)
              ..lineTo(s * 0.5, s * 0.4)
              ..lineTo(-s * 0.45, s * 0.3)
              ..close(),
            paint,
          );
          canvas.restore();
      }
    }
  }
}

/// A damped spring for tactile press/release motion (slight overshoot).
class Spring {
  double x = 0;
  double v = 0;
  double target = 0;

  void update(double dt, {double k = 700, double c = 26}) {
    // Sub-step for stability at low frame rates.
    final steps = (dt / (1 / 240)).ceil().clamp(1, 8);
    final h = dt / steps;
    for (var i = 0; i < steps; i++) {
      final a = k * (target - x) - c * v;
      v += a * h;
      x += v * h;
    }
  }
}

double easeOutBack(double t) {
  const c1 = 1.70158, c3 = c1 + 1;
  final u = t - 1;
  return 1 + c3 * u * u * u + c1 * u * u;
}

double easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();

double elasticOut(double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1;
}
