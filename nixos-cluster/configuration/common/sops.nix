{
  sops = {
    defaultSopsFormat = "yaml";
    defaultSopsFile = "/root/forge/nixos-cluster/configuration/secrets-encrypted.yaml";
    age.keyFile = "/root/.config/sops/age/keys.txt";
  };
}