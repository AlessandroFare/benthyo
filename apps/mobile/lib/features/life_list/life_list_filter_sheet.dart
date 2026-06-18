import 'package:flutter/material.dart';

import '../../core/models/enums.dart';
import '../../core/theme/app_theme.dart';

class LifeListFilterSheet extends StatefulWidget {
  const LifeListFilterSheet({
    super.key,
    required this.selectedTypes,
  });

  final Set<SiteType> selectedTypes;

  @override
  State<LifeListFilterSheet> createState() => _LifeListFilterSheetState();
}

class _LifeListFilterSheetState extends State<LifeListFilterSheet> {
  late Set<SiteType> _selected;

  static const _categories = [
    (SiteType.reef, 'Reef', Icons.water, Color(0xFF2ECC71)),
    (SiteType.wreck, 'Wreck', Icons.directions_boat, Color(0xFFE74C3C)),
    (SiteType.wall, 'Wall', Icons.landscape, Color(0xFF3498DB)),
    (SiteType.pinnacle, 'Pelagic', Icons.waves, Color(0xFF9B59B6)),
    (SiteType.muck, 'Macro', Icons.visibility, Color(0xFF95A5A6)),
    (SiteType.cave, 'Cave', Icons.landscape_outlined, Color(0xFF34495E)),
  ];

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedTypes);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
                Text(
                  'Filters',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 2.4,
              children: _categories.map((item) {
                final selected = _selected.contains(item.$1);
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selected.remove(item.$1);
                      } else {
                        _selected.add(item.$1);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? AppColors.primary : Colors.black12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.$3,
                          color: selected ? Colors.white : item.$4,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            item.$2,
                            style: TextStyle(
                              color:
                                  selected ? Colors.white : AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: () => setState(_selected.clear),
              icon: const Icon(Icons.clear, color: Colors.orange),
              label: const Text(
                'Clear all',
                style: TextStyle(color: Colors.orange),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onPressed: () => Navigator.pop(context, _selected),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Set<SiteType>?> showLifeListFilterSheet({
  required BuildContext context,
  required Set<SiteType> selectedTypes,
}) {
  return showModalBottomSheet<Set<SiteType>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => LifeListFilterSheet(selectedTypes: selectedTypes),
  );
}
