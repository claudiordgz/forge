{
  sops = {
    defaultSopsFormat = "yaml";
    defaultSopsFile = ../secrets-encrypted.yaml;
    validateSopsFiles = false; 
    age.keyFile = "/home/.config/sops/age/keys.txt"; 
  };
}