{
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  nodejs,
  yarn,
  fetchYarnDeps,
  yarnConfigHook,
  yarnBuildHook,
  sqlcipher,
  applyPatches,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "seshat-node";
  version = "6.0.1";

  src = applyPatches {
    src = fetchFromGitHub {
      owner = "matrix-org";
      repo = "seshat";
      tag = finalAttrs.version;
      hash = "sha256-8he69sTR+UdnABS/3uey1kBxY80cwXCRy7olR/RCcZc=";
    };
    patches = [
      ./fix-cargo-lock.patch
    ];
  };

  sourceRoot = "${finalAttrs.src.name}/seshat-node";

  cargoHash = "sha256-YzlqV4OZwGUaPounv+uLVzSk41rZslZE6vdN3KtxThk=";

  yarnOfflineCache = fetchYarnDeps {
    yarnLock = finalAttrs.src + "/seshat-node/yarn.lock";
    hash = "sha256-nBRq8QDO2BukjDIdZK3HwyyTqA4xfibJcmBlXRUQmfA=";
  };

  nativeBuildInputs = [
    nodejs
    yarn
    yarnConfigHook
    yarnBuildHook
  ];

  buildInputs = [ sqlcipher ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    mv "index."{node,js} "$out"

    runHook postInstall
  '';

  disallowedReferences = [ stdenv.cc.cc ];
})
