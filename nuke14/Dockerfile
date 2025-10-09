FROM rockylinux:8

# Install required packages including ffmpeg
RUN dnf update -y && \
    dnf install -y epel-release && \
    dnf config-manager --set-enabled powertools && \
    dnf install -y \
    tar \
    gzip \
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
COPY nuke14/Nuke14.1v8-linux-x86_64.tgz /tmp/

# Extract and install Nuke
RUN cd /tmp && \
    tar -xzf Nuke14.1v8-linux-x86_64.tgz && \
    chmod +x Nuke14.1v8-linux-x86_64.run && \
    printf "y\ny\n" | ./Nuke14.1v8-linux-x86_64.run --mode unattended --prefix /opt/nuke && \
    ls -la /tmp && \
    find /tmp -name "*Nuke*" && \
    cp -r /tmp/Nuke14.1v8/* /opt/nuke/ && \
    chown -R nuke:nuke /opt/nuke && \
    rm -rf /tmp/Nuke14.1v8 /tmp/Nuke14.1v8-linux-x86_64.tgz /tmp/Nuke14.1v8-linux-x86_64.run

# Create samples directory
RUN mkdir -p /samples && chown nuke:nuke /samples

# Copy sample files to the container
COPY nuke14/testjob-nuke/SimpleNuke-16.0.nk /samples/SimpleNuke-16.nk
COPY nuke14/testjob-nuke/simple-16.0.png /samples/simple-16.png
COPY nuke14/motionblur2d_10.nk /samples/motionblur2d_10.nk
COPY nuke14/render_script.py /samples/render_script.py

# Set ownership of sample files
RUN chown -R nuke:nuke /samples

# Set environment variables
ENV NUKE_PATH=/opt/nuke
ENV PATH=$NUKE_PATH:$PATH

# Switch to nuke user
USER nuke

# Set default command
CMD ["/opt/nuke/Nuke14.1", "--help"]