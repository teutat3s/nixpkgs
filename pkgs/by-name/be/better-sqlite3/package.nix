{ lib
, buildNpmPackage
, fetchFromGitHub
, python3
}:

buildNpmPackage rec {
  pname = "better-sqlite3";
  version = "11.1.2";

  src = fetchFromGitHub {
    owner = "WiseLibs";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-qYE9R8ziGxLbPVP5b34fZVowAHlz1VEYuQBJNKgE1s8=";
  };
  nativeBuildInputs = [
    python3
  ];

  npmDepsHash = "sha256-Ksbj7fT53uVY5DdlX7PUn6Xntg9rLCY+DJso8nM0zFE=";
  npmBuildScript = "prebuild";

  prePatch = ''
    cp ${./package-lock.json} ./package-lock.json
    chmod +w ./package-lock.json
  '';

  buildPhase = ''
    runHook preBuild

    npx --no prebuild -r electron -t 30.0.0 --include-regex 'better_sqlite3.node$'

    runHook postBuild
  '';

  #passthru = {
  #  tests.version = testers.testVersion {
  #    package = triton;
  #  };
  #};

  meta = {
    description = "TritonDataCenter Client CLI and Node.js SDK";
    homepage = "https://github.com/TritonDataCenter/node-triton";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ teutat3s ];
    mainProgram = "triton";
  };
}
