# iOS runbook for Scanella / Scan2
#
# Bundle ID: com.scanella.mobile
#
# App Store Connect
# 1. App already uses Scanella bundle ID com.scanella.mobile.
# 2. Ensure GitHub secrets exist on this repo:
#    APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8
#    Optional: IOS_DIST_CERT_P12_BASE64, IOS_DIST_CERT_PASSWORD
# 3. Bump `version:` in pubspec.yaml (e.g. 1.0.1+714). The +N value is the
#    CFBundleVersion uploaded to TestFlight. Push commits must be higher than
#    the last successful TestFlight build.
# 4. Trigger upload by either:
#    - Commit message containing `[testflight]` on main / cursor/**, or
#    - Actions → "iOS Release (signed IPA)" (optional build_number override)
# 5. CI waits for App Store Connect processing and fails if Apple rejects the
#    binary. Install via TestFlight once the run is green.
