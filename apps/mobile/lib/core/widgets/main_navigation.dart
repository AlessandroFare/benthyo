import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

class MainNavigationBar extends StatelessWidget {
  const MainNavigationBar({super.key, required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.7)
                : Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        animationDuration: const Duration(milliseconds: 300),
        onDestinationSelected: (i) {
          if (i != currentIndex) HapticFeedback.selectionClick();
          switch (i) {
            case 0:
              context.go('/map');
            case 1:
              context.go('/dive-logs');
            case 2:
              context.go('/sightings');
            case 3:
              context.go('/species');
            case 4:
              context.go('/profile');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explore',
            tooltip: 'Explore dive sites on the map',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: 'My Dives',
            tooltip: 'Your dive logbook',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_camera_outlined),
            selectedIcon: Icon(Icons.photo_camera),
            label: 'Sightings',
            tooltip: 'Marine life you have logged',
          ),
          NavigationDestination(
            icon: Icon(Icons.biotech_outlined),
            selectedIcon: Icon(Icons.biotech),
            label: 'Species',
            tooltip: 'Species catalogue and life list',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Profile',
            tooltip: 'Your profile and settings',
          ),
        ],
      ),
    );
  }
}
