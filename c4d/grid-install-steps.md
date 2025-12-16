# NVIDIA GRID Driver Installation Steps (Amazon Linux 2023)

## Prerequisites
These were already installed on the system:
- gcc
- make  
- kernel-devel
- kernel-modules-extra

## Step 1: Install Build Dependencies (if needed)
```bash
sudo dnf install -y gcc make
```

## Step 2: Install Kernel Headers (if needed)
```bash
sudo dnf install -y kernel-devel kernel-modules-extra
```

## Step 3: Download NVIDIA GRID Driver from S3
```bash
aws s3 cp --recursive s3://ec2-linux-nvidia-drivers/latest/ /tmp/nvidia-driver/
```

Driver downloaded: `NVIDIA-Linux-x86_64-580.105.08-grid-aws.run`

## Step 4: Set Execute Permissions
```bash
chmod +x /tmp/nvidia-driver/NVIDIA-Linux-x86_64*.run
```

## Step 5: Install the Driver
```bash
sudo /bin/sh /tmp/nvidia-driver/NVIDIA-Linux-x86_64-580.105.08-grid-aws.run --silent
```

## Step 6: Disable GSP (Required for G4dn, G5, G5g with vGPU 14.x+)
```bash
sudo touch /etc/modprobe.d/nvidia.conf
echo "options nvidia NVreg_EnableGpuFirmware=0" | sudo tee --append /etc/modprobe.d/nvidia.conf
```

## Step 7: Reboot (Manual)
```bash
sudo reboot
```

## Verification (After Reboot)
```bash
nvidia-smi -q | head
```

## Notes
- Completed on: 2025-12-16
- Driver version: 580.105.08
- Warnings about X library path and Vulkan ICD loader are expected for headless rendering
- Reboot required to load the driver
