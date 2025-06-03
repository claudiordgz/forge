{
  sops = {
    defaultSopsFormat = "yaml";
    defaultSopsFile = ../secrets-encrypted.yaml;
    validateSopsFiles = false; 
    age.keyFile = "/home/admin/.config/sops/age/keys.txt"; 
  };
}