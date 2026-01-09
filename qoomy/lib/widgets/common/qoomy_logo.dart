import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class QoomyLogo extends StatelessWidget {
  final double size;

  const QoomyLogo({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/qoomylogo.svg',
      width: size,
      height: size,
    );
  }
}
