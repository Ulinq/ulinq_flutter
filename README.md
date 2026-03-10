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

Optional runtime config via Dart define:

```bash
flutter run \
  --dart-define=ULINQ_BASE_URL=https://api.ulinq.cc \
  --dart-define=ULINQ_SDK_KEY=sdk_live_xxx
```

## Public API

```dart
class Ulinq {
  static Future<void> initialize(UlinqConfig config);
  static void enableDebug([bool enabled = true]);

  static Future<bool> isFirstLaunch();
  static Future<UlinqInstallAttribution?> claimInstallAttribution({String? deviceIdOverride});
  static Future<UlinqResolvedLink?> claimDeferredDeeplink({
    String? deviceIdOverride,
    bool onlyOnFirstLaunch = true,
  });
  static Future<UlinqResolvedLink?> resolve({required String token});

  static Stream<UlinqResolvedLink> get onLink;
  static Stream<UlinqResolvedLink> get onLinkReceived;

  static Future<void> trackOpen({
    String? deeplinkId,
    Map<String, Object?>? properties,
  });

  static Future<UlinqConversionResult> trackConversion({
    required String eventName,
    required String eventId,
    double? value,
    String? currency,
    Map<String, Object?>? properties,
    String? deviceIdOverride,
  });

  static void setPendingInstallToken(String token);
}
```

## Method Contracts

### `Ulinq.resolve(token: ...)`

- Input: deeplink token
- Output: `UlinqResolvedLink`

`UlinqResolvedLink` includes:
- `deeplinkId`
- `appId`
- `projectId`
- `slug`
- `subdomain`
- `payload`
- `metadata`

### `Ulinq.claimInstallAttribution()`

Request context sent by SDK:
- `platform`
- `device_id`
- optional `install_token`

Returns `UlinqInstallAttribution`:
- `attributed`
- `status` (`attributed` or `unattributed`)
- `deeplinkId`
- `appId`
- `idempotent`
- optional `reason` (`invalid_token`, `token_expired`, `no_match`, `ambiguous`, `rate_limited`)

### `Ulinq.claimDeferredDeeplink()`

Flow:
1. Calls `claimInstallAttribution()`
2. If attributed and `deeplinkId` exists, resolves link and returns `UlinqResolvedLink`
3. Returns `null` when unavailable/unattributed

### `Ulinq.trackOpen()`

SDK sends:
- `platform`, `device_id`, `opened_at_utc`, `session_id`
- optional `install_token`, `deeplink_id`, `properties`

Handled internally via event queue with retry/backoff and persistence.

### `Ulinq.trackConversion()`

SDK sends:
- `device_id`, `platform`, `event_name`, `event_id`, `occurred_at_utc`, `session_id`
- optional `install_token`, `value`, `currency`, `properties`

Returns `UlinqConversionResult`:
- `attributed`
- `idempotent`
- optional `installId`
- optional `deeplinkId`

## Queue and Session Behavior

### Event queue

- In-memory queue with persistence (`SharedPreferences`)
- Retry with exponential backoff
- Flush triggers:
  - immediate for `trackOpen()`
  - threshold
  - timer
  - app foreground
- Batch transport enabled internally
- Persisted queue capped to newest `100` events

### Session manager

- Handles cold start + runtime deeplinks + resume checks
- Session ID generated on start
- Session rollover after background period
- Per-session dedupe key: `session_id:deeplink_id`

## Platform Integration

### Android (required for deferred install attribution)

1. Add Play Install Referrer dependency in the host app:

```gradle
implementation "com.android.installreferrer:installreferrer:2.2"
```

2. Expose method channel `ulinq/install_referrer` with method `getInstallReferrer`.

Expected referrer includes `install_token`.

### iOS

App Store does not provide install referrer directly after install. Supported token sources:
- Universal link token
- Native bridge (`ulinq/install_referrer` / `getPendingInstallToken`)
- App-provided token via `Ulinq.setPendingInstallToken(...)`

## Runtime Link Stream

```dart
Ulinq.onLinkReceived.listen((link) {
  // link.deeplinkId, link.payload, link.metadata
});
```

## Reserved Event Names

Do not use these with `Ulinq.trackConversion(...)`:
- `link_click`
- `install`
- `app_open`

## Error Types

SDK throws:
- `UlinqAuthException`
- `UlinqNetworkException`
- `UlinqRateLimitException`
- `UlinqInvalidResponseException`

```dart
try {
  await Ulinq.resolve(token: 'abc');
} on UlinqRateLimitException catch (e) {
  // e.waitSeconds
} on UlinqException {
  // fallback
}
```

## Debug Mode

```dart
Ulinq.enableDebug(true);
```

## Example

```bash
cd example
flutter run --dart-define=ULINQ_SDK_KEY=sdk_live_xxx
```
