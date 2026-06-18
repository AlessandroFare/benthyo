import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainNavigationBar extends StatelessWidget {
  const MainNavigationBar({super.key, required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (i) {
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
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: 'My Dives',
          tooltip: 'Your dive logbook',
        ),
        // "Sightings" = the things you saw on dives; distinct from the
        // "Species" catalogue. Eye icon = what I observed.
        NavigationDestination(
          icon: Icon(Icons.remove_red_eye_outlined),
          selectedIcon: Icon(Icons.remove_red_eye),
          label: 'Sightings',
          tooltip: 'Marine life you have logged',
        ),
        // "Species" = the reference catalogue / life list.
        NavigationDestination(
          icon: Icon(Icons.travel_explore_outlined),
          selectedIcon: Icon(Icons.travel_explore),
          label: 'Species',
          tooltip: 'Species catalogue and life list',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
          tooltip: 'Your profile and settings',
        ),
      ],
    );
  }
}
