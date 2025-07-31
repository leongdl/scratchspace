FROM mottosso/mayabase-rocky8:2023

MAINTAINER konstruktion@gmail.com

# Download and unpack distribution first, Docker's caching
# mechanism will ensure that this only happens once.
RUN wget https://efulfillment.autodesk.com/NetSWDLD/2025/MAYA/1AAEB4DA-FE7D-3C8A-A4F4-C217F55C55BA/ESD/Autodesk_Maya_2025_Linux_64bit.tgz -O maya.tgz && \
    mkdir /maya && tar -xvf maya.tgz -C /maya && \
    rm maya.tgz && \
    rpm -Uvh /maya/Packages/Maya*.rpm && \
    rm -r /maya

# Make mayapy the default Python
RUN echo alias hpython="\"/usr/autodesk/maya/bin/mayapy\"" >> ~/.bashrc && \
    echo alias hpip="\"mayapy -m pip\"" >> ~/.bashrc

# Setup environment
ENV MAYA_LOCATION=/usr/autodesk/maya/
ENV PATH=$MAYA_LOCATION/bin:$PATH

# Avoid warning about this variable not set, the path is its default value
RUN mkdir /var/tmp/runtime-root && \
    chmod 0700 /var/tmp/runtime-root
ENV XDG_RUNTIME_DIR=/var/tmp/runtime-root

# Workaround for "Segmentation fault (core dumped)"
# See https://forums.autodesk.com/t5/maya-general/render-crash-on-linux/m-p/5608552/highlight/true
ENV MAYA_DISABLE_CIP=1

# Copy and install Redshift
COPY redshift_2025.5.0_1853528846_linux_x64.run /tmp/redshift_installer.run
COPY redshift.ma /tmp/redshift.ma
RUN chmod +x /tmp/redshift_installer.run && \
    /tmp/redshift_installer.run --accept --quiet --nox11 && \
    rm /tmp/redshift_installer.run

# Setup Redshift for Maya 2025
RUN mkdir -p /root/maya/modules && \
    mkdir -p /root/maya/2025 && \
    mkdir -p /root/redshift

# Create Redshift module file for Maya 2025
RUN echo "+ MAYAVERSION:2025 redshift4maya any /usr/redshift/redshift4maya" > /root/maya/modules/redshift4maya.mod && \
    echo "scripts: common/scripts" >> /root/maya/modules/redshift4maya.mod && \
    echo "icons: common/icons" >> /root/maya/modules/redshift4maya.mod && \
    echo "plug-ins: 2025" >> /root/maya/modules/redshift4maya.mod && \
    echo "REDSHIFT_COREDATAPATH = /usr/redshift" >> /root/maya/modules/redshift4maya.mod && \
    echo "MAYA_CUSTOM_TEMPLATE_PATH +:= common/scripts/NETemplates" >> /root/maya/modules/redshift4maya.mod && \
    echo "MAYA_RENDER_DESC_PATH +:= common/rendererDesc" >> /root/maya/modules/redshift4maya.mod && \
    echo "REDSHIFT_MAYAEXTENSIONSPATH +:= 2025/extensions" >> /root/maya/modules/redshift4maya.mod && \
    echo "REDSHIFT_PROCEDURALSPATH += \$REDSHIFT_COREDATAPATH/procedurals/usd/USD_24.08" >> /root/maya/modules/redshift4maya.mod && \
    echo "REDSHIFT_PROCEDURALSPATH += \$REDSHIFT_COREDATAPATH/procedurals/alembic" >> /root/maya/modules/redshift4maya.mod

# Copy redshiftRenderer.xml for command-line rendering
RUN cp /usr/redshift/redshift4maya/common/rendererDesc/redshiftRenderer.xml /usr/autodesk/maya/bin/rendererDesc/

# Set Redshift environment variables
ENV REDSHIFT_COREDATAPATH=/usr/redshift
ENV REDSHIFT_LOCALDATAPATH=/root/redshift

# Copy and install Ornatrix Maya 2025
COPY Ornatrix_Maya_2025_Demonstration_5.1.2.36369.run /tmp/ornatrix_installer.run
RUN chmod +x /tmp/ornatrix_installer.run && \
    /tmp/ornatrix_installer.run --quiet --nox11 && \
    rm /tmp/ornatrix_installer.run

# Copy and install SpeedTree Modeler
COPY SpeedTree_Modeler_v10.0.1_Linux.tar.gz /tmp/speedtree.tar.gz
RUN cd /tmp && \
    tar -xzf speedtree.tar.gz && \
    rm speedtree.tar.gz && \
    mkdir -p /opt/SpeedTree && \
    mv /tmp/SpeedTree_Modeler_v10.0.1_Linux/SpeedTree_Modeler_v10.0.1 /opt/SpeedTree/ && \
    cd /opt/SpeedTree/SpeedTree_Modeler_v10.0.1 && \
    chmod +x installSpeedTreeModeler.sh && \
    ./installSpeedTreeModeler.sh -s && \
    rm -rf /tmp/SpeedTree_Modeler_v10.0.1_Linux

# Install xcb dependencies for SpeedTree
RUN yum install -y libxcb xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm

# Set SpeedTree environment variables
ENV SPEEDTREE_HOME=/opt/SpeedTree/SpeedTree_Modeler_v10.0.1
ENV PATH=$SPEEDTREE_HOME:$PATH

# Copy and install MtoA (Arnold for Maya)
COPY MtoA-5.4.4-linux-2025.run /tmp/mtoa_installer.run
RUN chmod +x /tmp/mtoa_installer.run && \
    echo -e "accept\n1\n" | /tmp/mtoa_installer.run --nox11 && \
    rm /tmp/mtoa_installer.run

# Set Arnold environment variables
ENV ARNOLD_LOCATION=/usr/autodesk/arnold/mtoa/2025
ENV PATH=$ARNOLD_LOCATION/bin:$PATH
ENV MAYA_MODULE_PATH=$MAYA_MODULE_PATH:/usr/autodesk/modules/maya/2025
ENV MAYA_RENDER_DESC_PATH=$MAYA_RENDER_DESC_PATH:/usr/autodesk/arnold/mtoa/2025

# Copy and install V-Ray for Maya 2025
COPY vray_adv_71000_maya2025_rhel8 /tmp/vray_installer
COPY vray.ma /tmp/vray.ma
COPY vray-config.xml /tmp/vray-config.xml
#RUN chmod +x /tmp/vray_installer && \
#    /tmp/vray_installer -gui=0 -configFile="/tmp/vray-config.xml" -ignoreErrors=1 && \
#    rm /tmp/vray_installer

# Setup V-Ray for Maya 2025
RUN mkdir -p /opt/vray_builds/vray_71000_maya2025

# Set V-Ray environment variables
ENV MAYA_MODULE_PATH=$MAYA_MODULE_PATH:/usr/autodesk/vray4maya2025/maya_root/modules
ENV VRAY_FOR_MAYA2025_PLUGINS=/usr/autodesk/vray4maya2025/maya_vray/vrayplugins
ENV VRAY_OSL_PATH=/usr/autodesk/vray4maya2025/vray/opensl
ENV PATH=$PATH:/usr/autodesk/vray4maya2025/vray/bin

# Cleanup
WORKDIR /root
