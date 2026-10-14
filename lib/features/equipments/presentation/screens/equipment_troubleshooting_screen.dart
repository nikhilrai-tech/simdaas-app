import 'package:flutter/material.dart';

/// Troubleshooting reference page for the control unit's RGB status LED.
///
/// Mirrors the firmware's LED Status Reference: hue says which feature,
/// blink rate says which phase. Green and red are reserved for link status
/// and outcomes.
class EquipmentTroubleshootingScreen extends StatelessWidget {
  const EquipmentTroubleshootingScreen({super.key});

  static const _magenta = Color(0xFFE91EE3);
  static const _yellow = Color(0xFFFFC107);
  static const _off = Colors.transparent;

  static const List<_LedSection> _sections = [
    _LedSection(
      icon: Icons.check_circle_outline,
      title: 'Normal operation',
      legend: [
        _Legend('Colour', [
          _LegendItem(Colors.green, LedPattern.solid(), 'Cloud connected'),
          _LegendItem(Colors.red, LedPattern.solid(), 'Disconnected'),
        ]),
        _Legend('Pattern', [
          _LegendItem(Colors.green, LedPattern.solid(), 'Solid = auto mode'),
          _LegendItem(
              Colors.green, LedPattern.blink(1), 'Blinking = manual mode'),
        ]),
        _Legend('Session open', [
          _LegendItem(Colors.green, LedPattern.wink(), 'Wink (auto)'),
          _LegendItem(
              Colors.green, LedPattern.doublePulse(), 'Double pulse (manual)'),
        ]),
      ],
      rows: [
        _LedRow(Colors.green, LedPattern.solid(), 'Solid green',
            'Auto mode, connected'),
        _LedRow(Colors.green, LedPattern.wink(), 'Green, brief wink every 1 s',
            'Auto mode, connected, session open'),
        _LedRow(Colors.green, LedPattern.blink(1), 'Green blink (1 Hz)',
            'Manual mode, connected'),
        _LedRow(
            Colors.green,
            LedPattern.doublePulse(),
            'Green, two pulses then a gap',
            'Manual mode, connected, session open'),
        _LedRow(Colors.red, LedPattern.solid(), 'Solid red',
            'Auto mode, cloud disconnected'),
        _LedRow(Colors.red, LedPattern.wink(), 'Red, brief wink every 1 s',
            'Auto mode, disconnected, session open'),
        _LedRow(Colors.red, LedPattern.blink(1), 'Red blink (1 Hz)',
            'Manual mode, cloud disconnected'),
        _LedRow(
            Colors.red,
            LedPattern.doublePulse(),
            'Red, two pulses then a gap',
            'Manual mode, disconnected, session open'),
      ],
    ),
    _LedSection(
      icon: Icons.power_settings_new,
      title: 'Power on',
      rows: [
        _LedRow(Colors.blue, LedPattern.blink(5), 'Blue blink (5 Hz)',
            'Booting (first 3 s)'),
        _LedRow(_off, LedPattern.solid(), 'LED off',
            'Stabilising, 3 to 8 s after power on. This is normal'),
      ],
    ),
    _LedSection(
      icon: Icons.touch_app_outlined,
      title: 'Session start button',
      note: 'Auto mode only. Hold the RIGHT button for 5 s to start or end '
          'a session.',
      rows: [
        _LedRow(Colors.purple, LedPattern.accelerating(), 'Purple, speeding up',
            'Keep holding, nearly there'),
        _LedRow(_yellow, LedPattern.solid(), 'Solid yellow (5 s)',
            'Session started'),
        _LedRow(_yellow, LedPattern.blink(5), 'Yellow blink (5 Hz, 5 s)',
            'Session ended'),
      ],
    ),
    _LedSection(
      icon: Icons.system_update_alt,
      title: 'Firmware update (OTA)',
      rows: [
        _LedRow(_magenta, LedPattern.blink(1), 'Magenta blink (1 Hz)',
            'Joining WiFi hotspot'),
        _LedRow(_magenta, LedPattern.blink(5), 'Magenta blink (5 Hz)',
            'Downloading firmware'),
        _LedRow(_magenta, LedPattern.solid(), 'Solid magenta',
            'Download OK, about to reboot'),
        _LedRow(_magenta, LedPattern.blink(2), 'Magenta blink (2 Hz)',
            'New firmware on trial after reboot'),
        _LedRow(Colors.red, LedPattern.blink(5), 'Red blink (5 Hz), stays on',
            'Firmware update failed'),
      ],
    ),
    _LedSection(
      icon: Icons.cloud_upload_outlined,
      title: 'Log upload',
      rows: [
        _LedRow(Colors.cyan, LedPattern.blink(1), 'Cyan blink (1 Hz)',
            'Connecting over WiFi'),
        _LedRow(Colors.cyan, LedPattern.blink(5), 'Cyan blink (5 Hz)',
            'Uploading over WiFi'),
        _LedRow(Colors.orange, LedPattern.blink(1), 'Orange blink (1 Hz)',
            'Connecting over cellular'),
        _LedRow(Colors.orange, LedPattern.blink(5), 'Orange blink (5 Hz)',
            'Uploading over cellular'),
      ],
    ),
    _LedSection(
      icon: Icons.bluetooth,
      title: 'Bluetooth log retrieval',
      note: 'Auto mode only. Hold the LEFT button for 5 s to open a '
          '5 minute Bluetooth window.',
      rows: [
        _LedRow(Colors.purple, LedPattern.accelerating(), 'Purple, speeding up',
            'Keep holding, nearly there'),
        _LedRow(Colors.cyan, LedPattern.doublePulse(),
            'Cyan, two pulses then a gap', 'Bluetooth window open'),
        _LedRow(Colors.cyan, LedPattern.blink(5), 'Cyan blink (5 Hz)',
            'Sending file to phone'),
      ],
    ),
    _LedSection(
      icon: Icons.mark_email_unread_outlined,
      title: 'Commands and messages',
      rows: [
        _LedRow(
            Colors.white,
            LedPattern.doublePulse(),
            'White, two pulses then a gap (5 s)',
            'Control unit / plot changed, or factory reset done'),
        _LedRow(Colors.blue, LedPattern.blink(1), 'Blue blink (1 Hz, 5 s)',
            'Message received from cloud'),
      ],
    ),
    _LedSection(
      icon: Icons.flag_outlined,
      title: 'Update / upload result',
      rows: [
        _LedRow(Colors.green, LedPattern.solid(), 'Solid green for ~5 s',
            'Update or upload succeeded'),
        _LedRow(Colors.red, LedPattern.blink(5), 'Red blink (5 Hz) for ~5 s',
            'Update or upload failed'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment Troubleshooting'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Light indications', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Match the control unit\'s light to a pattern below to see '
            'what it means.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final section in _sections) _SectionCard(section: section),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final _LedSection section;

  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(section.icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (section.legend.isNotEmpty || section.note != null) ...[
              const SizedBox(height: 12),
              _InfoBox(legend: section.legend, note: section.note),
            ],
            const SizedBox(height: 4),
            for (var i = 0; i < section.rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
              _LedRowTile(row: section.rows[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final List<_Legend> legend;
  final String? note;

  const _InfoBox({required this.legend, this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textStyle = theme.textTheme.bodyMedium
        ?.copyWith(color: scheme.onSecondaryContainer);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: scheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(child: Text(note!, style: textStyle)),
              ],
            ),
          for (var i = 0; i < legend.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 && note == null ? 0 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    legend[i].label,
                    style: textStyle?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      for (final item in legend[i].items)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LedLamp(
                                color: item.color,
                                pattern: item.pattern,
                                size: 24),
                            const SizedBox(width: 8),
                            Text(item.text, style: textStyle),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LedRowTile extends StatelessWidget {
  final _LedRow row;

  const _LedRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          LedLamp(color: row.color, pattern: row.pattern),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  row.meaning,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LedSection {
  final IconData icon;
  final String title;
  final String? note;
  final List<_Legend> legend;
  final List<_LedRow> rows;

  const _LedSection({
    required this.icon,
    required this.title,
    this.note,
    this.legend = const [],
    required this.rows,
  });
}

class _Legend {
  final String label;
  final List<_LegendItem> items;

  const _Legend(this.label, this.items);
}

class _LegendItem {
  final Color color;
  final LedPattern pattern;
  final String text;

  const _LegendItem(this.color, this.pattern, this.text);
}

class _LedRow {
  final Color color;
  final LedPattern pattern;
  final String label;
  final String meaning;

  const _LedRow(this.color, this.pattern, this.label, this.meaning);
}

enum _LedPatternKind { solid, blink, wink, doublePulse, accelerating }

/// How the LED lights over time, matching the firmware's patterns.
class LedPattern {
  final _LedPatternKind _kind;
  final double _hz;

  /// Always on.
  const LedPattern.solid()
      : _kind = _LedPatternKind.solid,
        _hz = 0;

  /// 50% duty blink at [hz].
  const LedPattern.blink(double hz)
      : _kind = _LedPatternKind.blink,
        _hz = hz;

  /// Solid, with a 120 ms off gap every 1 s.
  const LedPattern.wink()
      : _kind = _LedPatternKind.wink,
        _hz = 0;

  /// 120 ms on, 120 ms off, 120 ms on, then quiet; 1 s cycle.
  const LedPattern.doublePulse()
      : _kind = _LedPatternKind.doublePulse,
        _hz = 0;

  /// Blink accelerating from 1 Hz to 5 Hz over 5 s (button hold progress).
  const LedPattern.accelerating()
      : _kind = _LedPatternKind.accelerating,
        _hz = 0;

  static const _unitMs = 120;
  static const _rampMs = 5000;

  bool get isAnimated => _kind != _LedPatternKind.solid;

  Duration get cycle {
    switch (_kind) {
      case _LedPatternKind.solid:
      case _LedPatternKind.wink:
      case _LedPatternKind.doublePulse:
        return const Duration(milliseconds: 1000);
      case _LedPatternKind.blink:
        return Duration(milliseconds: (1000 / _hz).round());
      case _LedPatternKind.accelerating:
        return const Duration(milliseconds: _rampMs);
    }
  }

  /// Whether the LED is lit [ms] into the current cycle.
  bool isOnAt(double ms) {
    switch (_kind) {
      case _LedPatternKind.solid:
        return true;
      case _LedPatternKind.blink:
        return ms < cycle.inMilliseconds / 2;
      case _LedPatternKind.wink:
        return ms < 1000 - _unitMs;
      case _LedPatternKind.doublePulse:
        return ms < _unitMs || (ms >= 2 * _unitMs && ms < 3 * _unitMs);
      case _LedPatternKind.accelerating:
        // Frequency rises linearly 1 -> 5 Hz; phase is its integral.
        final t = ms / 1000;
        final phase = t + 0.4 * t * t;
        return phase - phase.floor() < 0.5;
    }
  }
}

/// A dark "lamp" housing with an LED that lights according to [pattern],
/// so white and yellow stay visible and the glow reads like the real unit.
class LedLamp extends StatefulWidget {
  final Color color;
  final LedPattern pattern;
  final double size;

  const LedLamp(
      {super.key,
      required this.color,
      required this.pattern,
      this.size = 36.0});

  @override
  State<LedLamp> createState() => _LedLampState();
}

class _LedLampState extends State<LedLamp> with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.pattern.isAnimated) {
      _ctrl = AnimationController(vsync: this, duration: widget.pattern.cycle)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Widget _lamp(bool on) {
    final lit = on && widget.color.a > 0;
    final dot = widget.size * 0.45;
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF263238),
        borderRadius: BorderRadius.circular(widget.size * 0.28),
      ),
      child: Container(
        width: dot,
        height: dot,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: lit ? widget.color : const Color(0xFF455A64),
          boxShadow: lit
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.7),
                    blurRadius: widget.size * 0.28,
                    spreadRadius: widget.size * 0.05,
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null) return _lamp(true);
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, child) {
        final ms = ctrl.value * widget.pattern.cycle.inMilliseconds;
        return _lamp(widget.pattern.isOnAt(ms));
      },
    );
  }
}
