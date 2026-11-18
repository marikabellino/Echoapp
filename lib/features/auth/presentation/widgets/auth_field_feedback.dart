import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_motion.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:flutter/material.dart';

// ─── Regole password ──────────────────────────────────────────────────────────

/// Requisiti della password. [required] = blocca la registrazione;
/// gli altri alzano solo la "forza".
class PasswordRule {
  const PasswordRule(this.label, this.test, {this.required = true});
  final String label;
  final bool Function(String) test;
  final bool required;
}

final passwordRules = <PasswordRule>[
  PasswordRule('8+ caratteri', (v) => v.length >= 8),
  PasswordRule('una lettera', (v) => RegExp(r'[A-Za-z]').hasMatch(v)),
  PasswordRule('un numero', (v) => RegExp(r'\d').hasMatch(v)),
  PasswordRule(
    'maiuscola + minuscola',
    (v) => RegExp(r'[a-z]').hasMatch(v) && RegExp(r'[A-Z]').hasMatch(v),
    required: false,
  ),
  PasswordRule(
    'un simbolo',
    (v) => RegExp(r'[^A-Za-z0-9]').hasMatch(v),
    required: false,
  ),
];

/// Validator condiviso (registrazione + reset password).
String? validatePassword(String? v) {
  final value = v ?? '';
  if (value.isEmpty) return 'Inserisci una password';
  final missing = passwordRules.where((r) => r.required && !r.test(value));
  if (missing.isEmpty) return null;
  return 'Manca ancora: ${missing.map((r) => r.label).join(', ')}';
}

/// 0..4
int _strength(String v) {
  if (v.isEmpty) return 0;
  final passed = passwordRules.where((r) => r.test(v)).length;
  final requiredOk = passwordRules.every((r) => !r.required || r.test(v));
  if (!requiredOk) return 1;
  // Requisiti ok → passed è 3..5 → forza 2..4, +1 per le password lunghe.
  final s = passed - 1 + (v.length >= 12 ? 1 : 0);
  return s.clamp(2, 4);
}

const _strengthLabels = ['', 'Debole', 'Discreta', 'Buona', 'Fortissima'];
const _strengthColors = [
  Colors.transparent,
  AppColors.error,
  AppColors.accentSecondary,
  AppColors.accent,
  AppColors.success,
];

/// Barra di forza + checklist a chip, si apre quando si inizia a scrivere.
class PasswordGuide extends StatelessWidget {
  const PasswordGuide({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        return AnimatedSize(
          duration: AppMotion.pop,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: text.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  child: _GuideBody(text: text),
                ),
        );
      },
    );
  }
}

class _GuideBody extends StatelessWidget {
  const _GuideBody({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = _strength(text);
    final color = _strengthColors[s];
    final idle = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 1; i <= 4; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.pop,
                  curve: Curves.easeOutCubic,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i <= s ? color : idle,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: i <= s
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              if (i < 4) const SizedBox(width: 6),
            ],
            const SizedBox(width: 12),
            SizedBox(
              width: 78,
              child: AnimatedSwitcher(
                duration: AppMotion.pop,
                switchInCurve: AppMotion.popCurve,
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: a,
                  child: FadeTransition(opacity: a, child: c),
                ),
                child: Text(
                  _strengthLabels[s],
                  key: ValueKey(s),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: s == 2 && !isDark
                        ? AppColors.accentSecondaryOnLight
                        : color,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in passwordRules) _RuleChip(rule: r, ok: r.test(text)),
          ],
        ),
      ],
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.rule, required this.ok});
  final PasswordRule rule;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idleFg = isDark
        ? AppColors.textSecondaryLight
        : AppColors.textSecondaryDark;
    final fg = ok ? AppColors.success : idleFg;
    final label = rule.required ? rule.label : '${rule.label} · bonus';

    return AnimatedContainer(
      duration: AppMotion.pop,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        color: ok
            ? AppColors.success.withValues(alpha: isDark ? 0.14 : 0.12)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04)),
        border: Border.all(
          color: ok
              ? AppColors.success.withValues(alpha: 0.55)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: AppMotion.pop,
            switchInCurve: AppMotion.popCurve,
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(
              ok ? Icons.check_circle_rounded : Icons.circle_outlined,
              key: ValueKey(ok),
              size: 14,
              color: fg,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: ok ? FontWeight.w600 : FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Username ────────────────────────────────────────────────────────────────

enum UsernameStatus { idle, invalid, checking, available, taken, error }

/// Icona di stato nel campo username.
class UsernameStatusIcon extends StatelessWidget {
  const UsernameStatusIcon({super.key, required this.status});
  final UsernameStatus status;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (status) {
      UsernameStatus.checking => const SizedBox(
        key: ValueKey('checking'),
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accent,
        ),
      ),
      UsernameStatus.available => const Icon(
        Icons.check_circle_rounded,
        key: ValueKey('ok'),
        color: AppColors.success,
        size: 20,
      ),
      UsernameStatus.taken => const Icon(
        Icons.cancel_rounded,
        key: ValueKey('taken'),
        color: AppColors.accent,
        size: 20,
      ),
      _ => const SizedBox.shrink(key: ValueKey('none')),
    };
    return SizedBox(
      width: 48,
      child: Center(
        child: AnimatedSwitcher(
          duration: AppMotion.pop,
          switchInCurve: AppMotion.popCurve,
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: child,
        ),
      ),
    );
  }
}

/// Riga sotto il campo username ("@mario è libero" / "già preso").
class UsernameStatusLine extends StatelessWidget {
  const UsernameStatusLine({
    super.key,
    required this.status,
    required this.username,
  });
  final UsernameStatus status;
  final String username;

  @override
  Widget build(BuildContext context) {
    final (String? text, Color color) = switch (status) {
      UsernameStatus.available => (
        '@$username è libero, è tuo!',
        AppColors.success,
      ),
      UsernameStatus.taken => (
        '@$username è già in uso, prova un\'altra variante',
        AppColors.accent,
      ),
      UsernameStatus.invalid => (
        'Solo lettere, numeri e _ (niente spazi o accenti)',
        AppColors.accent,
      ),
      UsernameStatus.error => (
        'Non riesco a verificare ora, riproverò all\'invio',
        AppColors.accentSecondary,
      ),
      _ => (null, Colors.transparent),
    };

    return AnimatedSize(
      duration: AppMotion.pop,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AppMotion.pop,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, -0.3),
              end: Offset.zero,
            ).animate(a),
            child: c,
          ),
        ),
        child: text == null
            ? const SizedBox(width: double.infinity, key: ValueKey('empty'))
            : Padding(
                key: ValueKey('$status$username'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

enum _Match { none, match, mismatch }

/// Mismatch appena è certo: testo diverso e non più un "pezzo iniziale"
/// della password (mentre si sta ancora digitando correttamente resta neutro).
_Match _matchState(String password, String confirm) {
  if (confirm.isEmpty) return _Match.none;
  if (confirm == password) return _Match.match;
  if (confirm.length < password.length && password.startsWith(confirm)) {
    return _Match.none;
  }
  return _Match.mismatch;
}

/// Spunta verde / croce rosa nel campo "Conferma password", aggiornata live.
class PasswordMatchIcon extends StatelessWidget {
  const PasswordMatchIcon({
    super.key,
    required this.password,
    required this.confirm,
    required this.toggle,
  });
  final TextEditingController password;
  final TextEditingController confirm;
  final Widget toggle;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([password, confirm]),
      builder: (context, _) {
        final state = _matchState(password.text, confirm.text);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: AppMotion.pop,
              switchInCurve: AppMotion.popCurve,
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: switch (state) {
                _Match.match => const Icon(
                  Icons.check_circle_rounded,
                  key: ValueKey('match'),
                  color: AppColors.success,
                  size: 20,
                ),
                _Match.mismatch => const Icon(
                  Icons.cancel_rounded,
                  key: ValueKey('mismatch'),
                  color: AppColors.accent,
                  size: 20,
                ),
                _Match.none => const SizedBox.shrink(key: ValueKey('none')),
              },
            ),
            toggle,
          ],
        );
      },
    );
  }
}

/// Riga sotto "Conferma password": compare subito se non coincidono.
class PasswordMatchLine extends StatelessWidget {
  const PasswordMatchLine({
    super.key,
    required this.password,
    required this.confirm,
  });
  final TextEditingController password;
  final TextEditingController confirm;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([password, confirm]),
      builder: (context, _) {
        final state = _matchState(password.text, confirm.text);
        final (String? text, Color color) = switch (state) {
          _Match.mismatch => ('Le password non coincidono', AppColors.accent),
          _Match.match => ('Perfetto, coincidono!', AppColors.success),
          _Match.none => (null, Colors.transparent),
        };
        return AnimatedSize(
          duration: AppMotion.pop,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: AppMotion.pop,
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, -0.3),
                  end: Offset.zero,
                ).animate(a),
                child: c,
              ),
            ),
            child: text == null
                ? const SizedBox(width: double.infinity, key: ValueKey('empty'))
                : Padding(
                    key: ValueKey(state),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
