# Scan2 — Document Scanner

**Production-quality, cross-platform document scanner mobile app** (Flutter single codebase for iOS + Android).

Original branding. No CamScanner assets, name, or trademarks. Fully offline / on-device.

**Scope**: Document scanning ONLY. No fax, translation, ID photos, cloud accounts, or subscriptions.

## Web Demo Mode (New!)

The app now runs **fully interactively in Chrome** for quick UI testing and iteration:

```powershell
flutter run -d chrome
```

**What works in browser demo mode:**
- Complete Library flow (create documents, delete, navigate)
- Camera screen with mock capture
- Crop & Enhance with draggable corners + all filters + sliders
- Settings and navigation

You will see a visible **"DEMO MODE"** chip in the Library app bar.

Real camera, OCR, and Drift database are used only on actual Android/iOS devices.

This makes it very easy to preview and refine all UI screens without needing a phone or emulator every time.