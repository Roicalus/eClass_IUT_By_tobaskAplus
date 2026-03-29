import 'package:flutter/material.dart';

import 'pin_security_service.dart';
import 'pin_widgets.dart';
import 'pin_palette.dart';

class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({super.key, required this.security});

  final PinSecurityService security;

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  static const int _pinLength = 4;

  String _first = '';
  String _confirm = '';
  bool _confirmStep = false;
  bool _error = false;

  void _append(int digit) {
    if (_error) {
      setState(() => _error = false);
    }

    setState(() {
      if (!_confirmStep) {
        if (_first.length < _pinLength) {
          _first += digit.toString();
          if (_first.length == _pinLength) {
            _confirmStep = true;
          }
        }
      } else {
        if (_confirm.length < _pinLength) {
          _confirm += digit.toString();
          if (_confirm.length == _pinLength) {
            _finishIfMatch();
          }
        }
      }
    });
  }

  void _backspace() {
    if (_error) {
      setState(() => _error = false);
    }

    setState(() {
      if (!_confirmStep) {
        if (_first.isNotEmpty) {
          _first = _first.substring(0, _first.length - 1);
        }
      } else {
        if (_confirm.isNotEmpty) {
          _confirm = _confirm.substring(0, _confirm.length - 1);
        } else {
          _confirmStep = false;
        }
      }
    });
  }

  Future<void> _finishIfMatch() async {
    if (_confirm != _first) {
      setState(() {
        _error = true;
        _confirm = '';
      });
      return;
    }

    await widget.security.setPin(_first);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _reset() {
    setState(() {
      _first = '';
      _confirm = '';
      _confirmStep = false;
      _error = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String subtitle = _confirmStep
        ? 'Re-enter your 4-digit PIN to confirm.'
        : 'Create a 4-digit PIN to protect your account on this device.';

    final int filled = _confirmStep ? _confirm.length : _first.length;

    return PinCardScaffold(
      title: 'Create a PIN',
      subtitle: subtitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PinDotsRow(length: _pinLength, filled: filled, error: _error),
          const SizedBox(height: 9),
          if (_error)
            const Text(
              'PINs do not match. Try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: PinPalette.error,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Text(
              _confirmStep ? 'Confirm PIN' : 'Enter PIN',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PinPalette.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 13),
          PinDigitPad(
            onDigit: _append,
            onBackspace: _backspace,
            extraButton: TextButton(
              onPressed: _reset,
              child: const Text(
                'Reset',
                style: TextStyle(
                  color: PinPalette.link,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
