{
  sops = {
    defaultSopsFormat = "yaml";
    defaultSopsFile = ./configuration/secrets-encrypted.yaml;
    validateSopsFiles = false; 
    age.keyFile = "/root/.config/sops/age/keys.txt"; 
  };
}