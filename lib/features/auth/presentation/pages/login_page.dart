import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/auth/data/auth_repository.dart';
import 'package:echo/features/auth/providers/auth_provider.dart';
import 'package:echo/shared/widgets/glass_card.dart';
import 'package:echo/shared/widgets/glass_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late final AnimationController _anim;

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Widget _slide(Widget child, double start, double end) {
    final curve = CurvedAnimation(
      parent: _anim,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(email: _emailCtrl.text, password: _passwordCtrl.text);
      // Router redirect handles navigation
    } on EchoAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          _Background(isDark: isDark),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 32),

                      // ── Titolo typewriter ──────────────────────────────────
                      _EchoTitle(animation: _anim),
                      const SizedBox(height: 10),

                      // ── Subtitle — compare dopo la fine del titolo ─────────
                      _slide(
                        Text(
                          'Il mondo ricorda.',
                          style: AppTextStyles.bodySecondary(context),
                          textAlign: TextAlign.center,
                        ),
                        0.33,
                        0.52,
                      ),

                      const SizedBox(height: 48),

                      // ── Form card ──────────────────────────────────────────
                      _slide(
                        GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Accedi',
                                  style: AppTextStyles.headline(context),
                                ),
                                const SizedBox(height: 24),
                                _Field(
                                  controller: _emailCtrl,
                                  label: 'Email',
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Inserisci l\'email';
                                    }
                                    if (!v.contains('@'))
                                      return 'Email non valida';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _Field(
                                  controller: _passwordCtrl,
                                  label: 'Password',
                                  obscureText: _obscure,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Inserisci la password';
                                    }
                                    return null;
                                  },
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFE8879C),
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  height: 40,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: AppColors.primary,
                                      disabledBackgroundColor: AppColors.accent
                                          .withValues(alpha: 0.4),
                                      shape: const StadiumBorder(),
                                    ),
                                    child: _loading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Accedi'),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                GestureDetector(
                                  onTap: () => context.go('/forgot-password'),
                                  child: Text(
                                    'Hai dimenticato la password?',
                                    style: AppTextStyles.bodySecondary(
                                      context,
                                    ).copyWith(fontSize: 13, decoration: TextDecoration.underline, decorationThickness: 1.2),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        0.50,
                        0.78,
                      ),

                      const SizedBox(height: 24),

                      // ── Link registrazione ─────────────────────────────────
                      _slide(
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Non hai un account? ',
                              style: AppTextStyles.bodySecondary(context),
                            ),
                            GestureDetector(
                              onTap: () => context.go('/register'),
                              child: Text(
                                'Registrati',
                                style: AppTextStyles.body(context).copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        0.72,
                        0.92,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Register Page ────────────────────────────────────────────────────────────

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  late final AnimationController _anim;

  bool _loading = false;
  bool _obscure = true;
  bool _submitted = false;
  String _submittedEmail = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Widget _slide(Widget child, double start, double end) {
    final curve = CurvedAnimation(
      parent: _anim,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signUp(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
            username: _usernameCtrl.text,
            displayName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text,
          );
      if (!mounted) return;
      setState(() {
        _submittedEmail = _emailCtrl.text.trim();
        _submitted = true;
      });
      _anim
        ..reset()
        ..forward();
    } on EchoAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_submitted) {
      return Scaffold(
        body: Stack(
          children: [
            _Background(isDark: isDark),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _slide(_EmailSentIllustration(isDark: isDark), 0.0, 0.55),
                      const SizedBox(height: 36),
                      _slide(
                        Column(
                          children: [
                            Text(
                              'Controlla la tua email',
                              style: AppTextStyles.displayLarge(context),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Abbiamo inviato un link di conferma a',
                              style: AppTextStyles.bodySecondary(context),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _submittedEmail,
                              style: AppTextStyles.body(context).copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.textLight
                                    : AppColors.textDark,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        0.15,
                        0.65,
                      ),
                      const SizedBox(height: 48),
                      _slide(
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () => context.go('/login'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Torna al login'),
                          ),
                        ),
                        0.35,
                        0.85,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          _Background(isDark: isDark),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      _slide(
                        Row(
                          children: [
                            GlassIconButton(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onPressed: () => context.go('/login'),
                            ),
                          ],
                        ),
                        0.0,
                        0.4,
                      ),
                      const SizedBox(height: 8),
                      _slide(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Crea account',
                              style: AppTextStyles.displayLarge(context),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Inizia a lasciare ricordi nel mondo.',
                              style: AppTextStyles.bodySecondary(context),
                            ),
                          ],
                        ),
                        0.1,
                        0.5,
                      ),
                      const SizedBox(height: 32),
                      _slide(
                        GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Field(
                                  controller: _nameCtrl,
                                  label: 'Nome (opzionale)',
                                  textCapitalization: TextCapitalization.words,
                                ),
                                const SizedBox(height: 16),
                                _Field(
                                  controller: _usernameCtrl,
                                  label: 'Username',
                                  prefixText: '@',
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Scegli un username';
                                    }
                                    if (v.trim().length < 3) {
                                      return 'Minimo 3 caratteri';
                                    }
                                    if (!RegExp(
                                      r'^[a-zA-Z0-9_]+$',
                                    ).hasMatch(v.trim())) {
                                      return 'Solo lettere, numeri e _';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _Field(
                                  controller: _emailCtrl,
                                  label: 'Email',
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Inserisci l\'email';
                                    }
                                    if (!v.contains('@'))
                                      return 'Email non valida';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _Field(
                                  controller: _passwordCtrl,
                                  label: 'Password',
                                  obscureText: _obscure,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.length < 6) {
                                      return 'Minimo 6 caratteri';
                                    }
                                    return null;
                                  },
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFE8879C),
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  height: 40,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _register,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: AppColors.primary,
                                      disabledBackgroundColor: AppColors.accent
                                          .withValues(alpha: 0.4),
                                      shape: StadiumBorder(),
                                    ),
                                    child: _loading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Crea account'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        0.25,
                        0.75,
                      ),
                      const SizedBox(height: 24),
                      _slide(
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Hai già un account? ',
                              style: AppTextStyles.bodySecondary(context),
                            ),
                            GestureDetector(
                              onTap: () => context.go('/login'),
                              child: Text(
                                'Accedi',
                                style: AppTextStyles.body(context).copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        0.45,
                        0.9,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Forgot Password Page ─────────────────────────────────────────────────────

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  late final AnimationController _anim;

  bool _loading = false;
  bool _submitted = false;
  String _submittedEmail = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Widget _slide(Widget child, double start, double end) {
    final curve = CurvedAnimation(
      parent: _anim,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(_emailCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _submittedEmail = _emailCtrl.text.trim();
        _submitted = true;
      });
      _anim
        ..reset()
        ..forward();
    } catch (_) {
      setState(() => _error = 'Qualcosa è andato storto. Riprova.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_submitted) {
      return Scaffold(
        body: Stack(
          children: [
            _Background(isDark: isDark),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _slide(_EmailSentIllustration(isDark: isDark), 0.0, 0.55),
                      const SizedBox(height: 36),
                      _slide(
                        Column(
                          children: [
                            Text(
                              'Controlla la tua email',
                              style: AppTextStyles.displayLarge(context),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Abbiamo inviato un link per reimpostare la password a',
                              style: AppTextStyles.bodySecondary(context),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _submittedEmail,
                              style: AppTextStyles.body(context).copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.textLight
                                    : AppColors.textDark,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        0.15,
                        0.65,
                      ),
                      const SizedBox(height: 48),
                      _slide(
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () => context.go('/login'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Torna al login'),
                          ),
                        ),
                        0.35,
                        0.85,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          _Background(isDark: isDark),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      _slide(
                        Row(
                          children: [
                            GlassIconButton(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onPressed: () => context.go('/login'),
                            ),
                          ],
                        ),
                        0.0,
                        0.4,
                      ),
                      const SizedBox(height: 8),
                      _slide(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Password dimenticata?',
                              style: AppTextStyles.displayLarge(context),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Inserisci la tua email e ti invieremo un link per reimpostarla.',
                              style: AppTextStyles.bodySecondary(context),
                            ),
                          ],
                        ),
                        0.1,
                        0.5,
                      ),
                      const SizedBox(height: 32),
                      _slide(
                        GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Field(
                                  controller: _emailCtrl,
                                  label: 'Email',
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Inserisci l\'email';
                                    }
                                    if (!v.contains('@'))
                                      return 'Email non valida';
                                    return null;
                                  },
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFE8879C),
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  height: 40,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _send,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: AppColors.primary,
                                      disabledBackgroundColor: AppColors.accent
                                          .withValues(alpha: 0.4),
                                      shape: StadiumBorder(),
                                    ),
                                    child: _loading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Invia link'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        0.25,
                        0.75,
                      ),
                      const SizedBox(height: 24),
                      _slide(
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Ricordi la password? ',
                              style: AppTextStyles.bodySecondary(context),
                            ),
                            GestureDetector(
                              onTap: () => context.go('/login'),
                              child: Text(
                                'Accedi',
                                style: AppTextStyles.body(context).copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        0.45,
                        0.9,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reset Password Page ──────────────────────────────────────────────────────

class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  late final AnimationController _anim;

  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Widget _slide(Widget child, double start, double end) {
    final curve = CurvedAnimation(
      parent: _anim,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).updatePassword(_pwCtrl.text);
      if (!mounted) return;
      setState(() => _done = true);
      _anim
        ..reset()
        ..forward();
    } on EchoAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_done) {
      return Scaffold(
        body: Stack(
          children: [
            _Background(isDark: isDark),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _slide(_SuccessIllustration(isDark: isDark), 0.0, 0.55),
                      const SizedBox(height: 36),
                      _slide(
                        Column(
                          children: [
                            Text(
                              'Password aggiornata',
                              style: AppTextStyles.displayLarge(context),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Puoi ora accedere con la tua nuova password.',
                              style: AppTextStyles.bodySecondary(context),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        0.15,
                        0.65,
                      ),
                      const SizedBox(height: 48),
                      _slide(
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () => context.go('/login'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Accedi'),
                          ),
                        ),
                        0.35,
                        0.85,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          _Background(isDark: isDark),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 48),
                      _slide(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nuova password',
                              style: AppTextStyles.displayLarge(context),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Scegli una nuova password per il tuo account.',
                              style: AppTextStyles.bodySecondary(context),
                            ),
                          ],
                        ),
                        0.1,
                        0.5,
                      ),
                      const SizedBox(height: 32),
                      _slide(
                        GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Field(
                                  controller: _pwCtrl,
                                  label: 'Nuova password',
                                  obscureText: _obscure,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.length < 6) {
                                      return 'Minimo 6 caratteri';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _Field(
                                  controller: _confirmCtrl,
                                  label: 'Conferma password',
                                  obscureText: _obscureConfirm,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirm
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                      () => _obscureConfirm = !_obscureConfirm,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v != _pwCtrl.text) {
                                      return 'Le password non coincidono';
                                    }
                                    return null;
                                  },
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFE8879C),
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                                const SizedBox(height: 24),
                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _save,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: AppColors.primary,
                                      disabledBackgroundColor: AppColors.accent
                                          .withValues(alpha: 0.4),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: _loading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Salva password'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        0.25,
                        0.75,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _EmailSentIllustration extends StatelessWidget {
  const _EmailSentIllustration({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);
    final iconColor = isDark ? AppColors.textLight : AppColors.textDark;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow ring
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 1),
            color: bg,
          ),
        ),
        // Inner circle
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            border: Border.all(color: border, width: 1),
          ),
          child: Icon(
            Icons.mark_email_unread_outlined,
            size: 48,
            color: iconColor,
          ),
        ),
        // Decorative dots
        Positioned(
          top: 12,
          right: 24,
          child: _Dot(size: 8, color: iconColor.withValues(alpha: 0.3)),
        ),
        Positioned(
          bottom: 18,
          left: 20,
          child: _Dot(size: 6, color: iconColor.withValues(alpha: 0.2)),
        ),
        Positioned(
          top: 36,
          left: 10,
          child: _Dot(size: 4, color: iconColor.withValues(alpha: 0.15)),
        ),
      ],
    );
  }
}

class _SuccessIllustration extends StatelessWidget {
  const _SuccessIllustration({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);
    final iconColor = isDark ? AppColors.textLight : AppColors.textDark;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 1),
            color: bg,
          ),
        ),
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            border: Border.all(color: border, width: 1),
          ),
          child: Icon(Icons.lock_open_outlined, size: 48, color: iconColor),
        ),
        Positioned(
          top: 12,
          right: 24,
          child: _Dot(size: 8, color: iconColor.withValues(alpha: 0.3)),
        ),
        Positioned(
          bottom: 18,
          left: 20,
          child: _Dot(size: 6, color: iconColor.withValues(alpha: 0.2)),
        ),
        Positioned(
          top: 36,
          left: 10,
          child: _Dot(size: 4, color: iconColor.withValues(alpha: 0.15)),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

// ─── Echo typewriter title ────────────────────────────────────────────────────

class _EchoTitle extends StatelessWidget {
  const _EchoTitle({required this.animation});
  final Animation<double> animation;

  Animation<double> _letter(double start, double end) => CurvedAnimation(
    parent: animation,
    curve: Interval(start, end, curve: Curves.easeOut),
  );

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.displayLarge(context);

    // "E" sale dal basso + fade-in, poi ogni lettera appare in rapida sequenza
    final eAnim = _letter(0.00, 0.13);
    final cAnim = _letter(0.13, 0.18);
    final hAnim = _letter(0.18, 0.23);
    final oAnim = _letter(0.23, 0.28);
    final dotAnim = _letter(0.28, 0.33);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        FadeTransition(
          opacity: eAnim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.5),
              end: Offset.zero,
            ).animate(eAnim),
            child: Text('E', style: style),
          ),
        ),
        FadeTransition(
          opacity: cAnim,
          child: Text('c', style: style),
        ),
        FadeTransition(
          opacity: hAnim,
          child: Text('h', style: style),
        ),
        FadeTransition(
          opacity: oAnim,
          child: Text('o', style: style),
        ),
        FadeTransition(
          opacity: dotAnim,
          child: Text('.', style: style),
        ),
      ],
    );
  }
}

// ─── Background ───────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF100F1C), Color(0xFF181528), Color(0xFF100E1A)]
              : const [Color(0xFFF3F1FC), Color(0xFFE9E6F7), Color(0xFFF2F0FB)],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.prefixText,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final String? prefixText;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefixText,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.6),
      ),
    );
  }
}
