import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'auth/auth_service.dart';
import 'auth/pin/biometrics_consent_screen.dart';
import 'auth/pin/create_pin_screen.dart';
import 'auth/pin/pin_gate_screen.dart';
import 'auth/pin/pin_security_service.dart';
import 'auth/sign_in_screen.dart';
import 'eclass_app.dart';
import 'firebase_options.dart';
import 'ui/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    if (DefaultFirebaseOptions.isPlaceholder) {
      runApp(const _FirebaseNotConfiguredApp());
      return;
    }
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } else {
    await Firebase.initializeApp();
  }

  runApp(const _AuthGate());
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  static final AuthService _auth = AuthService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(),
      home: StreamBuilder<User?>(
        stream: _auth.authStateChanges(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (user == null) {
            return SignInScreen(auth: _auth);
          }
          return _PinGateChild(child: const EClassApp());
        },
      ),
    );
  }
}

class _PinGateChild extends StatefulWidget {
  const _PinGateChild({required this.child});

  final Widget child;

  @override
  State<_PinGateChild> createState() => _PinGateChildState();
}

class _PinGateChildState extends State<_PinGateChild> {
  final _security = PinSecurityService();
  bool _ready = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _ready = false;
    });

    final hasPin = await _security.hasPin();
    if (!mounted) return;

    // Enforce PIN for all signed-in users. If no PIN exists yet (old accounts),
    // force onboarding now.
    if (!hasPin) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => CreatePinScreen(security: _security),
            ),
          );
          if (!mounted) return;
          if (created != true) {
            await _security.clear();
            await FirebaseAuth.instance.signOut();
            if (!mounted) return;
            setState(() {
              _ready = false;
              _checking = false;
            });
            return;
          }

          if (!mounted) return;
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => BiometricsConsentScreen(security: _security),
            ),
          );

          if (!mounted) return;
          setState(() {
            _ready = true;
            _checking = false;
          });
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _ready = false;
            _checking = false;
          });
        }
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => PinGateScreen(security: _security)),
        );
        if (!mounted) return;
        setState(() {
          _ready = ok == true;
          _checking = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _ready = false;
          _checking = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return widget.child;
  }
}

class _FirebaseNotConfiguredApp extends StatelessWidget {
  const _FirebaseNotConfiguredApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text(
                'Firebase is not configured for Web yet.\n\n'
                'Run: flutterfire configure\n'
                'or fill in lib/firebase_options.dart',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
