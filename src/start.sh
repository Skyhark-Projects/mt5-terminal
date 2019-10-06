sed -i "s/Login\=$/Login=$login/g" /root/mt5/Config/common.ini
sed -i "s/Password\=$/Password=$password/g" /root/mt5/Config/common.ini
sed -i "s/Server\=$/Server=$server/g" /root/mt5/Config/common.ini
WINEDLLOVERRIDES="mscoree,mshtml=" /usr/bin/wine /root/mt5/terminal64.exe /config:Z:\\root\\mt5\\Config\\common.ini