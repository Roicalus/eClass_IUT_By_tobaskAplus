import 'package:flutter/material.dart';

import 'pin_palette.dart';

class PinCardScaffold extends StatelessWidget {
  const PinCardScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lightTheme = theme.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: PinPalette.bg,
      colorScheme: theme.colorScheme.copyWith(
        brightness: Brightness.light,
        primary: PinPalette.link,
        onPrimary: Colors.white,
        surface: PinPalette.bg,
        onSurface: PinPalette.textPrimary,
        outline: PinPalette.border,
        error: PinPalette.error,
      ),
      textTheme: theme.textTheme.apply(
        bodyColor: PinPalette.textPrimary,
        displayColor: PinPalette.textPrimary,
      ),
    );

    return Theme(
      data: lightTheme,
      child: Scaffold(
        backgroundColor: PinPalette.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: PinPalette.textPrimary,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.25,
                          color: PinPalette.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 15),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PinDotsRow extends StatelessWidget {
  const PinDotsRow({
    super.key,
    required this.length,
    required this.filled,
    this.error = false,
  });

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final Color strokeColor = error ? PinPalette.error : PinPalette.border;
    final Color fillColor = error ? PinPalette.error : PinPalette.link;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (index) {
        final bool isFilled = index < filled;
        return Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isFilled ? fillColor : strokeColor,
              width: 2,
            ),
            color: isFilled ? fillColor : Colors.transparent,
          ),
        );
      }),
    );
  }
}

class PinDigitPad extends StatelessWidget {
  const PinDigitPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.extraButton,
  });

  final void Function(int digit) onDigit;
  final VoidCallback onBackspace;
  final Widget? extraButton;

  @override
  Widget build(BuildContext context) {
    Widget buildCircleButton({
      required Widget child,
      required VoidCallback? onPressed,
      double size = 72,
    }) {
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: PinPalette.border.withValues(alpha: 0.20),
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Center(child: child),
            ),
          ),
        ),
      );
    }

    Widget digit(int d) => buildCircleButton(
      child: Text(
        '$d',
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: PinPalette.textPrimary,
        ),
      ),
      onPressed: () => onDigit(d),
    );

    Widget backspace() => buildCircleButton(
      child: const Icon(
        Icons.backspace_outlined,
        size: 24,
        color: PinPalette.link,
      ),
      onPressed: onBackspace,
      size: 64,
    );

    Widget empty() => const SizedBox(width: 64, height: 64);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [digit(1), digit(2), digit(3)],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [digit(4), digit(5), digit(6)],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [digit(7), digit(8), digit(9)],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [extraButton ?? empty(), digit(0), backspace()],
        ),
      ],
    );
  }
}

class PinGradientButton extends StatelessWidget {
  const PinGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [PinPalette.gradStart, PinPalette.gradEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
