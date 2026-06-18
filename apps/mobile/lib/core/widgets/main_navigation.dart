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
            context.go('/sightings');
          case 2:
            context.go('/dive-logs');
          case 3:
            context.go('/species');
          case 4:
            context.go('/profile');
        }
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
        NavigationDestination(icon: Icon(Icons.visibility), label: 'Sightings'),
        NavigationDestination(icon: Icon(Icons.book), label: 'Logs'),
        NavigationDestination(icon: Icon(Icons.pets), label: 'Species'),
        NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}
