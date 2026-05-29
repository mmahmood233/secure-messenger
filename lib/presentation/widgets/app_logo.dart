import 'package:flutter/material.dart';
import 'package:secure_messenger/core/theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;

  const AppLogo({
    super.key,
    this.size = 40,
    this.showWordmark = false,
  });

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        Icons.lock_rounded,
        color: Colors.white,
        size: size * 0.55,
      ),
    );

    if (!showWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 10),
        const Text(
          'SecureMessenger',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
