# App Logo Setup Instructions

## Step 1: Save the Logo Image
1. Save your logo image as `app_logo.png` in this directory (`assets/images/`)
2. **Recommended size**: 1024x1024 pixels (minimum 512x512)
3. **Format**: PNG with transparent background works best

## Step 2: Generate App Icons
After saving the logo, run these commands in the terminal:

```bash
# Install dependencies
flutter pub get

# Generate app icons for Android and iOS
dart run flutter_launcher_icons
```

## Step 3: Clean and Rebuild
```bash
# Clean the build
flutter clean

# Get dependencies again
flutter pub get

# Run the app
flutter run
```

## What Gets Updated
- **Android**: App icon in all densities (mipmap folders)
- **iOS**: App icon in Assets.xcassets
- **Adaptive Icon**: Android 8.0+ adaptive icons with white background

## Current Configuration
Location: `pubspec.yaml`
```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/images/app_logo.png"
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "assets/images/app_logo.png"
```

## Troubleshooting
- If icons don't update, try uninstalling and reinstalling the app
- For Android, check: `android/app/src/main/res/mipmap-*/`
- For iOS, check: `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
