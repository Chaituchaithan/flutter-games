import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/system/loading_skeleton_screen.dart';
import '../widgets/aura.dart';

/// Renders a Riverpod [AsyncValue] with the app's shared loading / error / data
/// states, so every migrated screen handles async the same way.
/// See docs/SERVICES_AND_REALTIME.md.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.onRetry,
    required this.data,
    this.loading,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T value) data;

  /// Optional custom loading placeholder; defaults to shimmering list rows.
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => loading ?? const _SkeletonList(),
      error: (_, _) => ErrorRetry(onRetry: onRetry),
    );
  }
}

/// The default loading state (mockup `LOADING SKELETON` rows): shimmering
/// placeholder rows — a 44px tile, a title line (60%) over a dimmer subtitle
/// line (38%), and a small pill on the right — shown while a service call is
/// in flight.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < 6; i++) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  const SkeletonBox(width: 44, height: 44, radius: 14),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(widthFactor: 0.6, child: SkeletonBox(height: 13, radius: 6)),
                        SizedBox(height: 8),
                        FractionallySizedBox(widthFactor: 0.38, child: SkeletonBox(height: 10, radius: 6)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const SkeletonBox(width: 54, height: 24, radius: 8),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

/// Shared "couldn't load → retry" state.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.onRetry, this.message = "Couldn't load"});
  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AuraColors.textSecondary, size: 28),
          const SizedBox(height: 10),
          Text(message, style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
          const SizedBox(height: 12),
          SecondaryButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}
