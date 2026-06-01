{
  description = "libdave - Discord Audio & Video Encryption Protocol";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};

        mlspp-custom = pkgs.stdenv.mkDerivation {
          pname = "mlspp";
          version = "custom";
          src = pkgs.fetchFromGitHub {
            owner = "cisco";
            repo = "mlspp";
            rev = "1cc50a124a3bc4e143a787ec934280dc70c1034d";
            sha256 = "sha256-IjS2yYnfScwJR3BqDJp37ANgNkCg9ECxON41tYEocvA=";
          };
          nativeBuildInputs = [pkgs.cmake];
          buildInputs = [pkgs.openssl_3 pkgs.nlohmann_json];
          NIX_CFLAGS_COMPILE = "-Wno-error=maybe-uninitialized";
          cmakeFlags = [
            "-DMLS_CXX_NAMESPACE=mlspp"
            "-DDISABLE_GREASE=ON"
          ];
        };
      in {
        # devshell (mostly untested)
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs;
            [
              cmake # Requires CMake 3.20+
              gnumake
              nasm # Assembly compiler required by BoringSSL/OpenSSL
              go # Required by CI build scripts (especially for BoringSSL)
              pkg-config
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              llvmPackages_18.clang # Explicitly requested by macOS CI
            ];

          shellHook = ''
            export BUILD_DIR="$PWD/build"
            ${pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
              export CXX="${pkgs.llvmPackages_18.clang}/bin/clang++"
              export CC="${pkgs.llvmPackages_18.clang}/bin/clang"
            ''}
            echo "Loaded libdave dev environment."
            echo "To build using the native vcpkg workflow, run: make all"
          '';
        };

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "libdave";
          version = "1.0.1"; # Version matches the JS package.json
          src = ./.;

          # hack to have LICENSE file available
          preConfigure = ''
            cd cpp
          '';

          nativeBuildInputs = with pkgs; [
            cmake
            nasm
            pkg-config
          ];

          buildInputs = with pkgs; [
            openssl_3 # Default crypto backend in libdave's Makefile
            nlohmann_json # JSON parsing
            gtest # Unit testing
            mlspp-custom # custom mlspp build (see above)
          ];

          cmakeFlags = [
            "-DBUILD_SHARED_LIBS=OFF" # Default is OFF, matching Makefile 'make' target
            "-DPERSISTENT_KEYS=OFF" # Default is OFF
            "-DTESTING=ON" # Enable googletest targets
            "-DCMAKE_TOOLCHAIN_FILE=" # Deliberately clear this to disable vcpkg integration
          ];

          doCheck = true;
          installPhase = ''
            make install DESTDIR=$out
            mkdir -p $out/lib/pkgconfig
            cat <<EOF > $out/lib/pkgconfig/dave.pc
prefix=$out
exec_prefix=\''${prefix}
libdir=\''${prefix}/lib
includedir=\''${prefix}/include
Name: dave
Description: Discord Audio & Video Encryption (DAVE) Protocol
Version: 1.0.1
Libs: -L\''${libdir} -ldave
Cflags: -I\''${includedir}
EOF
          '';
        };
      }
    );
}
