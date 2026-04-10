## Linux

tar -xzf ssh_flutter_linux_x64.tar.gz
cd bundle
./ssh_flutter

## Windows

Copiar la clau a "C:\Users\NOM_USUARI\.ssh\id_rsa" o bé "$env:USERPROFILE\.ssh\id_rsa"
Després:

$key = "$env:USERPROFILE\.ssh\id_rsa"
$user = "$env:USERDOMAIN\$env:USERNAME"
icacls $key
icacls $key /inheritance:r
icacls $key /remove:g "Users" "Authenticated Users" "Everyone" "CodexSandboxUsers" "DESKTOP-T0AUJI\CodexSandboxUsers"
icacls $key /grant:r "${user}:R"
icacls $key

Configurar la clau de l'aplicació com "C:\Users\NOM_USUARI\.ssh\id_rsa" on NOM_USUARI és el nom de l'usuari
