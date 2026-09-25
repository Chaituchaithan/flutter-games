import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/system/loading_skeleton_screen.dart';
import '../widgets/aura.dart';

/// Renders a Riverpod [AsyncValue] with the app's shared loading / error / data
/// states, so every migrated screen handles async the same way.
/// See docs/INTEGRATION_PLAN.md §4.
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

/// A shimmering list of placeholder rows — the default loading state.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < 5; i++) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: AuraGlass.decoration(radius: 16),
              child: Row(
                children: [
                  const SkeletonBox(height: 40, shape: BoxShape.circle),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonBox(width: 130, height: 13),
                      SizedBox(height: 8),
                      SkeletonBox(width: 90, height: 10),
                    ],
                  ),
                  const Spacer(),
                  const SkeletonBox(width: 46, height: 22, radius: 11),
                ],
              ),
            ),
            const SizedBox(height: 10),
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
