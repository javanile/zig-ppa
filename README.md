


```shell
curl -SsL https://javanile.org/zig-ppa/ubuntu/key.gpg | sudo apt-key add -
sudo curl -SsL -o /etc/apt/sources.list.d/zig.list https://javanile.org/zig-ppa/ubuntu/sources.list
sudo apt update
sudo apt install zig
```