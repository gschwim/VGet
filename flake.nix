{
  description = "VGet — Flutter clients + yt-dlp backend";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells = {
          # Backend: FastAPI + yt-dlp + ffmpeg
          backend = pkgs.mkShell {
            buildInputs = with pkgs; [
              python312
              python312.pkgs.pip
              python312.pkgs.virtualenv
              ffmpeg
            ];
            shellHook = ''
              echo "VGet backend shell (Python $(python --version 2>&1 | cut -d' ' -f2))"
              if [ ! -d backend/.venv ]; then
                python -m venv backend/.venv
              fi
              source backend/.venv/bin/activate
              echo "venv active — run: pip install -r backend/requirements.txt"
            '';
          };

          # Flutter client: desktop (macOS) + web + mobile toolchains
          flutter = pkgs.mkShell {
            buildInputs = with pkgs; [
              flutter
              cocoapods
              jdk17
            ];
            shellHook = ''
              echo "VGet flutter shell"
              flutter --version 2>/dev/null || echo "run 'flutter doctor' to finish setup"
            '';
          };
        };
      });
}
