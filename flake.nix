{
  description = "Terax - AI-native terminal emulator packaged for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
    ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;

        pname = "terax";
        version = "0.7.1";

        src = lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            let
              base = baseNameOf path;
            in
            !(lib.elem base [
              ".git"
              ".flox"
              "node_modules"
              "dist"
              "result"
              "target"
            ]);
        };

        frontend = pkgs.buildNpmPackage {
          pname = "${pname}-frontend";
          inherit version src;

          npmDepsHash = "sha256-Wdom+Ni3F5kU1wB8czo8Tl7xoxkC5702LIgfpWZNTj4=";

          npmBuildScript = "build";
          npmFlags = [ "--legacy-peer-deps" ];
          npmInstallFlags = [ "--legacy-peer-deps" ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r dist $out/dist
            runHook postInstall
          '';
        };

        commonRuntimeLibraries = with pkgs; [
          webkitgtk_4_1
          gtk3
          glib
          gdk-pixbuf
          cairo
          pango
          atk
          libsoup_3
          openssl
          libayatana-appindicator
        ];

        terax-unwrapped = pkgs.rustPlatform.buildRustPackage {
          pname = "${pname}-unwrapped";
          inherit version src;

          cargoLock.lockFile = ./src-tauri/Cargo.lock;

          postUnpack = ''
            repoRoot="$sourceRoot"
            cp -r ${frontend}/dist "$repoRoot/dist"
            sourceRoot="$repoRoot/src-tauri"
          '';

          nativeBuildInputs = with pkgs; [
            pkg-config
            glib
          ];

          buildInputs = commonRuntimeLibraries;

          cargoBuildFlags = [
            "--bin"
            pname
            "--features"
            "tauri/custom-protocol"
          ];

          # The upstream release profile uses fat LTO + codegen-units=1. That is
          # unnecessarily fragile inside Nix sandboxes for the large Tauri/WebKit
          # dependency graph and can trigger rustc/LLVM stack overflows on NixOS.
          RUST_MIN_STACK = "16777216";
          CARGO_PROFILE_RELEASE_LTO = "false";
          CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";

          # Tauri's bundle step is intentionally not used here. Nix installs the
          # raw binary and the wrapped package below supplies NixOS runtime glue.
          doCheck = false;

          meta = with lib; {
            description = "Terax — an open-source AI-native terminal emulator (unwrapped binary)";
            homepage = "https://github.com/crynta/terax-ai";
            license = licenses.asl20;
            mainProgram = pname;
            platforms = platforms.linux;
          };
        };

        desktopItem = pkgs.makeDesktopItem {
          name = pname;
          desktopName = "Terax";
          genericName = "AI-native terminal emulator";
          comment = "AI-native terminal emulator with editor, explorer, preview and agents";
          exec = "terax %U";
          icon = pname;
          categories = [
            "Development"
            "TerminalEmulator"
            "Utility"
          ];
          startupNotify = true;
        };

        terax = pkgs.symlinkJoin {
          name = "${pname}-${version}";
          paths = [
            terax-unwrapped
            desktopItem
          ];

          nativeBuildInputs = [ pkgs.makeWrapper ];

          postBuild = ''
            rm -f $out/bin/${pname}
            makeWrapper ${terax-unwrapped}/bin/${pname} $out/bin/${pname} \
              --prefix PATH : ${lib.makeBinPath (with pkgs; [
                bashInteractive
                coreutils
                findutils
                git
                gnugrep
                gnused
                ripgrep
                fd
                zsh
                fish
              ])} \
              --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath commonRuntimeLibraries} \
              --set-default WEBKIT_DISABLE_COMPOSITING_MODE 1 \
              --set-default GDK_BACKEND x11,wayland \
              --set-default XCURSOR_PATH ${lib.makeSearchPath "share/icons" (with pkgs; [
                adwaita-icon-theme
                hicolor-icon-theme
              ])}

            mkdir -p $out/share/icons/hicolor/128x128/apps $out/share/icons/hicolor/256x256/apps
            cp ${src}/src-tauri/icons/128x128.png $out/share/icons/hicolor/128x128/apps/${pname}.png
            cp ${src}/src-tauri/icons/128x128@2x.png $out/share/icons/hicolor/256x256/apps/${pname}.png
          '';

          meta = terax-unwrapped.meta // {
            description = "Terax — an open-source AI-native terminal emulator (NixOS wrapped)";
          };
        };
      in
      {
        packages = {
          default = terax;
          wrapped = terax;
          unwrapped = terax-unwrapped;
          frontend = frontend;
        };

        apps = {
          default = flake-utils.lib.mkApp {
            drv = terax;
            exePath = "/bin/${pname}";
          };
          wrapped = flake-utils.lib.mkApp {
            drv = terax;
            exePath = "/bin/${pname}";
          };
          unwrapped = flake-utils.lib.mkApp {
            drv = terax-unwrapped;
            exePath = "/bin/${pname}";
          };
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nodejs_24
            npmHooks.npmConfigHook
            cargo
            rustc
            rustfmt
            clippy
            cargo-tauri
            pkg-config
            webkitgtk_4_1
            gtk3
            glib
            libsoup_3
            openssl
          ];

          LD_LIBRARY_PATH = lib.makeLibraryPath commonRuntimeLibraries;
          WEBKIT_DISABLE_COMPOSITING_MODE = "1";
        };
      }
    );
}
