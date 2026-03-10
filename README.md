# ulinq_sdk

Flutter SDK for Ulinq deeplink resolution, install attribution, and event tracking.

## Installation

```yaml
dependencies:
  ulinq_sdk: ^1.0.0
```

## Initialize

```dart
import 'package:ulinq_sdk/ulinq_sdk.dart';

Future<void> setupUlinq() async {
  await Ulinq.initialize(
    UlinqConfig(
      sdkKey: 'sdk_live_xxx',
      authHeaderMode: UlinqAuthHeaderMode.authorization,
      enableLogging: false,
    ),
  );
}
```
