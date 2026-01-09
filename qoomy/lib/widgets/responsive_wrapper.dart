import 'package:flutter/material.dart';
import 'package:qoomy/config/theme.dart';

class ResponsiveWrapper extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;

  const ResponsiveWrapper({
    super.key,
    required this.child,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: QoomyTheme.maxContentWidth),
          child: child,
        ),
      ),
    );
  }
}
