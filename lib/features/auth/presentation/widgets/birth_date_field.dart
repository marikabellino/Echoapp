import 'package:flutter/services.dart';

/// Scrive la data mentre si digita: "12052008" diventa "12/05/2008".
class BirthDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 8 ? digits.substring(0, 8) : digits;
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 2 || i == 4) b.write('/');
      b.write(d[i]);
    }
    final text = b.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// "GG/MM/AAAA" → data, oppure null se non è una data vera.
DateTime? parseBirthDate(String text) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(text.trim());
  if (m == null) return null;
  final day = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final year = int.parse(m.group(3)!);
  final date = DateTime(year, month, day);
  // DateTime(2008, 2, 31) diventa il 2 marzo: una data inesistente non vale.
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Età compiuta oggi da chi è nato il [birth].
int ageOn(DateTime birth, DateTime today) {
  var age = today.year - birth.year;
  if (today.month < birth.month ||
      (today.month == birth.month && today.day < birth.day)) {
    age--;
  }
  return age;
}

String? validateBirthDate(String text, {required int minAge}) {
  if (text.trim().isEmpty) return 'Inserisci la data di nascita';
  final date = parseBirthDate(text);
  final now = DateTime.now();
  if (date == null || date.isAfter(now) || date.year < 1900) {
    return 'Scrivila così: GG/MM/AAAA';
  }
  if (ageOn(date, now) < minAge) {
    return 'Per usare mingle. devi avere almeno $minAge anni';
  }
  return null;
}
