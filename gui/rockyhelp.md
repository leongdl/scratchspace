Building a Rocky Linux 9 container with a full GUI (like XFCE or GNOME) requires two main components: the Desktop Environment (DE) and a Remote Access tool (like VNC or noVNC), since containers don't have a physical monitor.

Below is a guide and a sample Dockerfile to get a full XFCE desktop running on Rocky Linux 9.

Dockerfile for Rocky Linux 9 + XFCE + VNC
XFCE is recommended over GNOME for containers because it is lightweight and performs much better over remote connections.

Dockerfile

# Use official Rocky Linux 9 image
FROM rockylinux:9

# Install EPEL (required for XFCE) and common tools
RUN dnf install -y epel-release && \
    dnf update -y && \
    dnf groupinstall -y "Xfce" "base-x" && \
    dnf install -y tigervnc-server xterm novnc python3-websockify procps-ng && \
    dnf clean all

# Set up a user for the VNC session
RUN useradd -m -s /bin/bash rockyuser
USER rockyuser
WORKDIR /home/rockyuser

# Initialize VNC password (set to 'password' for this example)
RUN mkdir -p /home/rockyuser/.vnc && \
    echo "password" | vncpasswd -f > /home/rockyuser/.vnc/passwd && \
    chmod 600 /home/rockyuser/.vnc/passwd

# Set XFCE as the default session
RUN echo "startxfce4 &" > /home/rockyuser/.vnc/xstartup && \
    chmod +x /home/rockyuser/.vnc/xstartup

# Expose VNC (5901) and noVNC web port (6080)
EXPOSE 5901 6080

# Start VNC and noVNC (web access)
CMD vncserver :1 -geometry 1280x800 -depth 24 && \
    /usr/share/novnc/utils/novnc_proxy --vnc localhost:5901 --listen 6080
How to Build and Run
Build the image:

Bash

docker build -t rocky9-desktop .
Run the container:

Bash

docker run -d -p 6080:6080 --name rocky-gui rocky9-desktop
Access the Desktop: Open your web browser and go to http://localhost:6080/vnc.html. Click Connect and enter the password (password).

Key Resources & Links
Official Rocky Linux Documentation: XFCE Installation Guide — Useful for seeing which groups and packages Rocky requires for a GUI.

Docker Headless VNC (GitHub): ConSol/docker-headless-vnc-container — A robust repository showing how to build professional-grade Rocky/CentOS GUI containers.

TigerVNC Project: TigerVNC Official Site — Documentation on the VNC server used to bridge the container to your screen.