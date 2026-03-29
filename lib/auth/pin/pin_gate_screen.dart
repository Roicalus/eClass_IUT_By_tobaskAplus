import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'pin_security_service.dart';
import 'pin_widgets.dart';
import 'pin_palette.dart';

class PinGateScreen extends StatefulWidget {
  const PinGateScreen({super.key, required this.security});

  final PinSecurityService security;

  @override
  State<PinGateScreen> createState() => _PinGateScreenState();
}

class _PinGateScreenState extends State<PinGateScreen> {
  static const int _pinLength = 4;

  String _pin = '';
  bool _error = false;
  bool _checking = false;
  bool _biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.security.isBiometricsEnabled();
    final canUse = enabled && await widget.security.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _biometricsAvailable = canUse;
    });

    if (canUse) {
      // Best-effort: prompt immediately.
      await _tryBiometrics();
    }
  }

  Future<void> _tryBiometrics() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = false;
    });
    final ok = await widget.security.authenticateWithBiometrics();
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  void _append(int digit) {
    if (_checking) return;
    if (_error) {
      setState(() => _error = false);
    }

    setState(() {
      if (_pin.length < _pinLength) {
        _pin += digit.toString();
        if (_pin.length == _pinLength) {
          _verify();
        }
      }
    });
  }

  void _backspace() {
    if (_checking) return;
    if (_error) {
      setState(() => _error = false);
    }

    setState(() {
      if (_pin.isNotEmpty) {
        _pin = _pin.substring(0, _pin.length - 1);
      }
    });
  }

  Future<void> _verify() async {
    if (_checking) return;

    setState(() => _checking = true);
    final ok = await widget.security.verifyPin(_pin);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _checking = false;
        _error = true;
        _pin = '';
      });
    }
  }

  Future<void> _forgotPin() async {
    await widget.security.clear();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: PinCardScaffold(
        title: 'Enter PIN',
        subtitle: '',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56, color: PinPalette.link),
            const SizedBox(height: 9),
            PinDotsRow(length: _pinLength, filled: _pin.length, error: _error),
            const SizedBox(height: 9),
            if (_checking)
              const Text(
                'Checking…',
                style: TextStyle(color: PinPalette.textSecondary),
              )
            else if (_error)
              const Text(
                'Incorrect PIN. Try again.',
                style: TextStyle(
                  color: PinPalette.error,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              const Text(
                ' ',
                style: TextStyle(color: PinPalette.textSecondary),
              ),
            const SizedBox(height: 13),
            PinDigitPad(
              onDigit: _append,
              onBackspace: _backspace,
              extraButton: _biometricsAvailable
                  ? SizedBox(
                      width: 56,
                      height: 56,
                      child: IconButton(
                        onPressed: _tryBiometrics,
                        icon: const Icon(
                          Icons.fingerprint,
                          color: PinPalette.link,
                          size: 28,
                        ),
                      ),
                    )
                  : const SizedBox(width: 56, height: 56),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _forgotPin,
                child: const Text(
                  'Forgot PIN?',
                  style: TextStyle(
                    color: PinPalette.link,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
