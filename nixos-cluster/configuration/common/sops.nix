{
  sops = {
    defaultSopsFormat = "yaml";
    defaultSopsFile = "/root/forge/nixos-cluster/secrets-encrypted.yaml";
    age.keyFile = "/root/.config/sops/age/keys.txt";
  };
}