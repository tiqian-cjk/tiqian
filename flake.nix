{
  description = "Tiqian CJK paragraph layout engine development environment";

  inputs = {
    nixpkgs.url = "flake:nixpkgs";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, rust-overlay }:
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
                git
                rustToolchain
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
          };
        }
      );
    };
}
