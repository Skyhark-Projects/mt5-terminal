FROM ubuntu:bionic

# https://github.com/solarkennedy/wine-x11-novnc-docker

ENV HOME /root
ENV DEBIAN_FRONTEND noninteractive
ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

RUN apt-get update && apt-get -y install xvfb x11vnc python-pip xdotool wget tar supervisor net-tools fluxbox cabextract software-properties-common winetricks && \
    dpkg --add-architecture i386 && \
    apt-get install -y gnupg2 && \
    wget -nc https://dl.winehq.org/wine-builds/winehq.key && \
    apt-key add winehq.key && \
    apt-add-repository 'deb https://dl.winehq.org/wine-builds/ubuntu/ bionic main' && \
    apt-get -y install wine64-development net-tools fluxbox cabextract && \
    apt install -y --install-recommends winehq-stable && \
    pip install -U Flask pytz

#pip install MetaTrader5

ENV WINEPREFIX /root/prefix64
ENV WINEARCH win64
ENV DISPLAY :0

WORKDIR /root/
RUN wget -O - https://github.com/novnc/noVNC/archive/v1.1.0.tar.gz | tar -xzv -C /root/ && mv /root/noVNC-1.1.0 /root/novnc && ln -s /root/novnc/vnc_lite.html /root/novnc/index.html && \
    wget -O - https://github.com/novnc/websockify/archive/v0.8.0.tar.gz | tar -xzv -C /root/ && mv /root/websockify-0.8.0 /root/novnc/utils/websockify

ADD ./mt5 /root/mt5
ADD src /tmp/src
RUN mv /tmp/src/server.py /root/server.py && \
    mv /tmp/src/start.sh /usr/bin/start.sh && \
    mv /tmp/src/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 8080

CMD ["/usr/bin/supervisord"]