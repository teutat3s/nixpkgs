{ config, lib, pkgs, ... }:

let
  cfg = config.services.matrix-authentication-service;
  format = pkgs.formats.yaml { };

  # remove null values from the final configuration
  finalSettings = lib.filterAttrsRecursive (_: v: v != null) cfg.settings;
  configFile = format.generate "config.yaml" finalSettings;
in
{
  options.services.matrix-authentication-service = {
    enable = lib.mkEnableOption (lib.mdDoc "matrix authentication service");

    package = lib.mkPackageOption pkgs "matrix-authentication-service" { };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/matrix-authentication-service";
      description = lib.mdDoc ''
        The directory where matrix-authentication-service stores its stateful data such as
        certificates, media and uploads.
      '';
    };

    settings = lib.mkOption {
      default = { };
      description = lib.mdDoc ''
        The primary mas configuration. See the
        [configuration reference](https://matrix-org.github.io/matrix-authentication-service/usage/configuration.html)
        for possible values.

        Secrets should be passed in by using the `extraConfigFiles` option.
      '';
      type = with lib.types; submodule {
        freeformType = format.type;
        options = {
          database.uri = lib.mkOption {
            type = lib.types.str;
            default = "postgresql:///matrix-authentication-service?host=/run/postgresql";
            description = lib.mdDoc ''
              The database uri.
            '';
          };
          matrix.homeserver = lib.mkOption {
            type = lib.types.str;
            default = "localhost:8008";
            description = lib.mdDoc ''
              Corresponds to the server_name in the Synapse configuration file.
            '';
          };
          matrix.secret = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = lib.mdDoc ''
              A shared secret the service will use to call the homeserver admin API.
            '';
          };
          matrix.endpoint = lib.mkOption {
            type = lib.types.str;
            default = "http://localhost:8008";
            description = lib.mdDoc ''
              The URL to which the homeserver is accessible from the service.
            '';
          };
          upstream_oauth2.providers = lib.mkOption {
            type = types.listOf (types.submodule {
              freeformType = format.type;
              options = {
                id = lib.mkOption {
                  type = types.str;
                  example = "01H8PKNWKKRPCBW4YGH1RWV279";
                  description = lib.mdDoc ''
                    Unique id for the provider, must be a ULID, and can be generated using online tools like https://www.ulidtools.com
                  '';
                };
              };
            });
            default = [{}];
            description = lib.mdDoc ''
              Configuration of upstream providers
            '';
          };
        };
      };
    };

    createDatabase = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = lib.mdDoc ''
        Whether to enable and configure `services.postgres` to ensure that the database user `matrix-authentication-service`
        and the database `matrix-authentication-service` exist.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      description = lib.mdDoc ''
        Environment file as defined in {manpage}`systemd.exec(5)`.

        This must contain the {env}`SYNCV3_SECRET` variable which should
        be generated with {command}`openssl rand -hex 32`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = lib.optionalAttrs cfg.createDatabase {
      enable = true;
      ensureDatabases = [ "matrix-authentication-service" ];
      ensureUsers = [ {
        name = "matrix-authentication-service";
        ensureDBOwnership = true;
      } ];
    };

    users.users.matrix-authentication-service = {
      group = "matrix-authentication-service";
      home = cfg.dataDir;
      createHome = true;
      shell = "${pkgs.bash}/bin/bash";
      uid = config.ids.uids.matrix-authentication-service;
    };

    users.groups.matrix-authentication-service = {
      gid = config.ids.gids.matrix-authentication-service;
    };

    systemd.services.matrix-authentication-service = rec {
      after =
        lib.optional cfg.createDatabase "postgresql.service"
        ++ lib.optional config.services.matrix-synapse.enable config.services.matrix-synapse.serviceUnit;
      wants = after;
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "matrix-authentication-service";
        Group = "matrix-authentication-service";
        WorkingDirectory = cfg.dataDir;
        ExecStartPre = [
          ("+" + (pkgs.writeShellScript "matrix-authentication-service-generate-config" ''
            ${lib.getExe cfg.package} config generate > ${cfg.dataDir}/config.yaml
            ${lib.getExe cfg.package} config check --config ${cfg.dataDir}/config.yaml --config ${configFile}
          ''))
        ];
        ExecStart = ''
          ${lib.getExe cfg.package} server --migrate --config ${cfg.dataDir}/config.yaml --config ${configFile}
        '';
        Restart = "on-failure";
        RestartSec = "1s";
      };
    };
  };
}
