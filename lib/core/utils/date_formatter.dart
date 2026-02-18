import 'package:intl/intl.dart';

class DateFormatter {
  static String formatMessageTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays == 0) return DateFormat('HH:mm').format(time);
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat('EEE').format(time);
    if (diff.inDays < 365) return DateFormat('d MMM').format(time);
    return DateFormat('d MMM y').format(time);
  }

  static String formatFullDate(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays == 0) return 'Today ${DateFormat('HH:mm').format(time)}';
    if (diff.inDays == 1) return 'Yesterday ${DateFormat('HH:mm').format(time)}';
    return DateFormat('d MMM y, HH:mm').format(time);
  }

  static String formatDateSeparator(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat('EEEE').format(time);
    return DateFormat('d MMMM y').format(time);
  }
}
