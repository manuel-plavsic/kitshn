{
  description = "Development environment for kitshn (Kotlin Multiplatform / Compose Multiplatform)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          config.android_sdk.accept_license = roles.android;
        };

        isMac = pkgs.stdenv.isDarwin;
        isLinux = pkgs.stdenv.isLinux;

        # check if a flag is enabled
        enabled = v: v == "1";

        # disable roles with e.g. `NO_ANDROID=1 nix develop --impure`
        roles = {
          android = !enabled (builtins.getEnv "NO_ANDROID");
          # Android emulator + system image (large download)
          emulator = !enabled (builtins.getEnv "NO_ANDROID") && !enabled (builtins.getEnv "NO_EMULATOR");
          ios = !enabled (builtins.getEnv "NO_IOS") && isMac; # iOS builds only work on macOS
          linux = !enabled (builtins.getEnv "NO_LINUX") && isLinux;
          macos = !enabled (builtins.getEnv "NO_MACOS") && isMac;
        };

        # must match `jvmToolchain(21)` in the Gradle build files
        jdk = pkgs.jdk21;

        # must match `compileSdk` in the Gradle build files
        androidPlatformVersion = "37.0";
        androidBuildToolsVersion = "37.0.0";

        # Gradle itself is provided by the wrapper (./gradlew)
        jvmTools = [
          jdk
          pkgs.kotlin # kotlinc, for quick experiments outside of Gradle
          pkgs.kotlin-language-server
        ];

        webTools = with pkgs; [
          nodejs # REQUIRED to build the documentation website in web/
        ];

        releaseTools = with pkgs; [
          ruby # REQUIRED for fastlane (see Gemfile)
          bundler
        ];

        extraTools = with pkgs; [
          codebook # efficient spellchecker for code
          nil # Nix language server (older)
          nixd # Nix language server (newer)
          nixfmt-rfc-style # Official Nix formatter
          nushell # powerful and pragmatic shell written in Rust
          tombi # TOML language server (gradle/libs.versions.toml)
        ];

        linuxLdLibraryPath =
          if roles.linux then
            with pkgs;
            [
              libGL # REQUIRED to run the Compose Desktop app (Skiko) with OpenGL
              fontconfig
              freetype
              libx11
              libxext
              libxrender
              libxtst
              libxi
              libxrandr
              libxcursor
            ]
          else
            [ ];

        androidLdLibraryPath =
          if roles.emulator && isLinux then
            [
              pkgs.vulkan-loader
              pkgs.libGL # REQUIRED to run the emulator with OpenGL (common fallback from Vulkan to OpenGL in case of `useVulkanComposition: false`)
            ]
          else
            [ ];

        androidTools = if roles.android then [ androidSdk ] else [ ];

        iosTools = if roles.ios then [ pkgs.cocoapods ] else [ ];

        # complements androidTools
        androidSdk =
          if roles.android then
            let
              androidEnv = pkgs.androidenv.override { licenseAccepted = true; };
              composition = androidEnv.composeAndroidPackages {
                cmdLineToolsVersion = "19.0";
                buildToolsVersions = [
                  "36.0.0" # default of AGP 9.2 (used when `buildToolsVersion` is not set)
                  androidBuildToolsVersion
                ];
                platformVersions = [ androidPlatformVersion ];
                abiVersions = abiVersions;
                includeEmulator = roles.emulator;
                includeSystemImages = roles.emulator;
                systemImageTypes = [ "google_apis_playstore" ];
              };
            in
            composition.androidsdk
          else
            null;

        androidSdkRoot = "${androidSdk}/libexec/android-sdk";

        # complements androidSdk
        abiVersions =
          if system == "x86_64-linux" || system == "x86_64-darwin" then
            [ "x86_64" ]
          else if system == "aarch64-linux" || system == "aarch64-darwin" then
            [ "arm64-v8a" ]
          else
            builtins.throw "Unsupported architecture: ${system}. Only x86_64-linux, x86_64-darwin, aarch64-linux, and aarch64-darwin are supported for Android development.";
      in
      {
        devShells.default = pkgs.mkShell {
          name = "kitshn";

          buildInputs =
            jvmTools
            ++ webTools
            ++ releaseTools
            ++ extraTools
            ++ androidTools
            ++ iosTools;

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (linuxLdLibraryPath ++ androidLdLibraryPath);

          JAVA_HOME = jdk.home;

          # Android emulator graphics envars
          QT_QPA_PLATFORM = if (roles.emulator && isLinux) then "wayland;xcb" else null;
          LIBGL_DRIVERS_PATH = if (roles.emulator && isLinux) then "/run/opengl-driver/lib/dri" else null;
          VK_ICD_FILENAMES =
            if (roles.emulator && isLinux) then
              "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json:/run/opengl-driver/share/vulkan/icd.d/intel_icd.x86_64.json:/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json:/run/opengl-driver/share/vulkan/icd.d/gfxstream_vk_icd.x86_64.json"
            else
              null;

          # Android envars
          ANDROID_HOME = if roles.android then androidSdkRoot else null;
          ANDROID_SDK_ROOT = if roles.android then androidSdkRoot else null;
          # the aapt2 binary AGP downloads from Maven does not run on NixOS, use the one from the SDK
          GRADLE_OPTS =
            if roles.android then
              "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidSdkRoot}/build-tools/${androidBuildToolsVersion}/aapt2"
            else
              null;

          shellHook = ''
            echo "Loaded roles:"
            echo "  android:  ${toString roles.android}"
            echo "  emulator: ${toString roles.emulator}"
            echo "  ios:      ${toString roles.ios}"
            echo "  linux:    ${toString roles.linux}"
            echo "  macos:    ${toString roles.macos}"

            ${pkgs.lib.optionalString roles.ios ''
              # use Xcode's toolchain instead of the one from the nix store
              unset DEVELOPER_DIR
              unset SDKROOT
              export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v xcbuild | paste -sd:)
            ''}
          '';
        };
      }
    );
}
