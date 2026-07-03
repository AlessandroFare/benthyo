import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'onboarding_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPageData(
      icon: Icons.explore,
      title: 'Explore Dive Sites',
      description:
          'Discover thousands of dive sites worldwide with detailed maps, '
          'current conditions, and community reviews.',
      color: Color(0xFF0A2342),
    ),
    _OnboardingPageData(
      icon: Icons.book,
      title: 'Log Your Dives',
      description:
          'Quickly log dives with depth, duration, and gear — offline, '
          'on the boat, or even underwater with our streamlined interface.',
      color: Color(0xFF003D5B),
    ),
    _OnboardingPageData(
      icon: Icons.visibility,
      title: 'Record Sightings',
      description:
          'Document marine life sightings and contribute to citizen science. '
          'Verified observations feed into GBIF and OBIS.',
      color: Color(0xFF005F73),
    ),
    _OnboardingPageData(
      icon: Icons.military_tech,
      title: 'Track Your Journey',
      description:
          'Build your life list, earn badges, and watch your dive stats grow. '
          'Connect with operators and share your adventures.',
      color: Color(0xFF0A9396),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _onGetStarted();
    }
  }

  void _onSkip() {
    _pageController.animateToPage(
      _pages.length - 1,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _onGetStarted() async {
    await ref.read(onboardingNotifierProvider.notifier).complete();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _pages.length,
            itemBuilder: (context, index) => _OnboardingPage(
              data: _pages[index],
              isLastPage: index == _pages.length - 1,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: _currentPage < _pages.length - 1
                ? TextButton(
                    onPressed: _onSkip,
                    child: const Text('Skip'),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 32,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PageIndicator(
                  count: _pages.length,
                  current: _currentPage,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _onNext,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _currentPage == _pages.length - 1
                        ? 'Get Started'
                        : 'Next',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data, required this.isLastPage});

  final _OnboardingPageData data;
  final bool isLastPage;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: data.color,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(data.icon, size: 64, color: Colors.white),
            ),
            const SizedBox(height: 48),
            Text(
              data.title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              data.description,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.8),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == current ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i == current ? Colors.white : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
