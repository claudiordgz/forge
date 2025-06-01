{ config, lib, pkgs, ... }:

let
  host = config.networking.hostName;
in
{
  sops.secrets."sshKeys/${host}/adminuser" = {};

  users.users.root.openssh.authorizedKeys.keys = [
    config.sops.secrets."sshKeys/${host}/adminuser".path
  ];
}