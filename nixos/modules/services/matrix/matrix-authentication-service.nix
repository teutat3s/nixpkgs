{ config, lib, pkgs, ... }:

let
  inherit (lib)
    concatMapStringsSep
    filterAttrsRecursive
    getExe
    mdDoc
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    optional
    optionalAttrs
    types
    ;

  cfg = config.services.matrix-authentication-service;
  format = pkgs.formats.yaml { };

  # remove null values from the final configuration
  finalSettings = filterAttrsRecursive (_: v: v != null) cfg.settings;
  configFile = format.generate "config.yaml" finalSettings;
in
{
  options.services.matrix-authentication-service = {
    enable = mkEnableOption (mdDoc "matrix authentication service");

    package = mkPackageOption pkgs "matrix-authentication-service" { };

    settings = mkOption {
      default = { };
      description = mdDoc ''
        The primary mas configuration. See the
        [configuration reference](https://element-hq.github.io/matrix-authentication-service/usage/configuration.html)
        for possible values.

        Secrets should be passed in by using the `extraConfigFiles` option.
      '';
      type = types.submodule {
        freeformType = format.type;

        options = {
          http.public_base = mkOption {
            type = types.str;
            default = "http://[::]:8080/";
          };
          http.issuer = mkOption {
            type = types.str;
            default = "http://[::]:8080/";
          };
          http.trusted_proxies = mkOption {
            type = types.listOf (types.str);
            default = [ "192.168.0.0/16" "172.16.0.0/12" "10.0.0.0/10" "127.0.0.1/8" "fd00::/8" "::1/128" ];
          };
          http.listeners = mkOption {
            type = types.listOf (types.submodule {
              freeformType = format.type;
              options = {
                name = mkOption {
                  type = types.str;
                  example = "web";
                };
                proxy_protocol = mkOption {
                  type = types.bool;
                };
                resources = mkOption {
                  type = types.listOf (types.submodule {
                    freeformType = format.type;
                    options = {
                      name = mkOption {
                        type = types.str;
                      };
                      path = mkOption {
                        type = types.str;
                        default = "";
                      };
                    };
                  });
                };
                binds = mkOption {
                  type = types.listOf (types.submodule {
                    freeformType = format.type;
                    options = {
                      host = mkOption {
                        type = types.str;
                      };
                      port = mkOption {
                        type = types.ints.unsigned;
                      };
                    };
                  });
                };
              };
            });
            default = [
            {
              name = "web";
              resources = [
                { name = "discovery"; }
                { name = "human"; }
                { name = "oauth"; }
                { name = "compat"; }
                { name = "graphql"; }
                { name = "assets"; path = "${cfg.package}/share/matrix-authentication-service/assets"; }
              ];
              binds = [
                { host = "0.0.0.0"; port = 8080; }
              ];
              proxy_protocol = false;
            }
            {
              name = "internal";
              resources = [
                { name = "health"; }
              ];
              binds = [
                { host = "0.0.0.0"; port = 8081; }
              ];
              proxy_protocol = false;
            }
            ];
          };

          database.uri = mkOption {
            type = types.str;
            default = "postgresql:///matrix-authentication-service?host=/run/postgresql";
            description = ''
              The postgres connection string.
              Refer to <https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING>.
            '';
          };

          database.max_connections = mkOption {
            type = types.ints.unsigned;
            default = 10;
          };

          database.min_connections = mkOption {
            type = types.ints.unsigned;
            default = 0;
          };

          database.connect_timeout = mkOption {
            type = types.ints.unsigned;
            default = 30;
          };

          database.idle_timeout = mkOption {
            type = types.ints.unsigned;
            default = 600;
          };

          database.max_lifetime = mkOption {
            type = types.ints.unsigned;
            default = 1800;
          };

          passwords.enabled = mkOption {
            type = types.bool;
            default = true;
          };

          passwords.schemes = mkOption {
            type = types.listOf (types.submodule {
              freeformType = format.type;
              options = {
                version = mkOption {
                  type = types.ints.unsigned;
                };
                algorithm = mkOption {
                  type = types.str;
                };
              };
            });
            default = [ { version = 1; algorithm = "argon2id"; } ];
          };

          passwords.minimum_complexity = mkOption {
            type = types.ints.unsigned;
            default = 3;
          };

          matrix.homeserver = mkOption {
            type = types.str;
            default = "";
            description = mdDoc ''
              Corresponds to the server_name in the Synapse configuration file.
            '';
          };
          matrix.secret = mkOption {
            type = types.str;
            default = "";
            description = mdDoc ''
              A shared secret the service will use to call the homeserver admin API.
            '';
          };
          matrix.endpoint = mkOption {
            type = types.str;
            default = "";
            description = mdDoc ''
              The URL to which the homeserver is accessible from the service.
            '';
          };
          upstream_oauth2.providers = mkOption {
            type = types.listOf (types.submodule {
              freeformType = format.type;
              options = {
                id = mkOption {
                  type = types.str;
                  example = "01H8PKNWKKRPCBW4YGH1RWV279";
                  description = mdDoc ''
                    Unique id for the provider, must be a ULID, and can be generated using online tools like https://www.ulidtools.com
                  '';
                };
              };
            });
            default = [{}];
            description = mdDoc ''
              Configuration of upstream providers
            '';
          };
        };
      };
    };

    createDatabase = mkOption {
      type = types.bool;
      default = false;
      description = mdDoc ''
        Whether to enable and configure `services.postgres` to ensure that the database user `matrix-authentication-service`
        and the database `matrix-authentication-service` exist.
      '';
    };

    extraConfigFiles = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = ''
        Extra config files to include.

        The configuration files will be included based on the command line
        argument --config. This allows to configure secrets without
        having to go through the Nix store, e.g. based on deployment keys if
        NixOps is in use.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.postgresql = optionalAttrs cfg.createDatabase {
      enable = true;
      ensureDatabases = [ "matrix-authentication-service" ];
      ensureUsers = [ {
        name = "matrix-authentication-service";
        ensureDBOwnership = true;
      } ];
    };

    users.users.matrix-authentication-service = {
      group = "matrix-authentication-service";
      isSystemUser = true;
    };
    users.groups.matrix-authentication-service = { };

    systemd.services.matrix-authentication-service = rec {
      after =
        optional cfg.createDatabase "postgresql.service"
        ++ optional config.services.matrix-synapse.enable config.services.matrix-synapse.serviceUnit;
      wants = after;
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "matrix-authentication-service";
        Group = "matrix-authentication-service";
        ExecStartPre = [
          ("+" + (pkgs.writeShellScript "matrix-authentication-service-check-config" ''
            ${getExe cfg.package} config check \
              ${ concatMapStringsSep " " (x: "--config ${x}") ([ configFile ] ++ cfg.extraConfigFiles) }
          ''))
        ];
        ExecStart = ''
          ${getExe cfg.package} server \
            ${ concatMapStringsSep " " (x: "--config ${x}") ([ configFile ] ++ cfg.extraConfigFiles) }
        '';
        Restart = "on-failure";
        RestartSec = "1s";
      };
    };
  };
}
