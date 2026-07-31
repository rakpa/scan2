# iOS runbook for Scan2
#
# Bundle ID: com.scan2.scan2
#
# App Store Connect
# 1. Create an app with bundle ID com.scan2.scan2 (if it does not exist yet).
# 2. Ensure GitHub secrets exist on this repo (same as your other apps):
#    APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8
#    Optional: IOS_DIST_CERT_P12_BASE64, IOS_DIST_CERT_PASSWORD
# 3. Run Actions → "iOS Release (signed IPA)" with upload_to_testflight=true
#    and a new build_number each upload.
# 4. Install via TestFlight once processing finishes.
