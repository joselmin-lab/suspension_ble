import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A sleek, modern card widget for controlling a single suspension corner.
///
/// Features animated click counter, custom slider theme, and haptic feedback.
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

  @override
  Widget build(BuildContext context) {
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
          color: Colors.blueAccent.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
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
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Animated click value + send button
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
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
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: Colors.blueAccent,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'CLICKS',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: Colors.white38,
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected
                      ? Colors.blueAccent.withValues(alpha: 0.15)
                      : Colors.transparent,
                  foregroundColor:
                      isConnected ? Colors.blueAccent : Colors.white30,
                  elevation: 0,
                  side: BorderSide(
                    color: isConnected
                        ? Colors.blueAccent.withValues(alpha: 0.5)
                        : Colors.white12,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: isConnected
                    ? () {
                        HapticFeedback.mediumImpact();
                        onSend?.call();
                      }
                    : null,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text(
                  'ENVIAR',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.blueAccent,
              inactiveTrackColor: Colors.blueAccent.withValues(alpha: 0.15),
              thumbColor: Colors.white,
              overlayColor: Colors.blueAccent.withValues(alpha: 0.15),
              valueIndicatorColor: Colors.blueAccent,
              valueIndicatorTextStyle: const TextStyle(color: Colors.white),
              trackHeight: 4,
            ),
            child: Slider(
              value: clicks.toDouble(),
              min: 0,
              max: 22,
              divisions: 22,
              label: '$clicks',
              onChanged: (d) {
                HapticFeedback.selectionClick();
                onChanged(d.toInt());
              },
              onChangeEnd: (_) => onChangeEnd?.call(),
            ),
          ),
        ],
      ),
    );
  }
}
