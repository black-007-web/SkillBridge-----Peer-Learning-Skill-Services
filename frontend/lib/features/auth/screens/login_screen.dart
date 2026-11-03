import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../providers/auth_provider.dart';

// ─────────────────────────────────────────────────────────────
// Design tokens — mapped from Watermelon UI "auth-10":
// near-black page, neutral-800 field borders, 12px field radius,
// 14px blue primary button, outlined social buttons, gradient hero.
// ─────────────────────────────────────────────────────────────
const _bg = Color(0xFF050505);
const _fieldFill = Color(0xFF0B0B0B);
const _line = Color(0xFF262626); // neutral-800
const _lineStrong = Color(0xFF404040); // neutral-700
const _lineFocus = Color(0xFF525252); // neutral-600
const _muted = Color(0xFF737373); // neutral-500
const _soft = Color(0xFFA3A3A3); // neutral-400
const _text = Color(0xFFE5E5E5); // neutral-200
const _brand = Color(0xFF0C74B4);
const _brandHover = Color(0xFF0A6299);
const _danger = Color(0xFFF87171);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.nextPath = '/'});

  final String nextPath;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _showPassword = false;
  bool _needsRegistrationConfirmation = false;
  String? _error;

  // UI-only: staggered entrance (like framer-motion staggerChildren)
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _intro.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || _googleLoading || !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final auth = ref.read(authServiceProvider);
    if (auth == null) {
      setState(() => _error = 'Connect Supabase to sign in.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _needsRegistrationConfirmation = false;
    });
    try {
      await auth.login(email: _email.text, password: _password.text);
      if (mounted) context.go(_safeNextPath(widget.nextPath));
    } on AuthException catch (error) {
      if (!mounted) return;
      final unverified = error.message.toLowerCase().contains(
        'email not confirmed',
      );
      setState(() {
        _error = unverified
            ? 'Confirm the email address used during registration before signing in.'
            : _friendlyAuthError(error);
        _needsRegistrationConfirmation = unverified;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not sign in. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    final auth = ref.read(authServiceProvider);
    if (auth == null || _loading || _googleLoading) return;
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await auth.signInWithGoogle();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Google sign-in could not start. Check OAuth configuration.',
        );
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  // ───────────────────────────────────────────────────────────
  // UI — presentation only
  // ───────────────────────────────────────────────────────────

  /// Fade + 15px rise, staggered by [i] (≈ itemVariants / staggerChildren).
  Widget _item(int i, Widget child) {
    final start = math.min(i * 0.07, 0.6);
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, math.min(1.0, start + 0.4), curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(
          offset: Offset(0, 15 * (1 - anim.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  ThemeData _theme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: _bg,
      colorScheme: const ColorScheme.dark(
        primary: _brand,
        onPrimary: Colors.white,
        surface: _bg,
        error: _danger,
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.white),
    );
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _muted, fontSize: 14),
      prefixIcon: Icon(icon, size: 20, color: _muted),
      suffixIcon: suffix,
      filled: true,
      fillColor: _fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(_line),
      enabledBorder: border(_line),
      disabledBorder: border(_line),
      focusedBorder: border(_lineFocus),
      errorBorder: border(_danger.withValues(alpha: .7)),
      focusedErrorBorder: border(_danger),
      errorStyle: const TextStyle(color: _danger, fontSize: 12),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: _text,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _googleLoading;
    final auth = ref.watch(authServiceProvider);

    final form = _formPanel(busy: busy, auth: auth);

    return Theme(
      data: _theme(),
      child: Scaffold(
        backgroundColor: _bg,
        body: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 900;
            if (wide) {
              return Row(
                children: [
                  const Expanded(child: _HeroPanel(compact: false)),
                  Expanded(
                    child: SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(48),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: form,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            return SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 300, child: _HeroPanel(compact: true)),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: form,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _formPanel({required bool busy, required dynamic auth}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _item(
          0,
          const Padding(
            padding: EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -.6,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Sign in and pick up where your learning left off.',
                  style: TextStyle(fontSize: 14, color: _soft, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          _ErrorBanner(
            message: _error!,
            action: _needsRegistrationConfirmation
                ? TextButton(
                    onPressed: busy
                        ? null
                        : () => context.go(
                            '/check-email?email=${Uri.encodeQueryComponent(_email.text.trim())}',
                          ),
                    child: const Text('Confirm registration'),
                  )
                : null,
          ),
          const SizedBox(height: 16),
        ],
        if (auth == null) ...[
          const _ErrorBanner(
            message:
                'Supabase is not configured. Use the setup guide in backend/README.md.',
          ),
          const SizedBox(height: 16),
        ],
        AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _item(
                  1,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Email address'),
                      TextFormField(
                        controller: _email,
                        enabled: !busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: _decoration(
                          hint: 'Enter your email',
                          icon: Icons.mail_outline_rounded,
                        ),
                        validator: (value) => _validEmail(value?.trim() ?? '')
                            ? null
                            : 'Enter a valid email address',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _item(
                  2,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Password'),
                      TextFormField(
                        controller: _password,
                        enabled: !busy,
                        obscureText: !_showPassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: _decoration(
                          hint: '••••••••••••',
                          icon: Icons.lock_outline_rounded,
                          suffix: IconButton(
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                key: ValueKey(_showPassword),
                                size: 20,
                                color: _muted,
                              ),
                            ),
                          ),
                        ),
                        validator: (value) => (value ?? '').isNotEmpty
                            ? null
                            : 'Enter your password',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _item(
          3,
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: _soft,
                textStyle: const TextStyle(fontSize: 13),
              ),
              onPressed: busy ? null : () => context.push('/forgot-password'),
              child: const Text('Forgot password?'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _item(
          4,
          _PressScale(
            child: SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  disabledBackgroundColor: _brand.withValues(alpha: .5),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  overlayColor: _brandHover,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onPressed: busy ? null : _submit,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _loading
                      ? const SizedBox.square(
                          key: ValueKey('spin'),
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Log in', key: ValueKey('label')),
                ),
              ),
            ),
          ),
        ),
        _item(
          5,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Row(
              children: [
                Expanded(child: Divider(color: _line, height: 1)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Or',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                ),
                Expanded(child: Divider(color: _line, height: 1)),
              ],
            ),
          ),
        ),
        _item(
          6,
          Row(
            children: [
              Expanded(
                child: _SocialButton(
                  label: 'Sign in with Google',
                  loading: _googleLoading,
                  leading: const _GoogleG(size: 18),
                  onPressed: auth == null || busy ? null : _google,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SocialButton(
                  label: 'Preview mode',
                  leading: const Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: Colors.white,
                  ),
                  onPressed: () => context.go('/'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        _item(
          7,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'New to SkillBridge?',
                style: TextStyle(fontSize: 13, color: _soft),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: _brand,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 36),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: busy ? null : () => context.go('/register'),
                child: const Text('Create account'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Hero panel — gradient "image" side with drifting light blobs,
// floating glass chips, brand mark and tagline.
// ─────────────────────────────────────────────────────────────
class _HeroPanel extends StatefulWidget {
  const _HeroPanel({required this.compact});
  final bool compact;
  @override
  State<_HeroPanel> createState() => _HeroPanelState();
}

class _HeroPanelState extends State<_HeroPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _blob(double t, double phase, Color color, double size, Offset base) {
    final a = 2 * math.pi * (t + phase);
    return Align(
      alignment: Alignment(
        base.dx + .25 * math.sin(a),
        base.dy + .2 * math.cos(a * .9),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }

  Widget _chip(double t, double phase, Alignment at, IconData icon) {
    final dy = 6 * math.sin(2 * math.pi * (t + phase));
    return Align(
      alignment: at,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .35)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    return ClipRRect(
      borderRadius: compact
          ? const BorderRadius.vertical(bottom: Radius.circular(28))
          : BorderRadius.zero,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFD9ECFF),
                      Color(0xFF7DB2F5),
                      Color(0xFF2F4FB8),
                      Color(0xFF111A4A),
                    ],
                    stops: [0, .35, .7, 1],
                  ),
                ),
              ),
              _blob(t, 0, const Color(0xCCFFD2E8), 360, const Offset(-.6, -.5)),
              _blob(t, .35, const Color(0xBB7CF2FF), 320, const Offset(.7, -.1)),
              _blob(t, .7, const Color(0x99B58CFF), 380, const Offset(-.2, .7)),
              _chip(t, 0, const Alignment(-.72, -.35), Icons.school_outlined),
              _chip(t, .33, const Alignment(.75, -.55), Icons.forum_outlined),
              if (!compact)
                _chip(t, .66, const Alignment(.55, .05),
                    Icons.workspace_premium_outlined),
              // legibility scrim for the bottom copy
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x73000000)],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(compact ? 24 : 48),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'SkillBridge',
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: compact ? 26 : 36,
                          letterSpacing: -.5,
                          color: Colors.black,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Learn together',
                        style: TextStyle(
                          fontSize: compact ? 14 : 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: .9),
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 16),
                      Text(
                        compact
                            ? 'Your personal hub for peer learning and practical skills'
                            : 'Get access to your personal\nhub for peer learning and\npractical skills',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 20 : 44,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                          letterSpacing: -.8,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: compact ? 4 : 24),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.action});
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _danger.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _danger.withValues(alpha: .35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.error_outline_rounded, size: 18, color: _danger),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(color: _text, fontSize: 13, height: 1.4),
              ),
              if (action != null) action!,
            ],
          ),
        ),
      ],
    ),
  );
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.leading,
    required this.onPressed,
    this.loading = false,
  });
  final String label;
  final Widget leading;
  final VoidCallback? onPressed;
  final bool loading;
  @override
  Widget build(BuildContext context) => _PressScale(
    child: SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: _lineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: 10),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}

/// Subtle press-down scale (≈ `active:scale-[0.98]`).
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child});
  final Widget child;
  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => _down = true),
    onPointerUp: (_) => setState(() => _down = false),
    onPointerCancel: (_) => setState(() => _down = false),
    child: AnimatedScale(
      scale: _down ? .98 : 1,
      duration: const Duration(milliseconds: 110),
      child: widget.child,
    ),
  );
}

/// Lightweight 4-colour Google "G" (no asset needed).
class _GoogleG extends StatelessWidget {
  const _GoogleG({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .2;
    final r = size.width / 2 - stroke / 2;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r);
    Paint p(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color;
    double rad(double deg) => deg * math.pi / 180;
    canvas.drawArc(rect, rad(200), rad(115), false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, rad(125), rad(75), false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, rad(35), rad(90), false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, rad(-45), rad(80), false, p(const Color(0xFF4285F4)));
    canvas.drawLine(
      c,
      Offset(c.dx + r + stroke / 2, c.dy),
      p(const Color(0xFF4285F4)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

bool _validEmail(String email) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

String _friendlyAuthError(AuthException error) {
  final message = error.message.toLowerCase();
  if (message.contains('invalid login credentials')) {
    return 'Email or password is incorrect.';
  }
  if (message.contains('rate limit')) {
    return 'Too many attempts. Wait a little and try again.';
  }
  return error.message;
}

String _safeNextPath(String value) {
  const allowed = {
    '/',
    '/profile',
    '/profile/edit',
    '/notifications',
    '/settings',
    '/settings/change-password',
    '/settings/delete-account',
  };
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !allowed.contains(uri.path)) {
    return '/';
  }
  return uri.toString();
}