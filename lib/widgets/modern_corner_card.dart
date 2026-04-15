import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const int _kMaxClicks = 22;

/// Returns the accent color for the current [clicks] level.
///
/// Transitions from light-blue (comfort, 0 clicks) to red (track, 22 clicks).
Color _levelColor(int clicks) {
  final t = (clicks / _kMaxClicks).clamp(0.0, 1.0);
  return Color.lerp(const Color(0xFF64B5F6), const Color(0xFFFF5252), t)!;
}

/// Animated vertical "shock-absorber tube" that fills proportionally to level.
class _LevelIndicator extends StatelessWidget {
  const _LevelIndicator({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: fraction),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      builder: (context, value, _) {
        return Container(
          width: 22,
          height: 90,
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white12, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: value,
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOut,
                builder: (context, animColor, _) {
                  final c = animColor ?? color;
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          c,
                          c.withValues(alpha: 0.55), // fade toward top for depth
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A sleek, modern card widget for controlling a single suspension corner.
///
/// Features an animated level indicator, `+` / `-` buttons, an animated click
/// counter, and an ENVIAR send button. Haptic feedback is triggered on each
/// button press.
class ModernCornerCard extends StatelessWidget {
  const ModernCornerCard({
    super.key,
    required this.label,
    required this.clicks,
    required this.isConnected,
    required this.onChanged,
    required this.onSend,
    this.onChangeEnd,
  });

  final String label;
  final int clicks;
  final bool isConnected;
  final ValueChanged<int> onChanged;
  final VoidCallback? onSend;
  final VoidCallback? onChangeEnd;

  void _increment() {
    if (clicks >= _kMaxClicks) return;
    HapticFeedback.selectionClick();
    onChanged(clicks + 1);
    onChangeEnd?.call();
  }

  void _decrement() {
    if (clicks <= 0) return;
    HapticFeedback.selectionClick();
    onChanged(clicks - 1);
    onChangeEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _levelColor(clicks);
    final fillFraction = clicks / _kMaxClicks;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: accent.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
                 // ── Fila Superior: Etiqueta (Label) y Botón ENVIAR pequeño ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected ? Colors.blueAccent : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              // Botón ENVIAR más pequeño y arriba a la derecha
              SizedBox(
                height: 28, // Altura reducida
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected
                        ? accent.withValues(alpha: 0.15)
                        : Colors.transparent,
                    foregroundColor: isConnected ? accent : Colors.white30,
                    elevation: 0,
                    side: BorderSide(
                      color: isConnected
                          ? accent.withValues(alpha: 0.5)
                          : Colors.white12,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                  onPressed: isConnected
                      ? () {
                          HapticFeedback.mediumImpact();
                          onSend?.call();
                        }
                      : null,
                  icon: const Icon(Icons.send_rounded, size: 12),
                  label: const Text(
                    'ENVIAR',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          
          // ── Fila de Contenido Principal (Nivel y Botones +/-) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Tubo indicador de nivel
              _LevelIndicator(fraction: fillFraction, color: accent),
              const SizedBox(width: 12),
              
              // Columna de controles (Número y +/-)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Número de clicks animado
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: anim,
                            child: child,
                          ),
                          child: Text(
                            '$clicks',
                            key: ValueKey(clicks),
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: accent,
                              height: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'CLICKS',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Botones + y -
                    Row(
                      children: [
                        Expanded(
                          child: _AdjustButton(
                            label: '-',
                            onPressed: _decrement,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AdjustButton(
                            label: '+',
                            onPressed: _increment,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A large, tactile `+` or `−` adjustment button.
class _AdjustButton extends StatelessWidget {
  const _AdjustButton({
    required this.label,
    required this.onPressed,
    required this.color,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
        elevation: 0,
        side: BorderSide(color: color.withValues(alpha: 0.35)),
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
    );
  }
}
