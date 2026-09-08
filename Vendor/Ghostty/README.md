# Ghostty pin

`pin.json` identifies source, compiler, build flags and SDK compatibility. Run `script/build-engine.sh`; source and artifacts live in ignored `.build-support/ghostty`. The full native artifact is `macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a`. Its PTY/renderer/input API is `include/ghostty.h`, not the independently produced `libghostty-vt`.

Prerequisites:

```sh
mise trust
mise install
xcodebuild -downloadComponent MetalToolchain
mise exec -- ./script/build-engine.sh
```

The engine currently also requires the installed macOS 26.5 Command Line Tools SDK. SDK discovery and LLVM archive packaging are scoped only to the engine build; Xcode 27 builds the app. Upstream Ghostty source is unmodified. `-Dsentry=false` excludes upstream crash-report storage. Zig libc++ fails against the macOS 27 headers, and Xcode 27 libtool drops unaligned Zig archive members. Remove the wrappers when a pinned compatible toolchain builds and verifies without them. See [build dependencies](../../docs/DEPENDENCIES.md).

The MIT notice is retained here and packaged in the development app. Third-party font/dependency redistribution notices must be audited before any distribution. No binary is checked in.
