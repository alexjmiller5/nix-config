{ python3Packages, fetchPypi, fetchurl }:
let
  qh3 = python3Packages.buildPythonPackage {
    pname = "qh3";
    version = "1.5.6";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/4c/5c/6c49f8d12da29eedd048039c1b3c33ffd4db8c2ed4c82afe91d31f00afc4/qh3-1.5.6-cp37-abi3-macosx_10_12_x86_64.macosx_11_0_arm64.macosx_10_12_universal2.whl";
      hash = "sha256-KLA/4MfYmJxClCbgdE1O6h/9l2qP5OY6AWTCtW6NSXY=";
    };
    pythonImportsCheck = [ "qh3.quic.packet_builder" ];
  };
  # PyIMG4 requires the ASN.1 2.x API until upstream supports 3.x.
  asn1 = python3Packages.asn1.overridePythonAttrs (_: {
    version = "2.8.0";
    src = fetchPypi {
      pname = "asn1";
      version = "2.8.0";
      hash = "sha256-rfd93CcHz0IMDq47me4w6ROvzwk2Rn1CZpggzmt9FQo=";
    };
  });
  pyimg4 = python3Packages.pyimg4.override { inherit asn1; };
  ipsw-parser = python3Packages.ipsw-parser.override { inherit pyimg4; };
in
python3Packages.pymobiledevice3.override { inherit ipsw-parser qh3; }
