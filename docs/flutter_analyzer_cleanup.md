# Flutter analyzer cleanup and code-quality review

## Scope and starting point

This maintenance branch is based on `99c6d18fd3638d09f19505429cc345a2b4835361` (`main` at task start), on branch `maintenance/flutter-analyzer-cleanup`. The application identity, architecture, screens, navigation, backend contracts, platform configuration, package versions, and signing settings were preserved. No APK was built.

The baseline was measured with Flutter **3.47.9** and Dart **3.13.7** after `flutter pub get`. The complete, unedited output from `flutter analyze` on the starting commit is preserved in [the baseline analyzer log](flutter_analyzer_baseline.log), including every affected path, line, and column. The baseline had **123 informational diagnostics, 0 warnings, and 0 errors**:

| Diagnostic | Baseline |
| --- | --- |
| `curly_braces_in_flow_control_structures` | 34 |
| `unnecessary_underscores` | 40 |
| `prefer_const_constructors` | 25 |
| `non_constant_identifier_names` | 1 |
| `prefer_interpolation_to_compose_strings` | 14 |
| `use_build_context_synchronously` | 7 |
| `unnecessary_brace_in_string_interps` | 1 |
| `deprecated_member_use` | 1 |
| **Total** | **123** |

The original test suite contained one widget test and passed on the starting commit.

## Changes

All safely applicable mechanical analyzer fixes were applied: explicit control-flow blocks, single ignored-parameter underscores supported by the declared Dart SDK, valid `const` constructors, interpolation in place of string composition, redundant interpolation-brace removal, and the current `DropdownButtonFormField.initialValue` API. The private auth-page helper was renamed from `_FormCard` to `_formCard`; this is not a public or serialized identifier.

The seven original asynchronous `BuildContext` findings were reviewed in their enclosing callbacks and lifecycle contexts rather than suppressed. Guards match the actual context and owning State: the chat block flow exits if its State was removed while the confirmation dialog was open; profile-list and comment-sheet error snackbars require both the parent State and sheet context to remain mounted; copy-link snackbars check the local BuildContext; story creation checks State liveness after dialogs and media selection/upload; and story deletion checks liveness before viewer updates, using the local BuildContext for its snackbar. The comments bottom sheet no longer calls its `StateSetter` after the sheet is unmounted, and async comment posting checks sheet liveness before clearing the controller or updating sheet state.

A focused lifecycle review found transient text controllers created inside report/tag dialog builders in the profile and social flows. Ownership was moved outside each builder and the controllers are disposed after their dialogs complete, including cancel/dismiss flows. Existing persistent controllers, stream subscriptions, timers, scroll controllers, and media controllers were reviewed for disposal in their owning `State` objects; no additional confirmed leaks were changed.

The requested `dart format .` pass reformatted the Dart sources repository-wide. The source was not uniformly formatter-clean at baseline; this reflow exposed additional `curly_braces_in_flow_control_structures` diagnostics. Those were fixed rather than suppressed. No analyzer rules, severities, or exclusions were changed.

## Validation results

| Check | Result |
| --- | --- |
| `flutter pub get` | Passed; dependency lockfile unchanged. Pub reported 60 newer versions outside existing constraints; no dependency upgrades were made. |
| `dart format --output=none --set-exit-if-changed .` | Passed: 34 Dart files checked, 0 changed. |
| `flutter analyze` (without `--no-fatal-infos`) | Passed: **No issues found** (0 errors, warnings, and informational diagnostics). |
| `flutter test` | Passed: all existing tests passed. |
| Existing iOS configuration preflight from CI | Passed. |
| `git diff --check` | Passed. |
| PR GitHub Actions run [41033247774](https://github.com/IrregDraken/eazy-mobile-v1/actions/runs/41033247774) | `flutter-analyze-test`, `ios-config-preflight`, and `backend-build-test` succeeded. `flutter-android-release-smoke` was canceled while its `flutter build apk --release` step was running, to honor the no-APK instruction. Its log has no build-completion or artifact-upload marker. |

The local analyzer/test runs completed successfully. The GitHub workflow did start an Android APK build command before it was canceled; the available log does not evidence successful completion or artifact distribution, so no claim of a successful APK build is made. No local APK build or signing operation was performed.

## Files and scope notes

Changed Dart files:

```
lib/app/router.dart
lib/core/auth/auth_controller.dart
lib/core/media/media_service.dart
lib/core/network/api_client.dart
lib/core/network/api_exception.dart
lib/core/ui/eazy_artwork.dart
lib/features/assist/assist_page.dart
lib/features/auth/auth_page.dart
lib/features/chat/chat_home_screen.dart
lib/features/chat/chat_page.dart
lib/features/home/home_shell.dart
lib/features/location/location_page.dart
lib/features/marketplace/cart_page.dart
lib/features/marketplace/marketplace_page.dart
lib/features/marketplace/product_detail_page.dart
lib/features/notifications/notifications_page.dart
lib/features/onboarding/discovery_page.dart
lib/features/onboarding/profile_setup_page.dart
lib/features/onboarding/welcome_page.dart
lib/features/profile/profile_page.dart
lib/features/security/blocks_page.dart
lib/features/security/security_page.dart
lib/features/settings/settings_page.dart
lib/features/social/social_page.dart
lib/features/social/stories_tray.dart
lib/features/social/video_media.dart
lib/features/translation/translation_page.dart
lib/features/wallet/wallet_page.dart
```

Formatter-normalized comparison shows `lib/core/network/api_exception.dart` is the only formatting-only Dart source. The other 27 Dart files contain analyzer or lifecycle edits in addition to formatting; most are behavior-preserving lint fixes. The lifecycle/correctness changes are concentrated in `chat_page.dart`, `profile_page.dart`, `social_page.dart`, and `stories_tray.dart`. No intended product-flow or UI behavior changes were made. The only non-code additions are this report and the baseline analyzer log.

Protected files and systems were not changed: `android/key.properties`, release signing configuration, application ID/namespace/version, Firebase/Google configuration, CI workflows, `pubspec.yaml` / `pubspec.lock`, analyzer configuration, backend/database/deployment configuration, production secrets, and production data.

## Remaining risks and limitations

The existing automated test coverage is very small (one widget test), so passing `flutter test` does not exercise the authentication, payments, chat, or social flows end-to-end. This task did not perform device-level testing or build an APK, as required. No confirmed security issue requiring an in-scope code change was identified during the focused review; a comprehensive security review remains outside this maintenance task.
