import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/aura_widgets.dart';
import 'slide_illustrations.dart';

/// Data for a single onboarding slide.
class _Slide {
  const _Slide({
    required this.art,
    required this.title,
    required this.body,
  });

  final Widget art;
  final String title;
  final String body;
}

const _slides = <_Slide>[
  _Slide(
    art: FindYourPeopleArt(),
    title: 'Find your people',
    body: 'Join circles that get you. Discover communities built around '
        'what you actually love.',
  ),
  _Slide(
    art: ShareYourMomentArt(),
    title: 'Share your moment',
    body: 'Post what moves you and watch the reactions roll in. Every share '
        'starts a conversation.',
  ),
  _Slide(
    art: AlwaysInSyncArt(),
    title: 'Always in sync',
    body: "See who's around in real time. Jump into live rooms and never "
        'miss the energy.',
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    }
  }

  void _finish() {
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraColors.background,
      body: AuraBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Skip, top-right. Reserve the row height so the layout stays
              // stable, but drop the button entirely on the last slide.
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _isLast
                      ? null
                      : TextButton(
                          onPressed: _finish,
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              color: AuraColors.skip,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                ),
              ),
              // Slides.
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
                ),
              ),
              const SizedBox(height: 8),
              AuraPageIndicator(count: _slides.length, index: _index),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: GradientButton(
                  label: _isLast ? 'Get Started' : 'Continue',
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: slide.art),
            ),
          ),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: AuraText.headline.copyWith(fontSize: 28),
          ),
          const SizedBox(height: 12),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: AuraText.body.copyWith(color: AuraColors.textSecondary, height: 1.55),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
