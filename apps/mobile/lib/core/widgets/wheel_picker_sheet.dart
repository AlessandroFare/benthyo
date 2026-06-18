import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

Future<T?> showWheelPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> values,
  required T initialValue,
  required String Function(T value) labelBuilder,
  String? unit,
}) {
  var selectedIndex = values.indexOf(initialValue);
  if (selectedIndex < 0) selectedIndex = 0;

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.black,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(context, values[selectedIndex]),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  if (unit != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        unit,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Colors.white54,
                            ),
                      ),
                    ),
                  SizedBox(
                    height: 220,
                    child: ListWheelScrollView.useDelegate(
                      itemExtent: 64,
                      perspective: 0.003,
                      diameterRatio: 1.4,
                      onSelectedItemChanged: (index) =>
                          setState(() => selectedIndex = index),
                      controller: FixedExtentScrollController(
                        initialItem: selectedIndex,
                      ),
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: values.length,
                        builder: (context, index) {
                          final selected = index == selectedIndex;
                          return Center(
                            child: Text(
                              labelBuilder(values[index]),
                              style: TextStyle(
                                color: selected ? Colors.white : Colors.white24,
                                fontSize: selected ? 48 : 28,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<T?> showOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T option) labelBuilder,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                    ),
              ),
            ),
            ...options.map(
              (option) => ListTile(
                title: Text(
                  labelBuilder(option),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: selected == option
                    ? const Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(context, option),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      );
    },
  );
}
