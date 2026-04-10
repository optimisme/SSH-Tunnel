## Linux

cd build/linux/x64/release/
tar -czf ssh_flutter_linux_x64.tar.gz bundle
mv ssh_flutter_linux_x64.tar.gz ../../../../../Releases
cd ../../../../

## Windows

Compress-Archive `
    -Path .\build\windows\x64\runner\Release\* `
    -DestinationPath ..\Releases\ssh_flutter_windows_x64.zip `
    -Force