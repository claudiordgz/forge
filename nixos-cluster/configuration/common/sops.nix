{
  sops = {
    defaultSopsFormat = "yaml";
    defaultSopsFile = ../secrets-encrypted.yaml;
    validateSopsFiles = false; 
    age.keyFile = "/root/.config/sops/age/keys.txt"; 
  };
}