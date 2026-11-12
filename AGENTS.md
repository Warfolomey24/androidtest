# Codex instructions: Merlin Launcher Lite

## Device and goals
- Device: Xiaomi Redmi Note 9, hardware `merlinnfc`, Android 12, MIUI `V13.0.2.0.SJOMIXM`, RAM 4 GB.
- Prioritize latency, smooth scrolling, low heap usage, stable home selection and safe rollback.
- Do not claim speed improvements without measuring both stock MIUI Home and Merlin under comparable conditions.

## Safety
- **Never** disable, uninstall or modify `com.miui.home`, SystemUI, framework, telephone or power-manager services.
- No privileged commands, root, bootloader unlock, partition writes, or OTA changes.
- Never publish repository or user data without explicit consent.
- Avoid invasive permissions: do not add `INTERNET`, `QUERY_ALL_PACKAGES`, accessibility service, or notification listener without clear necessity and authorization.
- Always keep Android's default-app picker as the mechanism for changing home application.

## Implementation
- Keep Kotlin + native Android Views; no Compose or heavyweight dependency unless profiled and justified.
- Use background executor for PackageManager enumeration, reuse GridView cells, avoid network/continuous background services.
- Ensure search, favorites, hide/restore apps, back navigation and default-home selection are testable.
- For Android 11+ package visibility use narrowly scoped `<queries>` for `ACTION_MAIN` + `CATEGORY_LAUNCHER`.
- Validate Android 12 behavior first; MIUI may force three-button navigation for third-party launchers.
- Prefer compiling release/debug variants in GitHub Actions after dependency verification. Check `assembleDebug`, logcat, and ANR/crash before feature expansion.

## Next tasks
1. Build and boot on a real Redmi Note 9; fix any crashes or missing icons.
2. Measure `dumpsys meminfo` (PSS) and `gfxinfo framestats` versus `com.miui.home` under comparable conditions.
3. Verify launcher role selection, HOME/BACK and return after switching apps.
4. Add app list refresh on package changes (with low overhead); currently refreshes periodically on resume.
5. Consider customizable home layout and icon size only after stable benchmarks.
6. Optional: single wallpaper layer, only if it does not worsen smoothness.

## Build
- AGP 8.7.3, Kotlin 2.0.21, Gradle 8.9, Java 17, compile SDK 35.
- CI: `.github/workflows/build-apk.yml` produces `app-debug.apk` artifact.
- No Gradle wrapper binary is bundled; use local Gradle 8.9 or CI.
