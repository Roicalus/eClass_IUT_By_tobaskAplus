import 'package:flutter/material.dart';

import 'pin_security_service.dart';
import 'pin_widgets.dart';
import 'pin_palette.dart';

class BiometricsConsentScreen extends StatefulWidget {
  const BiometricsConsentScreen({super.key, required this.security});

  final PinSecurityService security;

  @override
  State<BiometricsConsentScreen> createState() =>
      _BiometricsConsentScreenState();
}

class _BiometricsConsentScreenState extends State<BiometricsConsentScreen> {
  bool _supported = false;
  bool _loading = true;
  bool _enable = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool canUse = await widget.security.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _supported = canUse;
      _loading = false;
      _enable = canUse;
    });
  }

  Future<void> _continue() async {
    setState(() => _error = null);

    if (_supported && _enable) {
      final ok = await widget.security.authenticateWithBiometrics();
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _enable = false;
          _error = null;
        });
        await widget.security.setBiometricsEnabled(false);
      } else {
        await widget.security.setBiometricsEnabled(true);
      }
    } else {
      await widget.security.setBiometricsEnabled(false);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PinCardScaffold(
      title: 'Use biometrics?',
      subtitle: 'You can use Face ID / fingerprint to unlock faster.',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: PinPalette.border),
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Enable biometrics',
                                style: TextStyle(
                                  color: PinPalette.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _supported
                                    ? 'Requires device support and confirmation.'
                                    : 'Not supported on this device.',
                                style: const TextStyle(
                                  color: PinPalette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _supported && _enable,
                          onChanged: _supported
                              ? (v) => setState(() => _enable = v)
                              : null,
                          activeThumbColor: PinPalette.link,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'By enabling biometrics, you allow this device to use your biometric credentials to unlock the app. You can change this later in settings.',
                  style: TextStyle(
                    color: PinPalette.textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 9),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: PinPalette.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 9),
                PinGradientButton(label: 'Continue', onPressed: _continue),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    await widget.security.setBiometricsEnabled(false);
                    if (!context.mounted) return;
                    Navigator.of(context).pop(true);
                  },
                  child: const Text(
                    'Not now',
                    style: TextStyle(
                      color: PinPalette.link,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
