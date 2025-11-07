FROM rockylinux:8

# Install required packages including ffmpeg
RUN dnf update -y && \
    dnf install -y epel-release && \
    dnf config-manager --set-enabled powertools && \
    dnf install -y \
    tar \
    gzip \
    unzip \
    which \
    findutils \
    libX11 \
    libXext \
    libXrender \
    libXrandr \
    libXinerama \
    libXcursor \
    libXi \
    libXScrnSaver \
    libXv \
    libXtst \
    libXdamage \
    libXfixes \
    libXcomposite \
    libSM \
    libICE \
    libGL \
    libGLU \
    mesa-libGL \
    mesa-libGLU \
    fontconfig \
    freetype \
    alsa-lib \
    && dnf install -y --nogpgcheck https://download1.rpmfusion.org/free/el/rpmfusion-free-release-8.noarch.rpm \
    && dnf install -y ffmpeg \
    && dnf clean all

# Create nuke user and group
RUN groupadd -r nuke && useradd -r -g nuke -d /opt/nuke -s /bin/bash nuke

# Set working directory
WORKDIR /opt/nuke

# Copy Nuke installer
COPY Nuke14.1v8-linux-x86_64.tgz /tmp/

# Extract and install Nuke
RUN cd /tmp && \
    tar -xzf Nuke14.1v8-linux-x86_64.tgz && \
    chmod +x Nuke14.1v8-linux-x86_64.run && \
    printf "y\ny\n" | ./Nuke14.1v8-linux-x86_64.run --mode unattended --prefix /opt/nuke && \
    ls -la /tmp && \
    find /tmp -name "*Nuke*" && \
    cp -r /tmp/Nuke14.1v8/* /opt/nuke/ && \
    chown -R nuke:nuke /opt/nuke && \
    rm -rf /tmp/Nuke14.1v8 /tmp/Nuke14.1v8-linux-x86_64.tgz /tmp/Nuke14.1v8-linux-x86_64.run && \
    ln -s /opt/nuke/Nuke14.1 /opt/nuke/Nuke

# Create samples directory
RUN mkdir -p /samples && chown nuke:nuke /samples

# Copy sample files to the container
COPY testjob-nuke/SimpleNuke-16.0.nk /samples/SimpleNuke-16.nk
COPY testjob-nuke/simple-16.0.png /samples/simple-16.png
COPY motionblur2d_10.nk /samples/motionblur2d_10.nk
COPY render_script.py /samples/render_script.py

# Set ownership of sample files
RUN chown -R nuke:nuke /samples

# Copy plugin installers
COPY keentools-2025.2.0-for-nuke-14.1-linux.zip /tmp/
COPY NeatVideo6OFX.Demo.Intel64.tgz /tmp/
COPY RSMB6OFXInstaller.tar.gz /tmp/

# Extract plugin installers
RUN cd /tmp && \
    unzip -q keentools-2025.2.0-for-nuke-14.1-linux.zip && \
    tar -xzf NeatVideo6OFX.Demo.Intel64.tgz && \
    tar -xzf RSMB6OFXInstaller.tar.gz

# Create Nuke plugins directories
RUN mkdir -p /usr/local/NUKE/14.1/plugins /usr/OFX/Nuke

# Install KeenTools (manual extraction due to checksum issues)
RUN cd /tmp && \
    chmod +x "KeenTools - Nuke 14.1.sh" && \
    ("./KeenTools - Nuke 14.1.sh" --noexec --target /tmp/keentools_extract || true) && \
    if [ -d "/tmp/keentools_extract" ]; then \
        cp -r /tmp/keentools_extract/* /usr/local/NUKE/14.1/plugins/ || \
        (mkdir -p /usr/local/NUKE/14.1/plugins/KeenTools && \
         cp -r /tmp/manual/KeenTools/* /usr/local/NUKE/14.1/plugins/KeenTools/); \
    fi

# Install NeatVideo (skip if fails)
RUN cd /tmp && \
    chmod +x NeatVideo6OFX.Demo.Intel64/NeatVideo6OFX.Demo.Intel64.run && \
    (./NeatVideo6OFX.Demo.Intel64/NeatVideo6OFX.Demo.Intel64.run --mode silent || \
     echo "NeatVideo installation failed - continuing without it")

# Install RSMB silently
RUN cd /tmp && \
    chmod +x RSMB6OFX-6.6.2-linux-x64-installer.run && \
    ./RSMB6OFX-6.6.2-linux-x64-installer.run --mode unattended

# Clean up installation files
RUN rm -rf /tmp/keentools-2025.2.0-for-nuke-14.1-linux.zip \
           /tmp/NeatVideo6OFX.Demo.Intel64.tgz \
           /tmp/RSMB6OFXInstaller.tar.gz \
           /tmp/KeenTools* \
           /tmp/NeatVideo6OFX.Demo.Intel64 \
           /tmp/RSMB6OFX* \
           /tmp/manual \
           /tmp/keentools_extract

# Set environment variables
ENV NUKE_PATH=/opt/nuke
ENV PATH=$NUKE_PATH:$PATH

# Switch to nuke user
USER nuke

# Set default command
CMD ["/opt/nuke/Nuke14.1", "--help"]