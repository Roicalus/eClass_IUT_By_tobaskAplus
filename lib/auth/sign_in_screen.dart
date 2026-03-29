import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'legal_screen.dart';
import '../ui/app_theme.dart';
import 'pin/biometrics_consent_screen.dart';
import 'pin/create_pin_screen.dart';
import 'pin/pin_security_service.dart';

enum _AuthMode { signIn, signUp }

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _loading = false;
  String? _error;

  _AuthMode _mode = _AuthMode.signIn;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _patronymicController = TextEditingController();

  bool _showPassword = false;

  bool _acceptedTerms = false;
  bool _showTermsError = false;

  final _pinSecurity = PinSecurityService();

  // Palette: blue/cyan family (matches provided swatches)
  static const _cCardBg = Color(0xFFFFFFFF);
  static const _cFieldBg = Color(0xFFFFFFFF);
  static const _cTextPrimary = AppTheme.ink;
  static const _cTextSecondary = AppTheme.muted;
  static const _cBorder = AppTheme.line;
  static const _cLink = AppTheme.brand;
  static const _cError = AppTheme.danger;
  static const _cTermsBg = Color(0xFFF3F4F6);
  static const _cWarn = AppTheme.warning;
  static const _gradStart = AppTheme.brandBright;
  static const _gradEnd = AppTheme.brandDeep;

  String _passwordStrengthLabel(String password) {
    final score = _passwordStrengthScore(password);
    switch (score) {
      case 0:
        return 'Very weak';
      case 1:
        return 'Weak';
      case 2:
        return 'Medium';
      case 3:
        return 'Good';
      default:
        return 'Strong';
    }
  }

  int _passwordStrengthScore(String password) {
    final p = password;
    if (p.isEmpty) return 0;

    var points = 0;
    if (p.length >= 8) points++;
    if (RegExp(r'[A-Z]').hasMatch(p)) points++;
    if (RegExp(r'[0-9]').hasMatch(p)) points++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) points++;
    if (p.length >= 12) points++;

    // Map to 0..4
    if (points <= 1) return 0;
    if (points == 2) return 1;
    if (points == 3) return 2;
    if (points == 4) return 3;
    return 4;
  }

  bool get _isPasswordStrongEnough {
    if (_mode != _AuthMode.signUp) return true;
    return _passwordStrengthScore(_passwordController.text) >= 2;
  }

  Color _passwordStrengthColor(String password) {
    final score = _passwordStrengthScore(password);
    if (score <= 1) return _cError;
    if (score == 2) return _cWarn;
    return _cLink;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _patronymicController.dispose();
    super.dispose();
  }

  void _openLegal(LegalDoc doc) {
    Navigator.of(context).push(LegalScreen.route(doc));
  }

  Future<void> _signInWithGoogle() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.auth.signInWithGoogle();

      final hasPin = await _pinSecurity.hasPin();
      if (!mounted) return;
      if (!hasPin) {
        final created = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => CreatePinScreen(security: _pinSecurity),
          ),
        );
        if (created != true) {
          await _pinSecurity.clear();
          await widget.auth.signOut();
          return;
        }

        if (!mounted) return;
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => BiometricsConsentScreen(security: _pinSecurity),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitEmailFlow() async {
    if (_loading) return;
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      if (_mode == _AuthMode.signUp && !_isPasswordStrongEnough) {
        setState(() {
          _error = 'Password strength must be Medium or higher';
        });
        return;
      }
      final ok = _formKey.currentState?.validate() ?? false;
      if (!ok) return;

      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (_mode == _AuthMode.signUp) {
        await widget.auth.signUpWithEmail(email: email, password: password);

        if (!mounted) return;
        final created = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => CreatePinScreen(security: _pinSecurity),
          ),
        );
        if (created != true) {
          await _pinSecurity.clear();
          await widget.auth.signOut();
          return;
        }

        if (!mounted) return;
        final consented = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => BiometricsConsentScreen(security: _pinSecurity),
          ),
        );
        if (consented != true) {
          // If user backs out, keep PIN but disable biometrics.
          await _pinSecurity.setBiometricsEnabled(false);
        }
      } else {
        await widget.auth.signInWithEmail(email: email, password: password);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String? _requiredText(String? v, {required String label}) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return '$label is required';
    return null;
  }

  String? _emailValidator(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Email is required';
    final at = value.indexOf('@');
    if (at <= 0 || at == value.length - 1) return 'Enter a valid email';
    return null;
  }

  String? _passwordValidator(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Password is required';
    if (_mode == _AuthMode.signUp && value.length < 8) {
      return 'Minimum 8 characters';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final inputTheme = InputDecorationTheme(
      filled: true,
      fillColor: _cFieldBg,
      labelStyle: const TextStyle(color: _cTextSecondary),
      hintStyle: const TextStyle(color: _cTextSecondary),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _cBorder),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _cLink, width: 1.6),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      errorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _cError),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _cError, width: 1.6),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.pageGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AuthHeroPanel(mode: _mode),
                    const SizedBox(height: 14),
                    Card(
                      elevation: 0,
                      color: _cCardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: const BorderSide(color: _cBorder),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _loading ? null : _signInWithGoogle,
                                icon: const Icon(Icons.login),
                                label: Text(
                                  _loading
                                      ? 'Please wait...'
                                      : 'Continue with Google',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _cLink,
                                  side: const BorderSide(color: _cBorder),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: Divider(color: _cBorder)),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'or',
                                    style: TextStyle(color: _cTextSecondary),
                                  ),
                                ),
                                Expanded(child: Divider(color: _cBorder)),
                              ],
                            ),
                            const SizedBox(height: 9),
                            Theme(
                              data: Theme.of(context).copyWith(
                                inputDecorationTheme: inputTheme,
                                textSelectionTheme:
                                    const TextSelectionThemeData(
                                      cursorColor: _cLink,
                                      selectionHandleColor: _cLink,
                                    ),
                                checkboxTheme: CheckboxThemeData(
                                  side: const BorderSide(color: _cBorder),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  fillColor: WidgetStateProperty.resolveWith(
                                    (states) =>
                                        states.contains(WidgetState.selected)
                                        ? _cLink
                                        : Colors.transparent,
                                  ),
                                  checkColor: const WidgetStatePropertyAll(
                                    Colors.white,
                                  ),
                                ),
                                dividerTheme: const DividerThemeData(
                                  color: _cBorder,
                                ),
                                textButtonTheme: TextButtonThemeData(
                                  style: TextButton.styleFrom(
                                    foregroundColor: _cLink,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    if (_mode == _AuthMode.signUp) ...[
                                      TextFormField(
                                        controller: _firstNameController,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.givenName,
                                        ],
                                        style: const TextStyle(
                                          color: _cTextPrimary,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: 'First name *',
                                          border: OutlineInputBorder(),
                                        ),
                                        validator: (v) => _requiredText(
                                          v,
                                          label: 'First name',
                                        ),
                                      ),
                                      const SizedBox(height: 9),
                                      TextFormField(
                                        controller: _lastNameController,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.familyName,
                                        ],
                                        style: const TextStyle(
                                          color: _cTextPrimary,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: 'Last name (optional)',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 9),
                                      TextFormField(
                                        controller: _patronymicController,
                                        textInputAction: TextInputAction.next,
                                        style: const TextStyle(
                                          color: _cTextPrimary,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: 'Patronymic (optional)',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 9),
                                    ],
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [
                                        AutofillHints.email,
                                      ],
                                      style: const TextStyle(
                                        color: _cTextPrimary,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Email',
                                      ),
                                      validator: _emailValidator,
                                    ),
                                    const SizedBox(height: 9),
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: !_showPassword,
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const [
                                        AutofillHints.password,
                                      ],
                                      style: const TextStyle(
                                        color: _cTextPrimary,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Password',
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(
                                            () =>
                                                _showPassword = !_showPassword,
                                          ),
                                          icon: Icon(
                                            _showPassword
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: _cTextSecondary,
                                          ),
                                        ),
                                      ),
                                      validator: _passwordValidator,
                                      onChanged: (_) {
                                        if (_mode == _AuthMode.signUp) {
                                          setState(() {
                                            _error = null;
                                          });
                                        }
                                      },
                                      onFieldSubmitted: (_) {
                                        if (_mode == _AuthMode.signUp &&
                                            !_acceptedTerms) {
                                          setState(
                                            () => _showTermsError = true,
                                          );
                                          return;
                                        }
                                        if (_mode == _AuthMode.signUp &&
                                            !_isPasswordStrongEnough) {
                                          setState(() {
                                            _error =
                                                'Password strength must be Medium or higher';
                                          });
                                          return;
                                        }
                                        _submitEmailFlow();
                                      },
                                    ),

                                    if (_mode == _AuthMode.signUp &&
                                        _passwordController
                                            .text
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              child: SizedBox(
                                                height: 6,
                                                child: LinearProgressIndicator(
                                                  value:
                                                      (_passwordStrengthScore(
                                                            _passwordController
                                                                .text,
                                                          ) +
                                                          1) /
                                                      5,
                                                  backgroundColor: _cBorder,
                                                  valueColor:
                                                      AlwaysStoppedAnimation(
                                                        _passwordStrengthColor(
                                                          _passwordController
                                                              .text,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _passwordStrengthLabel(
                                              _passwordController.text,
                                            ),
                                            style: TextStyle(
                                              color: _passwordStrengthColor(
                                                _passwordController.text,
                                              ),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (_mode == _AuthMode.signUp) ...[
                                      const SizedBox(height: 10),
                                      Material(
                                        color: _cTermsBg,
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          child: Column(
                                            children: [
                                              CheckboxListTile(
                                                value: _acceptedTerms,
                                                onChanged: _loading
                                                    ? null
                                                    : (v) {
                                                        setState(() {
                                                          _acceptedTerms =
                                                              v ?? false;
                                                          if (_acceptedTerms) {
                                                            _showTermsError =
                                                                false;
                                                          }
                                                        });
                                                      },
                                                controlAffinity:
                                                    ListTileControlAffinity
                                                        .leading,
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                title: const Text(
                                                  'I have read and agree',
                                                  style: TextStyle(
                                                    color: _cTextPrimary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                subtitle: Wrap(
                                                  spacing: 8,
                                                  runSpacing: 0,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    TextButton(
                                                      onPressed: _loading
                                                          ? null
                                                          : () => _openLegal(
                                                              LegalDoc.terms,
                                                            ),
                                                      child: const Text(
                                                        'Terms',
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: _loading
                                                          ? null
                                                          : () => _openLegal(
                                                              LegalDoc.privacy,
                                                            ),
                                                      child: const Text(
                                                        'Privacy Policy',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (_showTermsError)
                                                Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 12,
                                                          bottom: 6,
                                                        ),
                                                    child: const Text(
                                                      'Please accept Terms to continue',
                                                      style: TextStyle(
                                                        color: _cError,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 9),
                                    SizedBox(
                                      width: double.infinity,
                                      child: _GradientButton(
                                        enabled:
                                            !_loading &&
                                            _isPasswordStrongEnough,
                                        onPressed: () {
                                          if (_mode == _AuthMode.signUp &&
                                              !_acceptedTerms) {
                                            setState(
                                              () => _showTermsError = true,
                                            );
                                            return;
                                          }
                                          if (_mode == _AuthMode.signUp &&
                                              !_isPasswordStrongEnough) {
                                            setState(() {
                                              _error =
                                                  'Password strength must be Medium or higher';
                                            });
                                            return;
                                          }
                                          _submitEmailFlow();
                                        },
                                        child: Text(
                                          _mode == _AuthMode.signUp
                                              ? 'Create account'
                                              : 'Login',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_error != null)
                              Text(
                                _error!,
                                style: TextStyle(color: _cError),
                                textAlign: TextAlign.center,
                              ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _mode = _mode == _AuthMode.signIn
                                      ? _AuthMode.signUp
                                      : _AuthMode.signIn;
                                  _error = null;
                                  _acceptedTerms = false;
                                  _showTermsError = false;
                                });
                              },
                              child: Text(
                                _mode == _AuthMode.signIn
                                    ? 'Don\'t have an account? Sign Up'
                                    : 'Already have an account? Sign In',
                                style: const TextStyle(
                                  color: _cLink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (_mode != _AuthMode.signUp)
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 0,
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        _openLegal(LegalDoc.privacy),
                                    style: TextButton.styleFrom(
                                      foregroundColor: _cLink,
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    child: const Text('Privacy Policy'),
                                  ),
                                  TextButton(
                                    onPressed: () => _openLegal(LegalDoc.terms),
                                    style: TextButton.styleFrom(
                                      foregroundColor: _cLink,
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    child: const Text('Terms'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
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

class _AuthHeroPanel extends StatelessWidget {
  const _AuthHeroPanel({required this.mode});

  final _AuthMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandDeep.withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.school_rounded, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            'eClass IUT',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mode == _AuthMode.signIn
                ? 'Sign in to continue with a cleaner, faster teaching workspace.'
                : 'Create your account and set up secure access in a few steps.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.enabled,
    required this.onPressed,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: enabled
              ? const [
                  _SignInScreenState._gradStart,
                  _SignInScreenState._gradEnd,
                ]
              : const [
                  _SignInScreenState._cBorder,
                  _SignInScreenState._cBorder,
                ],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
