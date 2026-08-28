{
  stdenv,
  fetchurl,
  lib,
}:

let
  src_base = "https://raw.githubusercontent.com/NixOnFyde/rknn-toolkit2/59a913d172e7f5ff03c9076e2ec7b1b1288ffd08/rknpu2/runtime/Linux/librknn_api";
in
stdenv.mkDerivation {
  pname = "librknnrt";
  version = "2024-10-01";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  propagatedBuildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm644 ${
      fetchurl {
        url = "${src_base}/aarch64/librknnrt.so";
        sha256 = "1s1qqyx95v02ci9zn2s19r52dmb2v7wnl3xxna8n0pxqhnfc27yk";
      }
    } $out/lib/librknnrt.so

    install -Dm644 ${
      fetchurl {
        url = "${src_base}/include/rknn_api.h";
        sha256 = "16msvqhiplm33srfkgkq9zcx6lh2lr77gbg4s5gili8vyjk133n4";
      }
    } $out/include/rknn_api.h

    install -Dm644 ${
      fetchurl {
        url = "${src_base}/include/rknn_custom_op.h";
        sha256 = "19naihxjxk991xvplv0r65ajic126dlalqiivhqwli521kd86ndg";
      }
    } $out/include/rknn_custom_op.h

    install -Dm644 ${
      fetchurl {
        url = "${src_base}/include/rknn_matmul_api.h";
        sha256 = "0hjd9bqnffn8k1x1m4zm01fhjxyv65knp692n830mqwd26kxkbda";
      }
    } $out/include/rknn_matmul_api.h
    runHook postInstall
  '';

  meta = with lib; {
    description = "Rockchip RKNN runtime library";
    homepage = "https://github.com/NixOnFyde/rknn-toolkit2";
    license = licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
