import 'package:flutter/material.dart';

class RadioOption<T> {
  final T value;
  final Widget title;
  final Widget? subtitle;
  RadioOption({required this.value, required this.title, this.subtitle});
}

/// Lightweight selector list that replicates RadioGroup behavior without
/// relying on the deprecated `Radio`/`RadioListTile` APIs. Shows a selectable
/// icon and invokes `onChanged` with the selected value.
class RadioGroupList<T> extends StatelessWidget {
  final T? value;
  final ValueChanged<T?>? onChanged;
  final List<RadioOption<T>> options;
  final Axis axis;

  const RadioGroupList({
    super.key,
    required this.options,
    this.value,
    this.onChanged,
    this.axis = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    if (axis == Axis.vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final selected = value != null && value == o.value;
          return ListTile(
            leading: Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? Theme.of(context).colorScheme.primary : null,
            ),
            title: o.title,
            subtitle: o.subtitle,
            onTap: () => onChanged?.call(o.value),
            contentPadding: EdgeInsets.zero,
          );
        }).toList(),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((o) {
          final selected = value != null && value == o.value;
          return InkWell(
            onTap: () => onChanged?.call(o.value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color:
                        selected ? Theme.of(context).colorScheme.primary : null,
                  ),
                  const SizedBox(width: 6),
                  o.title,
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
