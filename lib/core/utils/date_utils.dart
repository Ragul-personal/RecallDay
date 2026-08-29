import 'package:intl/intl.dart';

class DateLabels {
  static String relative(DateTime when, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(when.year, when.month, when.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff > 1 && diff <= 6) return DateFormat.EEEE().format(when);
    if (diff < -1 && diff >= -6) return '${-diff}d ago';
    return DateFormat.MMMd().format(when);
  }

  static String time(DateTime when) => DateFormat.jm().format(when);

  static String monthYear(DateTime when) => DateFormat.yMMMM().format(when);
}
