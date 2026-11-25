import 'package:flutter/material.dart';
import 'package:nexora/core/constants/brand_config.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/toast/app_toast.dart';
import 'package:nexora/core/localization/l10n_extension.dart';

class SupportActions {
  const SupportActions._();

  static Future<void> sendFeedback(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: BrandConfig.supportEmail,
      queryParameters: {
        'subject': '${BrandConfig.appName} App Feedback',
        'body': 'Hello,\n\n',
      },
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        AppToast.error(context.l10n.couldNotOpenYour2);
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context.l10n.couldNotOpenYour2);
      }
    }
  }
}
