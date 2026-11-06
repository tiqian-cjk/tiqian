{
  description = "Tiqian CJK paragraph layout engine development environment";

  inputs = {
    nixpkgs.url = "flake:nixpkgs";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    boring = {
      url = "github:Losses/boring/9fc84f627a65873ee01bc35fd75eba9f18173f15";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };
  };

  outputs =
    { self, nixpkgs, rust-overlay, boring }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [ rust-overlay.overlays.default ];
              config = {
                allowUnfree = true;
                android_sdk.accept_license = true;
              };
            }
          )
        );
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          jdk = pkgs.jdk25;
          # ADR 0050: the Rust precompute stack uses a pinned overlay toolchain;
          # cross-link flags live in Cargo config, not in system probing.
          rustToolchain = pkgs.rust-bin.stable.latest.default;
          androidComposition = pkgs.androidenv.composeAndroidPackages {
            platformVersions = [ "36" ];
            buildToolsVersions = [ "36.0.0" ];
            includeEmulator = false;
            includeSystemImages = false;
            includeNDK = true;
            ndkVersion = "29.0.13599879-rc2";
            cmakeVersions = [ "3.22.1" ];
            includeSources = false;
          };
        in
        {
          default = pkgs.mkShell {
            packages =
              with pkgs;
              [
                jdk
                nodejs_22
                bun
                boring.packages.${pkgs.stdenv.hostPlatform.system}.driver
                git
                rustToolchain
                haxe
                # Toolchains used by engine-haxe generation and tests: dart
                # and kotlin below. The Swift toolchain comes from boring's
                # linux-swift package (a FHS-wrapped swiftc), added on
                # x86_64-linux in the optionals clause after this list.
                dart
                kotlin
              ]
              ++ pkgs.lib.optionals (pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64) [
                boring.packages.${pkgs.stdenv.hostPlatform.system}.linux-swift
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
                chromium
                firefox
                noto-fonts
                noto-fonts-cjk-sans
                roboto
                inter
              ];
            FONTCONFIG_FILE = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux
              "${pkgs.makeFontsConf { fontDirectories = [ pkgs.noto-fonts pkgs.noto-fonts-cjk-sans pkgs.roboto pkgs.inter ]; }}";
            JAVA_HOME = "${jdk.passthru.home}";
            CHROME_BIN = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux "${pkgs.chromium}/bin/chromium";
            FIREFOX_BIN = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux "${pkgs.firefox}/bin/firefox";
            ANDROID_HOME = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux
              "${androidComposition.androidsdk}/libexec/android-sdk";
            LD_LIBRARY_PATH = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux (
              pkgs.lib.makeLibraryPath [
                pkgs.fontconfig
                pkgs.freetype
                pkgs.libGL
                pkgs.libx11
                pkgs.libxcursor
                pkgs.libxrandr
                pkgs.libxi
                pkgs.libxrender
              ]
            );
            # Swift toolchain env shared with boring's own devShell. The
            # Linux x86_64 branch carries the libdispatch runtime path (a
            # swift toolchain store path not covered by the RUNPATH of
            # linked test binaries) and a pinned glibc dynamic linker, both
            # consumed by boring gen swift and the swift-f32/f64 bundle
            # tests. SystemPackage is the prebuilt swift-system module.
            BORING_SWIFT_SYSTEM_PACKAGE = "${boring.packages.${pkgs.stdenv.hostPlatform.system}.swift-system}";
            BORING_SWIFT_LIBDISPATCH = pkgs.lib.optionalString (pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64)
              "${boring.packages.${pkgs.stdenv.hostPlatform.system}.linux-swift.passthru.libdispatch}:${pkgs.gcc.cc.lib}/lib";
            BORING_SWIFT_DYNAMIC_LINKER = pkgs.lib.optionalString (pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64)
              "${pkgs.glibc}/lib/ld-linux-x86-64.so.2";
            shellHook = ''
              export HAXELIB_PATH="$PWD/.haxelib"
              mkdir -p "$HAXELIB_PATH/boring"
              boring_git="$HAXELIB_PATH/boring/git"
              if [ ! -f "$boring_git/.boring-flake-revision" ] || \
                 [ "$(cat "$boring_git/.boring-flake-revision")" != "${boring.rev or "unversioned-source"}" ] || \
                 [ ! -f "$boring_git/.boring-flake-source" ] || \
                 [ "$(cat "$boring_git/.boring-flake-source")" != "${boring}" ]; then
                if [ -e "$boring_git" ] || [ -L "$boring_git" ]; then
                  boring_backup="$boring_git.pre-flake-$(date +%Y%m%d%H%M%S)"
                  mv "$boring_git" "$boring_backup"
                  echo "tiqian devShell: saved previous boring checkout at $boring_backup" >&2
                fi
                mkdir -p "$boring_git"
                cp -a "${boring}/." "$boring_git/"
                chmod -R u+w "$boring_git"
                printf '%s\n' "${boring.rev or "unversioned-source"}" > "$boring_git/.boring-flake-revision"
              fi
              printf '%s\n' "${boring}" > "$boring_git/.boring-flake-source"
              haxelib dev boring "$boring_git" >/dev/null
              haxelib dev reflaxe "${boring.inputs.reflaxe}" >/dev/null
              haxelib install format 3.8.0 >/dev/null
              haxelib install formatter 1.18.0 >/dev/null
              if [ -f "$PWD/boring.json" ] && [ -d "$PWD/engine-haxe/targets" ]; then
                boring roots engine --project boring.json --output engine-haxe/targets/classes.hxml >/dev/null
              fi
            '';
          };
        }
      );
    };
}
