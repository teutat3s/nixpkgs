import ../make-test-python.nix (
  { pkgs, ... }:
  let
    # Set up SSL certs for Synapse to be happy.
    runWithOpenSSL = file: cmd: pkgs.runCommand file
      {
        buildInputs = [ pkgs.openssl ];
      }
      cmd;

    ca_key = runWithOpenSSL "ca-key.pem" "openssl genrsa -out $out 2048";
    ca_pem = runWithOpenSSL "ca.pem" ''
      openssl req \
        -x509 -new -nodes -key ${ca_key} \
        -days 10000 -out $out -subj "/CN=snakeoil-ca"
    '';
    key = runWithOpenSSL "matrix_key.pem" "openssl genrsa -out $out 2048";
    csr = runWithOpenSSL "matrix.csr" ''
      openssl req \
         -new -key ${key} \
         -out $out -subj "/CN=localhost" \
    '';
    cert = runWithOpenSSL "matrix_cert.pem" ''
      openssl x509 \
        -req -in ${csr} \
        -CA ${ca_pem} -CAkey ${ca_key} \
        -CAcreateserial -out $out \
        -days 365
    '';
  in
  {
    name = "draupnir";
    meta = with pkgs.lib; {
      maintainers = [ maintainers.RorySys ];
    };

    nodes = {
      homeserver = { pkgs, ... }: {
        services.matrix-synapse = {
          enable = true;
          settings = {
            database.name = "sqlite3";
            tls_certificate_path = "${cert}";
            tls_private_key_path = "${key}";
            enable_registration = true;
            enable_registration_without_verification = true;
            registration_shared_secret = "supersecret-registration";

            listeners = [ {
              # The default but tls=false
              bind_addresses = [
                "0.0.0.0"
              ];
              port = 8448;
              resources = [ {
                compress = true;
                names = [ "client" ];
              } {
                compress = false;
                names = [ "federation" ];
              } ];
              tls = false;
              type = "http";
              x_forwarded = false;
            } ];
          };
        };

        networking.firewall.allowedTCPPorts = [ 8448 ];

        environment.systemPackages = [
          (pkgs.writeShellScriptBin "register_draupnir_user" ''
            exec ${pkgs.matrix-synapse}/bin/register_new_matrix_user \
              -u draupnir \
              -p draupnir-password \
              --admin \
              --shared-secret supersecret-registration \
              http://localhost:8448
          ''
          )
          (pkgs.writeShellScriptBin "register_moderator_user" ''
            exec ${pkgs.matrix-synapse}/bin/register_new_matrix_user \
              -u moderator \
              -p moderator-password \
              --no-admin \
              --shared-secret supersecret-registration \
              http://localhost:8448
          ''
          )
        ];
      };

      draupnir = { ... }: {
        services.draupnir = {
          enable = true;
          accessTokenFile = "/tmp/draupnir-access-token";
          settings = {
            homeserverUrl = "http://homeserver:8448";
            managementRoom = "#moderators:homeserver";
          };
        };
        environment.systemPackages = [
          (pkgs.writeShellScriptBin "get_draupnir_access_token" ''
            exec ${pkgs.curl}/bin/curl \
              -X POST -s \
              -d '{"type":"m.login.password", "user":"draupnir", "password":"draupnir-password"}' \
              http://homeserver:8448/_matrix/client/v3/login \
              | ${pkgs.jq}/bin/jq --join-output '.access_token' \
              > /tmp/draupnir-access-token
          ''
          )
        ];
      };

      draupnirpantalaimon = { pkgs, ... }: {
        services.draupnir = {
          enable = true;
          pantalaimon = {
            enable = true;
            username = "draupnir";
            passwordFile = pkgs.writeText "password.txt" "draupnir-password";
            options = {
              # otherwise draupnir tries to connect to ::1, which is not listened by pantalaimon
              listenAddress = "127.0.0.1";
              homeserver = "http://homeserver:8448";
            };
          };
          settings = {
            managementRoom = "#moderators-encrypted:homeserver";
          };
        };
      };

      client = { pkgs, ... }: {
        environment.systemPackages = [
          (pkgs.writers.writePython3Bin "create_management_rooms_and_invite_draupnir"
            { libraries = with pkgs.python3Packages; [
                matrix-nio
              ] ++ matrix-nio.optional-dependencies.e2e;
            } ''
            import asyncio

            from nio import (
                AsyncClient,
                EnableEncryptionBuilder
            )


            async def main() -> None:
                client = AsyncClient("http://homeserver:8448", "moderator")

                await client.login("moderator-password")

                room = await client.room_create(
                    name="Moderators",
                    alias="moderators",
                )

                encrypted_room = await client.room_create(
                    name="Moderators-encrypted",
                    alias="moderators-encrypted",
                    initial_state=[EnableEncryptionBuilder().as_dict()],
                )

                await client.join(room.room_id)
                await client.room_invite(room.room_id, "@draupnir:homeserver")

                await client.join(encrypted_room.room_id)
                await client.room_invite(encrypted_room.room_id, "@draupnir:homeserver")

            asyncio.run(main())
          ''
          )
        ];
      };
    };

    testScript = ''
      with subtest("start homeserver"):
        homeserver.start()

        homeserver.wait_for_unit("matrix-synapse.service")
        homeserver.wait_until_succeeds("curl --fail -L http://localhost:8448/")

      with subtest("register users"):
        # register draupnir user
        homeserver.succeed("register_draupnir_user")
        # register moderator user
        homeserver.succeed("register_moderator_user")

      with subtest("start draupnir"):
        draupnir.start()

        draupnir.wait_until_succeeds("curl --fail -L http://homeserver:8448/")

        draupnir.succeed("get_draupnir_access_token")

        draupnir.wait_for_unit("draupnir.service")

      with subtest("ensure draupnir can be invited to the management rooms"):
        client.start()

        client.wait_until_succeeds("curl --fail -L http://homeserver:8448/")

        client.succeed("create_management_rooms_and_invite_draupnir")

        draupnir.wait_for_console_text("Startup complete. Now monitoring rooms")

      with subtest("start draupnirpantalaimon"):
        draupnirpantalaimon.start()

        # wait for pantalaimon to be ready
        draupnirpantalaimon.wait_for_unit("pantalaimon-draupnir.service")
        draupnirpantalaimon.wait_for_unit("draupnir.service")

        draupnirpantalaimon.wait_until_succeeds("curl --fail -L http://localhost:8009/")

      with subtest("ensure draupnir can be invited to the encrypted management room"):

        draupnirpantalaimon.wait_for_console_text("Startup complete. Now monitoring rooms")
    '';
  }
)
