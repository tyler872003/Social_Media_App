import 'dart:async';

import 'package:flutter/material.dart';

/// Inline spinner with optional label — use inside lists, cards, or sections.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.message,
    this.size = 36,
    this.strokeWidth = 3,
  });

  final String? message;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: strokeWidth,
            color: colorScheme.primary,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Full-screen branded loading — use for auth, initial data, or page loads.
class AppLoadingScreen extends StatelessWidget {
  const AppLoadingScreen({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ColoredBox(
      color: colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/logo.jpg',
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, _, _) => Icon(
                        Icons.bolt_rounded,
                        size: 72,
                        color: colorScheme.primary,
                      ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'VibeStream',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 28),
              AppLoadingIndicator(message: message ?? 'Loading...'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Blocks interaction with a dim overlay while [isLoading] is true.
class AppLoadingOverlay extends StatelessWidget {
  const AppLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
  });

  final bool isLoading;
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.35),
              child: Center(
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 28,
                    ),
                    child: AppLoadingIndicator(
                      message: message ?? 'Please wait...',
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shows [loading] only after [delay] so fast operations don't flash a spinner.
class AppLoadingGate extends StatefulWidget {
  const AppLoadingGate({
    super.key,
    required this.isLoading,
    required this.loading,
    this.child,
    this.delay = const Duration(milliseconds: 350),
  });

  final bool isLoading;
  final Widget loading;
  final Widget? child;
  final Duration delay;

  @override
  State<AppLoadingGate> createState() => _AppLoadingGateState();
}

class _AppLoadingGateState extends State<AppLoadingGate> {
  bool _showLoading = false;
  Timer? _timer;

  @override
  void didUpdateWidget(covariant AppLoadingGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!widget.isLoading) {
      if (_showLoading) setState(() => _showLoading = false);
      return;
    }
    _timer = Timer(widget.delay, () {
      if (mounted && widget.isLoading) {
        setState(() => _showLoading = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && _showLoading) {
      return widget.loading;
    }
    return widget.child ?? const SizedBox.shrink();
  }
}

/// Global overlay for async work — call [show] before and [hide] in finally.
class AppLoading {
  AppLoading._();

  static OverlayEntry? _entry;

  static void show(BuildContext context, {String? message}) {
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder:
          (ctx) => Material(
            color: Colors.black.withValues(alpha: 0.35),
            child: Center(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(ctx).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 28,
                  ),
                  child: AppLoadingIndicator(
                    message: message ?? 'Please wait...',
                  ),
                ),
              ),
            ),
          ),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}
