# Desktop packaging

Scripts for producing distributable desktop builds. Everything lands in `dist/`,
which is gitignored.

| Platform | Script | Produces |
| --- | --- | --- |
| Linux | `packaging/linux/build-appimage.sh` | `UncensoredLocalAI-<version>-x86_64.AppImage` |
| Windows | `packaging/windows/build-installer.ps1` | `...-windows-x64-setup.exe` + `...-portable.zip` |
| macOS | `packaging/macos/build-and-notarize.sh` | `...-macos.zip` (optionally `.dmg`) |

All three read the version from `pubspec.yaml`, so bump it there and nowhere else.

---

## Linux — AppImage

```bash
./packaging/linux/build-appimage.sh
```

Builds the release bundle, assembles an AppDir with a desktop entry and an
`AppRun` that fixes up `LD_LIBRARY_PATH`, then downloads `appimagetool` on first
run and produces a single executable file.

**Build dependencies** (Debian/Ubuntu):

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev
```

On Fedora: `clang cmake ninja-build gtk3-devel xz-devel`.
On Arch: `clang cmake ninja gtk3 xz`.

`appimagetool` normally needs FUSE. The script passes
`--appimage-extract-and-run` first so it works in containers and CI where FUSE
is unavailable, falling back to the normal path if that fails.

**Verified working:** built and launched on Linux x64, Flutter 3.47.2, Impeller
OpenGLES backend. The resulting AppImage is ~26 MB.

Models and chat history are stored outside the read-only image, under
`$XDG_DATA_HOME` (`~/.local/share` by default), so they survive replacing the
AppImage with a newer one.

---

## Windows — installer + portable zip

```powershell
.\packaging\windows\build-installer.ps1
```

Options:

| Flag | Effect |
| --- | --- |
| `-SkipBuild` | Package the existing `build\windows\x64\runner\Release` |
| `-PortableOnly` | Produce only the zip, skip the installer |

The portable zip is always produced. The installer additionally needs
[Inno Setup 6](https://jrsoftware.org/isdl.php):

```powershell
winget install JRSoftware.InnoSetup
```

If Inno Setup is absent the script says so and still leaves you the zip.

### Code signing

The installer is unsigned, so SmartScreen shows "Windows protected your PC" on
first run until the binary builds reputation. To sign with an EV or OV
certificate:

```powershell
signtool sign /tr http://timestamp.digicert.com /td sha256 /fd sha256 `
  /a dist\UncensoredLocalAI-<version>-windows-x64-setup.exe
```

Sign `portable_ai_flutter.exe` inside the Release directory *before* running the
packaging script, so the signature ends up inside the installer too.

---

## macOS — sign, notarize, staple

```bash
./packaging/macos/build-and-notarize.sh              # build + zip
./packaging/macos/build-and-notarize.sh --sign       # + codesign
./packaging/macos/build-and-notarize.sh --notarize   # + notarize + staple
./packaging/macos/build-and-notarize.sh --notarize --dmg
```

### One-time setup

1. A **Developer ID Application** certificate in your login keychain
   (Apple Developer Program membership required).
2. An app-specific password from <https://appleid.apple.com>, stored as a
   notarytool profile:

```bash
xcrun notarytool store-credentials "ula-notary" \
  --apple-id "you@example.com" \
  --team-id "ABCDE12345" \
  --password "abcd-efgh-ijkl-mnop"
```

Override the defaults with `SIGN_IDENTITY` and `NOTARY_PROFILE`.

### Why the nested signing loop

The app bundles llama.cpp backend `.dylib`s. Codesign requires nested code to be
signed before the enclosing bundle, so the script signs those first and the
`.app` last.

### Entitlements

`macos/Runner/Release.entitlements` grants what the app actually needs under the
sandbox:

| Entitlement | Needed for |
| --- | --- |
| `network.client` | Downloading GGUF models |
| `network.server` | The built-in OpenAI-compatible API server |
| `files.user-selected.read-write` | Importing a `.gguf` from disk |
| `cs.allow-jit` | llama.cpp runtime kernel compilation |
| `cs.disable-library-validation` | `ggml_backend_load_all()` loading backend dylibs |

Before this was fixed, the release entitlements granted only `app-sandbox`, so a
signed release build could not download models, could not start the API server,
and could not import a model file.

### App Store

Notarized Developer ID distribution is what these scripts target. App Store
submission additionally needs a **Mac App Store** provisioning profile, a
`Apple Distribution` certificate, and removal of
`cs.disable-library-validation`, which App Review rejects — that requires the
llama backends to be signed with the same team identity as the app.

---

## Release checklist

1. Bump `version:` in `pubspec.yaml`.
2. Update `CHANGELOG.md`.
3. `flutter analyze && flutter test`
4. Build each platform with the scripts above.
5. Verify each artifact launches on a clean machine.
6. Attach everything in `dist/` to the GitHub release.
