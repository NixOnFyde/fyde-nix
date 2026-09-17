{
  stdenv,
  ghostty,
  makeWrapper,
  libGL,
}:

let
  shim = stdenv.mkDerivation {
    pname = "ghostty-zink-shim";
    version = "0.1.0";
    src = ./ghostty-zink-shim.c;
    dontUnpack = true;
    nativeBuildInputs = [ ];
    buildInputs = [ libGL ];
    buildPhase = ''
      cc -shared -fPIC -o libghostty-zink-shim.so $src -ldl
    '';
    installPhase = ''
      mkdir -p $out/lib
      cp libghostty-zink-shim.so $out/lib/
    '';
  };
in
stdenv.mkDerivation {
  pname = "ghostty-zink";
  version = ghostty.version;
  nativeBuildInputs = [ makeWrapper ];
  buildCommand = ''
    cp -r ${ghostty} $out
    chmod -R u+w $out
    wrapProgram $out/bin/ghostty \
      --set LD_PRELOAD ${shim}/lib/libghostty-zink-shim.so \
      --set MESA_LOADER_DRIVER_OVERRIDE zink
  '';
  meta = ghostty.meta // {
    description = "Ghostty with Zink (GL-on-Vulkan)";
  };
}
