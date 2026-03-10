import 'package:flutter/material.dart';

List<Widget> buildActionButtons({
  required VoidCallback initialize,
  required VoidCallback firstLaunch,
  required VoidCallback claimInstall,
  required VoidCallback claimDeferred,
  required VoidCallback resolveToken,
  required VoidCallback trackOpen,
  required VoidCallback trackConversion,
  required VoidCallback readLast,
  required VoidCallback disposeSdk,
}) {
  Widget btn(String label, VoidCallback onPressed) {
    return ElevatedButton(onPressed: onPressed, child: Text(label));
  }

  return [
    btn('Initialize', initialize),
    btn('isFirstLaunch', firstLaunch),
    btn('Claim Install', claimInstall),
    btn('Claim Deferred', claimDeferred),
    btn('Resolve Token', resolveToken),
    btn('Track Open', trackOpen),
    btn('Track Conversion', trackConversion),
    btn('Read Last Cache', readLast),
    btn('Dispose SDK', disposeSdk),
  ];
}
