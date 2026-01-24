import 'package:flutter/material.dart';
import 'package:simdaas/core/widgets/radio_group_list.dart';
import '../../../plot_mapping/data/models/plot_model.dart' as fm_models;

Future<String?> showBoundaryPicker(
    BuildContext context, List fields, String? initial) async {
  final picked = await showDialog<String?>(
    context: context,
    builder: (ctx) {
      String? temp = initial;
      return StatefulBuilder(builder: (ctx2, setStateDialog) {
        return AlertDialog(
          title: const Text('Select Boundary'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioGroupList<String>(
                  value: temp,
                  onChanged: (v) => setStateDialog(() {
                    temp = v;
                  }),
                  options: fields.map((ff) {
                    final f = ff as fm_models.PlotModel;
                    return RadioOption<String>(
                      value: f.id,
                      title: Text(f.name),
                      subtitle: (f.bedHeight != null || f.area != null)
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (f.bedHeight != null)
                                  Text('Bed H: ${f.bedHeight} m'),
                                if (f.area != null) Text('Area: ${f.area} ha'),
                              ],
                            )
                          : null,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(temp),
                child: const Text('OK')),
          ],
        );
      });
    },
  );

  return picked;
}
