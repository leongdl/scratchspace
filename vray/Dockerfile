FROM rockylinux:9

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LC_NUMERIC=en_US.UTF-8

RUN mkdir -p /install /opt/vray

RUN dnf install -y unzip tar gzip bzip2 which libX11 libXext libXrender libXrandr \
    libXfixes libXcursor libXinerama libXi glibc-langpack-en gtk3 mesa-libGL \
    mesa-libGLU libglvnd-glx libglvnd-opengl bc tcsh python3.11 nss nspr \
    pciutils sudo qt5-qtbase-gui qt5-qtx11extras xorg-x11-server-Xvfb \
    mesa-dri-drivers libXcomposite libXdamage libXtst libXScrnSaver \
    libxshmfence alsa-lib python3-pip

RUN pip3 install future lxml requests

COPY vraystd_adv_71000_rhel8_clang-gcc-11.2 /install/

RUN chmod +x /install/vraystd_adv_71000_rhel8_clang-gcc-11.2 && \
    /install/vraystd_adv_71000_rhel8_clang-gcc-11.2 -unpackInstall=/opt/vray

ENV PATH=/opt/vray/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/vray/lib:$LD_LIBRARY_PATH
ENV QT_QPA_PLATFORM=offscreen

RUN mkdir -p /render

RUN rm -rf /install

WORKDIR /render