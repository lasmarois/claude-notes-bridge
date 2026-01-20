# Build Instructions

## NotesSearch App (SwiftUI)

### Quick Build & Run
```bash
swift build --product notes-search
.build/debug/notes-search
```

### Clean Build (if issues occur)
```bash
swift package clean
swift build --product notes-search
```

### Build as macOS App Bundle (with code signing)
```bash
# Build
swift build --product notes-search

# Create app bundle
mkdir -p .build/NotesSearch.app/Contents/MacOS

# Copy binary
cp -f .build/debug/notes-search .build/NotesSearch.app/Contents/MacOS/NotesSearch

# Create Info.plist
cat > .build/NotesSearch.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NotesSearch</string>
    <key>CFBundleIdentifier</key>
    <string>com.claude.notes-search</string>
    <key>CFBundleName</key>
    <string>Notes Search</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

# Sign (required for Full Disk Access permissions)
codesign --force --deep --sign - .build/NotesSearch.app

# Launch
open .build/NotesSearch.app
```

### Full Disk Access
- The app needs Full Disk Access to read the Apple Notes database
- **Option A**: Add `.build/NotesSearch.app` to System Settings > Privacy & Security > Full Disk Access (requires signed app bundle)
- **Option B**: Add `Terminal.app` to Full Disk Access, then run `.build/debug/notes-search` from terminal (inherits permissions)

### Troubleshooting

| Issue | Solution |
|-------|----------|
| Can't add app to FDA | Sign the app bundle with `codesign` |
| Keyboard focus goes to terminal | Use the signed `.app` bundle, not raw binary |
| Old UI after rebuild | Kill running instances: `pkill -f notes-search` |
| Build errors after clean | Run `swift package clean` then rebuild |
