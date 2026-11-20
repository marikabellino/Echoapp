import 'package:flutter/widgets.dart';

/// Chiude la tastiera togliendo il focus da qualunque campo di testo.
void dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

/// Impedisce alla tastiera di riaprirsi "a caso" durante la navigazione.
///
/// Quando si apre una schermata o un foglio, il campo di testo della pagina
/// sotto resta attivo; quando si torna indietro Flutter gli ridà il focus e
/// la tastiera ricompare, a volte per un campo che non si vede nemmeno (per
/// esempio quello della pagina "Nuovo drop" tenuta viva nella barra in basso)
/// e che quindi non si può chiudere toccando fuori.
///
/// - push: si chiude subito la tastiera della pagina sotto; i campi con
///   `autofocus` della nuova schermata la riaprono dopo, quando servono.
/// - pop: dopo il ritorno si toglie il focus che Flutter ha ripristinato.
class KeyboardGuardObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) dismissKeyboard();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _dismissAfterRestore();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _dismissAfterRestore();
  }

  void _dismissAfterRestore() {
    WidgetsBinding.instance.addPostFrameCallback((_) => dismissKeyboard());
  }
}
