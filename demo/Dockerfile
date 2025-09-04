# Build and tag this container as: houdini-rdman:latest
# Example: docker build -t houdini-rdman:latest -f Dockerfile.houdini-rdman-rocky .
# Run with: docker run --rm -it houdini-rdman:latest

FROM rockylinux:9

# Set locale
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LC_NUMERIC=en_US.UTF-8

# Note: Docker container stack size must be set at runtime with --ulimit stack=<size>:<size>
# We'll set a more modest increase in the scripts themselves

# Add metadata
LABEL maintainer="David Leong"
LABEL description="Houdini with RenderMan Docker container based on Rocky Linux 9"

# Create installation directories
RUN mkdir -p /install /install/houdini

# Install all dependencies in one layer to reduce build time
# Including the missing X11/XCB libraries that were causing DSO issues
RUN dnf install -y dnf-plugins-core && \
    dnf config-manager --set-enabled devel && \
    dnf install -y unzip tar gzip bzip2 which \
    libSM libICE libXt libXcomposite libXdamage libXfixes libXext libXrender libXi \
    libXtst libXau libxcb libXinerama libXrandr libXcursor libXScrnSaver \
    alsa-lib mesa-libGL mesa-libGLU bc python3 \
    nss nspr pciutils sudo \
    mesa-dri-drivers fontconfig \
    glibc-langpack-en gtk3 ncurses-libs libxcrypt-compat ncurses-compat-libs \
    qt5-qtbase-gui qt5-qtx11extras xorg-x11-server-Xvfb \
    libglvnd-glx libglvnd-opengl libxshmfence libXdmcp \
    libxkbcommon libxkbcommon-x11 \
    xcb-util-wm xcb-util-image xcb-util-keysyms xcb-util-renderutil \
    xcb-util \
    python3-pip && \
    pip3 install future lxml requests && \
    dnf clean all

# Create csh symlink for hrender (which requires csh)
RUN ln -s /bin/bash /bin/csh

# Copy Houdini and RenderMan files into the container
COPY houdini-20.0.896-linux_x86_64_gcc11.2.tar.gz /install/
COPY RenderManForHoudini-26.3_2352169-linuxRHEL9_gcc11icx232.x86_64.rpm /install/
COPY RenderManProServer-26.3_2352291-linuxRHEL9_gcc11icx232.x86_64.rpm /install/

#######################################
# Houdini Installation Section
#######################################

# Extract and install Houdini, then cleanup in single layer
RUN tar -xzf /install/houdini-20.0.896-linux_x86_64_gcc11.2.tar.gz -C /install/houdini && \
    cd /install/houdini/houdini-20.0.896-linux_x86_64_gcc11.2 && \
    ./houdini.install \
    --auto-install \
    --accept-EULA 2021-10-13 \
    --no-install-engine-maya \
    --no-install-engine-unity \
    --no-install-menus \
    --no-install-bin-symlink \
    --no-install-hfs-symlink \
    --no-install-license \
    --no-install-hqueue-server \
    --no-root-check \
    --make-dir /opt/houdini && \
    rm -rf /install/houdini-20.0.896-linux_x86_64_gcc11.2.tar.gz /install/houdini

# Set up Houdini environment
ENV HFS=/opt/houdini
ENV H=/opt/houdini
ENV HB=/opt/houdini/bin
ENV HDSO=/opt/houdini/dsolib
ENV HD=/opt/houdini/demo
ENV HH=/opt/houdini/houdini
ENV HHC=/opt/houdini/config
ENV HT=/opt/houdini/toolkit
ENV HSB=/opt/houdini/sbin
ENV TEMP=/tmp
ENV PATH=$HB:$HSB:$PATH
ENV LD_LIBRARY_PATH=/opt/houdini/dsolib
ENV HOUDINI_MAJOR_RELEASE=20
ENV HOUDINI_MINOR_RELEASE=0
ENV HOUDINI_BUILD_VERSION=896
ENV HOUDINI_VERSION=$HOUDINI_MAJOR_RELEASE.$HOUDINI_MINOR_RELEASE.$HOUDINI_BUILD_VERSION

# Configure Houdini DSO error handling (set to 0 for permissive RenderMan ROP operations)
RUN mkdir -p /opt/houdini/houdini/config && \
    echo 'HOUDINI_DSO_ERROR = 0' > /opt/houdini/houdini/config/houdini.env

#######################################
# RenderMan for Houdini Installation Section
#######################################

# Install RenderMan for Houdini from RPM
RUN rpm -ivh /install/RenderManForHoudini-26.3_2352169-linuxRHEL9_gcc11icx232.x86_64.rpm

#######################################
# RenderMan ProServer Installation Section
#######################################

# Install RenderMan ProServer from RPM
RUN ls -la /install/RenderManProServer* && \
    rpm -ivh --verbose /install/RenderManProServer-26.3_2352291-linuxRHEL9_gcc11icx232.x86_64.rpm || \
    (echo "RPM installation failed, checking dependencies:" && \
     rpm -qpR /install/RenderManProServer-26.3_2352291-linuxRHEL9_gcc11icx232.x86_64.rpm)

# Set up RenderMan environment variables
ENV RMANTREE=/opt/pixar/RenderManProServer-26.3
ENV RFHTREE=/opt/pixar/RenderManForHoudini-26.3
ENV RMAN_PROCEDURALPATH=/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/openvdb

# Update Houdini path to include RenderMan for Houdini
ENV HOUDINI_PATH=/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896:/opt/houdini

# Create Houdini package configuration for RenderMan
RUN mkdir -p /opt/houdini/packages && \
    echo '{\
    "env": [\
        {\
            "RMANTREE": "/opt/pixar/RenderManProServer-26.3"\
        },\
        {\
            "RFHTREE": "/opt/pixar/RenderManForHoudini-26.3"\
        },\
        {\
            "RMAN_PROCEDURALPATH": "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896/openvdb"\
        },\
        {\
            "OCIO": "${RMANTREE}/lib/ocio/ACES-1.3/config.ocio"\
        }\
    ],\
    "path": "/opt/pixar/RenderManForHoudini-26.3/3.10/20.0.896"\
}' > /opt/houdini/packages/renderman.json

# Create render directory for asset files
RUN mkdir -p /render

# Copy test scene file
COPY RMAN_test_02.hip /render/