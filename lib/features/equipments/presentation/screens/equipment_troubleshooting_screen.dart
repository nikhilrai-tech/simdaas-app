import 'package:flutter/material.dart';

/// Simple troubleshooting reference page for equipment LED indications.
class EquipmentTroubleshootingScreen extends StatelessWidget {
  const EquipmentTroubleshootingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment Troubleshooting'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Light indications',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
                'Refer to the light patterns below to diagnose control units:'),
            const SizedBox(height: 12),
            _row(Colors.blue, 1.0,
                'Blue blink (1 Hz): Control unit registration'),
            const SizedBox(height: 8),
            _row(Colors.blueAccent, 5.0, 'Blue blink (5 Hz): Config upload'),
            const SizedBox(height: 8),
            _row(Colors.red, 5.0, 'Red blink (5 Hz): Sensor error'),
            const SizedBox(height: 8),
            _row(Colors.blue, 0.0, 'Solid blue: Boot and MQTT registration'),
            const SizedBox(height: 20),

            // Normal operation indicators
            Text('Normal operation',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _row(Colors.green, 3.0, 'Green blink (3 Hz): Demo mode'),
            const SizedBox(height: 6),
            _row(Colors.green, 0.0, 'Green solid: Auto mode'),
            const SizedBox(height: 6),
            _row(Colors.green, 1.0, 'Green blink (1 Hz): Manual mode'),
            const SizedBox(height: 16),

            // Cloud disintegrated indicators
            Text('Cloud disintegrated',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _row(Colors.red, 3.0, 'Red blink (3 Hz): Demo mode'),
            const SizedBox(height: 6),
            _row(Colors.red, 0.0, 'Red solid: Auto mode'),
            const SizedBox(height: 6),
            _row(Colors.red, 1.0, 'Red blink (1 Hz): Manual mode'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _row(Color color, double frequencyHz, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BlinkDot(color: color, frequencyHz: frequencyHz, size: 14),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}

/// A small blinking dot that toggles visibility at the requested frequency (Hz).
class BlinkDot extends StatefulWidget {
  final Color color;
  final double frequencyHz; // 0 for solid
  final double size;

  const BlinkDot(
      {super.key,
      required this.color,
      required this.frequencyHz,
      this.size = 14.0});

  @override
  State<BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<BlinkDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if ((widget.frequencyHz ?? 0) > 0) {
      final periodMs = (1000 / widget.frequencyHz).round();
      _ctrl = AnimationController(
          vsync: this, duration: Duration(milliseconds: periodMs))
        ..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ctrl == null) {
      // solid
      return Icon(Icons.circle, size: widget.size, color: widget.color);
    }
    return AnimatedBuilder(
      animation: _ctrl!,
      builder: (context, child) {
        final visible = (_ctrl!.value < 0.5);
        return Opacity(
          opacity: visible ? 1.0 : 0.0,
          child: Icon(Icons.circle, size: widget.size, color: widget.color),
        );
      },
    );
  }
}
