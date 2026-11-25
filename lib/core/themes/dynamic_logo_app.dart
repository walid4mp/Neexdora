import 'package:flutter/material.dart';
import 'package:nexora/core/constants/brand_config.dart';
import 'package:nexora/core/themes/brand_mark.dart';

/// Header wordmark (mark + app name) used on the home screen.
class DynamicHeaderLogo extends StatelessWidget {
  final double height;

  const DynamicHeaderLogo({super.key, this.height = 25});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: height * 1.15),
        SizedBox(width: height * 0.4),
        Text(
          BrandConfig.appName,
          style: TextStyle(
            fontSize: height * 0.85,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }
}
