{
  lib,
  librsvg,
  nixos-icons,
  imagemagick,
  python3,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "nixonfyde-plymouth-theme";
  version = "1.0.0";

  src = ./theme;

  nativeBuildInputs = [
    imagemagick
    librsvg
    python3
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall

    targetDir="$out/share/plymouth/themes/nixonfyde"
    mkdir -p "$targetDir/spinner"
    cp "$src/nixonfyde.plymouth" "$src/nixonfyde.script" \
      "$src/ATTRIBUTION" \
      "$targetDir/"

    for asset in box bullet entry lock; do
      magick "$src/$asset.png" -filter Lanczos -resize 200% \
        "$targetDir/$asset.png"
    done

    python3 - "$src/spinner.svg" "$TMPDIR" <<'PY'
    import pathlib
    import sys

    template_path = pathlib.Path(sys.argv[1])
    output_dir = pathlib.Path(sys.argv[2])
    template = template_path.read_text()

    def ease(value):
        # Invert the SVG's cubic-bezier(0.42, 0, 0.58, 1) timing curve.
        low, high = 0.0, 1.0
        for _ in range(24):
            parameter = (low + high) / 2
            x = 3 * (1 - parameter) ** 2 * parameter * 0.42
            x += 3 * (1 - parameter) * parameter**2 * 0.58
            x += parameter**3
            if x < value:
                low = parameter
            else:
                high = parameter
        parameter = (low + high) / 2
        return 3 * (1 - parameter) * parameter**2 + parameter**3

    for index in range(90):
        phase = index / 90
        if phase < 0.475:
            progress = ease(phase / 0.475)
            dash = 224 * progress
            offset = -85.333333 * progress
        elif phase < 0.95:
            progress = ease((phase - 0.475) / 0.475)
            dash = 224
            offset = -85.333333 - 229.333333 * progress
        else:
            dash = 224
            offset = -314.666667

        frame = f"{index + 1:04d}"
        svg = template.replace("stroke-dasharray=\"224 800\"", f"stroke-dasharray=\"{dash:.6f} 800\"")
        svg = svg.replace("stroke-dashoffset=\"0\"", f"stroke-dashoffset=\"{offset:.6f}\"")
        svg = svg.replace("rotate(-90 64 64)", f"rotate({index * 4 - 90} 64 64)")
        (output_dir / f"spinner-{frame}.svg").write_text(svg)
    PY

    for svg in "$TMPDIR"/spinner-*.svg; do
      frame="''${svg##*-}"
      frame="''${frame%.svg}"
      rsvg-convert --width=48 --height=48 "$svg" \
        --output "$targetDir/spinner/animation-$frame.png"
    done

    magick "$src/fydetab-wordmark-hires.png" -filter Lanczos -resize 554x \
      "$targetDir/fydetab-wordmark.png"

    magick -size 800x8 xc:white "$targetDir/progress-track.png"
    magick -size 800x8 xc:white "$targetDir/progress-fill.png"

    rsvg-convert --width=160 --height=160 \
      "${nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg" \
      --output "$targetDir/nix-snowflake.png"

    # Rewrite /usr/share -> $out/share with --replace-fail to fail loudly if not found
    substituteInPlace "$targetDir/nixonfyde.plymouth" \
      --replace-fail "/usr/share" "$out/share"

    runHook postInstall
  '';

  meta = with lib; {
    description = "NixOnFyde Plymouth boot splash theme";
    license = [
      licenses.cc0
      licenses.cc-by-40
      licenses.gpl2Plus
    ];
    maintainers = [ maintainers.skifli ];
    platforms = platforms.linux;
  };
}
