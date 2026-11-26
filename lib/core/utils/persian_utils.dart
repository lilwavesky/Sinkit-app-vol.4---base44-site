class PersianUtils {
  static const Map<String, String> _faToEn = {
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
  };

  static const Map<String, String> _enToFa = {
    '0': '۰',
    '1': '۱',
    '2': '۲',
    '3': '۳',
    '4': '۴',
    '5': '۵',
    '6': '۶',
    '7': '۷',
    '8': '۸',
    '9': '۹',
  };

  static String toEnglishDigits(String input) {
    final buffer = StringBuffer();
    for (final ch in input.split('')) {
      buffer.write(_faToEn[ch] ?? ch);
    }
    return buffer.toString();
  }

  static String toPersianDigits(String input) {
    final buffer = StringBuffer();
    for (final ch in input.split('')) {
      buffer.write(_enToFa[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// Normalizes Iranian mobile numbers to `09xxxxxxxxx` format.
  static String normalizeIranPhone(String raw) {
    var cleaned = toEnglishDigits(raw).replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+98')) {
      cleaned = '0${cleaned.substring(3)}';
    } else if (cleaned.startsWith('0098')) {
      cleaned = '0${cleaned.substring(4)}';
    } else if (cleaned.startsWith('98') && cleaned.length == 12) {
      cleaned = '0${cleaned.substring(2)}';
    }
    return cleaned;
  }

  static String? validateIranPhone(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'لطفاً شماره همراه را وارد کنید';
    }
    final normalized = normalizeIranPhone(raw);
    final regex = RegExp(r'^09\d{9}$');
    if (!regex.hasMatch(normalized)) {
      return 'شماره همراه باید با ۰۹ شروع شده و ۱۱ رقم باشد';
    }
    return null;
  }

  static String? validateDeviceTitle(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'لطفاً عنوان دستگاه را وارد کنید';
    }
    if (raw.trim().length < 2) {
      return 'عنوان دستگاه باید حداقل ۲ کاراکتر باشد';
    }
    return null;
  }

  static String formatPhoneForDisplay(String phone) {
    final normalized = normalizeIranPhone(phone);
    if (normalized.length == 11) {
      final grouped =
          '${normalized.substring(0, 4)} ${normalized.substring(4, 7)} ${normalized.substring(7)}';
      return toPersianDigits(grouped);
    }
    return toPersianDigits(phone);
  }

  static String formatTime24(int hour, int minute) {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return toPersianDigits('$h:$m');
  }

  static String formatDateTimeShort(DateTime dt) {
    final jalali = gregorianToJalali(dt.year, dt.month, dt.day);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return toPersianDigits(
      '${jalali.$1}/${jalali.$2.toString().padLeft(2, '0')}/${jalali.$3.toString().padLeft(2, '0')} - $h:$m',
    );
  }

  /// Standard Gregorian to Jalali (Solar Hijri) converter without external dependency risk.
  static (int year, int month, int day) gregorianToJalali(
    int gy,
    int gm,
    int gd,
  ) {
    const gDaysInMonth = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    int jy;
    if (gy > 1600) {
      jy = 979;
      gy -= 1600;
    } else {
      jy = 0;
      gy -= 621;
    }
    final gy2 = (gm > 2) ? (gy + 1) : gy;
    int days = (365 * gy) +
        ((gy2 + 3) ~/ 4) -
        ((gy2 + 99) ~/ 100) +
        ((gy2 + 399) ~/ 400) -
        80 +
        gd +
        gDaysInMonth[gm - 1];
    jy += 33 * (days ~/ 12053);
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    final jm = (days < 186) ? 1 + (days ~/ 31) : 7 + ((days - 186) ~/ 30);
    final jd = 1 + ((days < 186) ? (days % 31) : ((days - 186) % 30));
    return (jy, jm, jd);
  }
}
