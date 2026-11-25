import 'package:flutter/material.dart';
import 'package:nexora/core/constants/brand_config.dart';
import 'package:nexora/core/themes/brand_mark.dart';

/// Large centered logo (mark above the app name) for splash / auth screens.
class DynamicSplashLogo extends StatelessWidget {
  final double? width;
  final double? height;

  const DynamicSplashLogo({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 84),
            const SizedBox(height: 14),
            Text(
              BrandConfig.appName,
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: isDark ? Colors.white : const Color(0xFF111827),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
