{
  description = "Tiqian CJK paragraph layout engine development environment";

  inputs = {
    nixpkgs.url = "flake:nixpkgs";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    boring = {
      url = "github:Losses/boring/ad33ad870f73c5baa032b91fe7325810f2e6ddd8";
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
                # SwiftPM unpacks registry source archives with the host
                # unzip binary; without it every registry fetch fails with
                # "could not find executable for 'unzip'".
                unzip
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
            # boring input source tree; its tools/unicode-data carries the
            # Unicode 17.0.0 data files staged by tools/setup-haxe-env.sh.
            BORING_SOURCE = "${boring.outPath}";
            shellHook = ''
              # HAXELIB_PATH and the boring dev checkout belong to the flake
              # root: boring.json states the `.haxelib/boring/git/...` classpaths
              # relative to it, and CI runs `nix develop` from the repository
              # root. Resolve the root from the
              # invocation directory so a subdirectory invocation still stages
              # the haxelib tree those classpaths point at.
              tq_flake_root="$PWD"
              while [ "$tq_flake_root" != "/" ] && [ ! -f "$tq_flake_root/flake.nix" ]; do
                tq_flake_root="$(dirname "$tq_flake_root")"
              done
              if [ ! -f "$tq_flake_root/flake.nix" ]; then
                tq_flake_root="$PWD"
              fi
              export HAXELIB_PATH="$tq_flake_root/.haxelib"
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
              install_haxelib() {
                local name="$1" version="$2" attempt
                for attempt in 1 2 3; do
                  if haxelib install "$name" "$version" >/dev/null 2>&1; then
                    return 0
                  fi
                  echo "tiqian devShell: haxelib install $name $version failed (attempt $attempt)" >&2
                  sleep 5
                done
                return 1
              }
              if [ ! -d "$HAXELIB_PATH/format/3,8,0" ] && ! install_haxelib format 3.8.0; then
                echo "tiqian devShell: failed to install haxelib format 3.8.0" >&2
                exit 1
              fi
              if [ ! -d "$HAXELIB_PATH/formatter/1,18,0" ] && ! install_haxelib formatter 1.18.0; then
                echo "tiqian devShell: failed to install haxelib formatter 1.18.0" >&2
                exit 1
              fi
            '';
          };
        }
      );
    };
}
