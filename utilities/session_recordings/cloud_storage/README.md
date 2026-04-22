# Session Log Converter Service

## Overview

This script watches for new OPA session logs and converts them to asciinema (SSH) or MKV (RDP) format, saving to a mounted cloud storage bucket. It is intended to run as a Linux systemd service.

**_This script is not supported by Okta, is experimental, and is not intended for production use. No warranty is expressed or implied. Please review and understand all scripts before using. Use at your own risk._**

## Capabilities

- Watches `/var/log/sft/sessions` for new session recordings using inotifywait
- Automatically detects SSH vs RDP sessions based on filename
- Converts SSH sessions to asciinema `.cast` format for terminal playback
- Converts RDP sessions to `.mkv` video format
- Optionally copies raw source files instead of converting
- Automatic cleanup of source files based on configurable retention period
- Supports AWS S3, Google Cloud Storage, and Azure Blob Storage destinations

## Prerequisites

- `inotify-tools` package installed
- `sft` CLI installed and configured
- Cloud storage bucket mounted locally (see below)
- OPA Gateway configured to include protocol in log filenames (see below)

### Gateway Configuration

The script determines recording type (SSH vs RDP) based on the filename. Configure the OPA Gateway to include the protocol in log filenames by adding the following to `/etc/sft/sft-gatewayd.yaml`:

```yaml
LogFileNameFormats:
  SSHRecording: "{{.Protocol}}~{{.StartTime}}~{{.TeamName}}~{{.ProjectName}}~{{.ServerName}}~{{.Username}}~"
  RDPRecording: "{{.Protocol}}~{{.StartTime}}~{{.TeamName}}~{{.ProjectName}}~{{.ServerName}}~{{.Username}}~"
```

Restart the gateway service to apply changes:

```bash
sudo systemctl restart sft-gatewayd
```

## Installation

1. Download and install the script to `/etc/sft/`:
   ```bash
   curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/utilities/session_recordings/cloud_storage/cloud_sessionlogs.sh
   sudo mv cloud_sessionlogs.sh /etc/sft/cloud_sessionlogs.sh
   sudo chown root:root /etc/sft/cloud_sessionlogs.sh
   sudo chmod +x /etc/sft/cloud_sessionlogs.sh
   ```

2. Create the systemd service file at `/etc/systemd/system/opa-session-log-handler.service`:
   ```ini
   [Unit]
   Description=Watch for new OPA session logs and convert them
   After=network-online.target
   Wants=network-online.target

   [Service]
   Type=simple
   ExecStart=/etc/sft/cloud_sessionlogs.sh
   Restart=always
   RestartSec=5s
   Environment="WATCHPATH=/var/log/sft/sessions"
   Environment="DESTPATH=/mnt/cloud/sessions"
   Environment="SSH_MODE=convert"
   Environment="RDP_MODE=convert"
   Environment="RETENTION_DAYS=30"
   Environment="CLEANUP_INTERVAL=3600"

   [Install]
   WantedBy=multi-user.target
   ```

3. Enable and start the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable opa-session-log-handler
   sudo systemctl start opa-session-log-handler
   ```

4. Check status:
   ```bash
   sudo systemctl status opa-session-log-handler
   sudo journalctl -u opa-session-log-handler -f
   ```

## Mounting Cloud Storage

Choose one of the following options to mount cloud storage as a local filesystem.

### AWS S3 (using s3fs)

1. Install s3fs:
   ```bash
   sudo apt-get install s3fs
   ```

2. Create mount point:
   ```bash
   sudo mkdir -p /mnt/cloud/sessions
   ```

3. Configure authentication (choose one):

   **Option A: EC2 Instance Profile (recommended for EC2 instances)**
   
   Attach an IAM role to your EC2 instance with S3 access permissions. No additional configuration needed - s3fs will automatically use the instance metadata service.
   
   ```bash
   sudo s3fs {bucket-name} /mnt/cloud/sessions \
       -o allow_other \
       -o iam_role={iam-role-name} \
       -o endpoint={region} \
       -o url="https://s3-{region}.amazonaws.com"
   ```
   
   Replace:
   - `{iam-role-name}` - Name of the IAM role attached to the instance
   - `{region}` - Your bucket's region (e.g., `us-west-2`)
   - `{bucket-name}` - Your S3 bucket name
   
   For persistent mount, add to `/etc/fstab`:
   ```
   {bucket-name} /mnt/cloud/sessions fuse.s3fs _netdev,allow_other,iam_role={iam-role-name},endpoint={region},url=https://s3-{region}.amazonaws.com 0 0
   ```

   **Option B: IAM Roles Anywhere (recommended for non-AWS environments)**
   
   [IAM Roles Anywhere](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html) allows workloads outside of AWS to use X.509 certificates to obtain temporary credentials.
   
   1. Set up a trust anchor and profile in IAM Roles Anywhere
   2. Install the credential helper:
      ```bash
      curl -O https://rolesanywhere.amazonaws.com/releases/1.0.5/X86_64/Linux/aws_signing_helper
      chmod +x aws_signing_helper
      sudo mv aws_signing_helper /usr/local/bin/
      sudo chown root:root /usr/local/bin/aws_signing_helper
      ```
   3. Configure credential process in `~/.aws/config`:
      ```ini
      [profile rolesanywhere]
      credential_process = /usr/local/bin/aws_signing_helper credential-process \
          --certificate /path/to/certificate.pem \
          --private-key /path/to/private-key.pem \
          --trust-anchor-arn arn:aws:rolesanywhere:REGION:ACCOUNT:trust-anchor/TRUST_ANCHOR_ID \
          --profile-arn arn:aws:rolesanywhere:REGION:ACCOUNT:profile/PROFILE_ID \
          --role-arn arn:aws:iam::ACCOUNT:role/ROLE_NAME
      ```
   4. Mount using the profile:
      ```bash
      AWS_PROFILE=rolesanywhere sudo -E s3fs {bucket-name} /mnt/cloud/sessions \
          -o allow_other \
          -o endpoint={region} \
          -o url="https://s3-{region}.amazonaws.com"
      ```

   **Option C: Static credentials (last resort)**
   
   Only use if instance profiles and Roles Anywhere are not available.
   
   ```bash
   echo "ACCESS_KEY_ID:SECRET_ACCESS_KEY" > /root/.passwd-s3fs
   chmod 600 /root/.passwd-s3fs
   
   sudo s3fs {bucket-name} /mnt/cloud/sessions \
       -o passwd_file=/root/.passwd-s3fs \
       -o allow_other \
       -o endpoint={region} \
       -o url="https://s3-{region}.amazonaws.com"
   ```
   
   For persistent mount, add to `/etc/fstab`:
   ```
   {bucket-name} /mnt/cloud/sessions fuse.s3fs _netdev,allow_other,passwd_file=/root/.passwd-s3fs,endpoint={region},url=https://s3-{region}.amazonaws.com 0 0
   ```

### Google Cloud Storage (using gcsfuse)

1. Install gcsfuse:
   ```bash
   export GCSFUSE_REPO=gcsfuse-$(lsb_release -c -s)
   echo "deb https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
   curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
   sudo apt-get update
   sudo apt-get install gcsfuse
   ```

2. Create mount point:
   ```bash
   sudo mkdir -p /mnt/cloud/sessions
   ```

3. Configure authentication (choose one):

   **Option A: VM Service Account (recommended for GCE instances)**
   
   Attach a service account to your Compute Engine instance with Storage Object Admin permissions on the bucket. No additional configuration needed - gcsfuse will automatically use the instance metadata service.
   
   ```bash
   gcsfuse your-bucket-name /mnt/cloud/sessions
   ```
   
   For persistent mount, add to `/etc/fstab`:
   ```
   your-bucket-name /mnt/cloud/sessions gcsfuse rw,_netdev,allow_other,file_mode=644,dir_mode=755 0 0
   ```

   **Option B: Workload Identity Federation (recommended for non-GCP environments)**
   
   [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) allows external workloads to authenticate using OIDC/SAML tokens from external identity providers.
   
   1. Create a workload identity pool and provider in GCP
   2. Grant the external identity access to a service account with Storage permissions
   3. Download the credential configuration file
   4. Set the environment variable and mount:
      ```bash
      export GOOGLE_APPLICATION_CREDENTIALS=/path/to/credential-config.json
      gcsfuse your-bucket-name /mnt/cloud/sessions
      ```
   
   For persistent mount with systemd, create a service that sets the environment variable, or add to `/etc/environment`:
   ```
   GOOGLE_APPLICATION_CREDENTIALS=/path/to/credential-config.json
   ```

   **Option C: Service Account Key (last resort)**
   
   Only use if VM service accounts and Workload Identity Federation are not available.
   
   1. Create a service account and download the JSON key file
   2. Set permissions and mount:
      ```bash
      sudo mkdir -p /etc/gcsfuse
      sudo mv service-account-key.json /etc/gcsfuse/
      sudo chown root:root /etc/gcsfuse/service-account-key.json
      sudo chmod 600 /etc/gcsfuse/service-account-key.json
      
      GOOGLE_APPLICATION_CREDENTIALS=/etc/gcsfuse/service-account-key.json \
          gcsfuse your-bucket-name /mnt/cloud/sessions
      ```
   
   For persistent mount, add to `/etc/fstab`:
   ```
   your-bucket-name /mnt/cloud/sessions gcsfuse rw,_netdev,allow_other,key_file=/etc/gcsfuse/service-account-key.json 0 0
   ```

### Azure Blob Storage (using blobfuse2)

1. Install blobfuse2:
   ```bash
   sudo apt-get install libfuse3-dev fuse3
   curl -O https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
   sudo dpkg -i packages-microsoft-prod.deb
   sudo apt-get update
   sudo apt-get install blobfuse2
   ```

2. Create cache and mount directories:
   ```bash
   sudo mkdir -p /tmp/blobfuse2cache
   sudo mkdir -p /mnt/cloud/sessions
   ```

3. Configure authentication (choose one):

   **Option A: Managed Identity (recommended for Azure VMs)**
   
   Assign a managed identity to your Azure VM and grant it Storage Blob Data Contributor role on the storage account.
   
   Create config file at `/etc/blobfuse2/config.yaml`:
   ```yaml
   allow-other: true
   logging:
     type: syslog
     level: log_warning
   components:
     - libfuse
     - file_cache
     - attr_cache
     - azstorage
   libfuse:
     attribute-expiration-sec: 120
     entry-expiration-sec: 120
   file_cache:
     path: /tmp/blobfuse2cache
     timeout-sec: 120
   attr_cache:
     timeout-sec: 7200
   azstorage:
     type: block
     account-name: your-storage-account
     container: your-container-name
     mode: msi
   ```
   
   Mount the container:
   ```bash
   sudo blobfuse2 mount /mnt/cloud/sessions --config-file=/etc/blobfuse2/config.yaml
   ```
   
   For persistent mount, add to `/etc/fstab`:
   ```
   /mnt/cloud/sessions fuse blobfuse2,config-file=/etc/blobfuse2/config.yaml,_netdev 0 0
   ```

   **Option B: Workload Identity Federation (recommended for non-Azure environments)**
   
   [Workload Identity Federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation) allows external applications to authenticate using federated credentials from external identity providers.
   
   1. Register an application in Microsoft Entra ID
   2. Configure federated credentials for your external identity provider
   3. Grant the application Storage Blob Data Contributor role on the storage account
   4. Create config file at `/etc/blobfuse2/config.yaml`:
      ```yaml
      allow-other: true
      logging:
        type: syslog
        level: log_warning
      components:
        - libfuse
        - file_cache
        - attr_cache
        - azstorage
      libfuse:
        attribute-expiration-sec: 120
        entry-expiration-sec: 120
      file_cache:
        path: /tmp/blobfuse2cache
        timeout-sec: 120
      attr_cache:
        timeout-sec: 7200
      azstorage:
        type: block
        account-name: your-storage-account
        container: your-container-name
        mode: spn
        appid: your-application-client-id
        tenantid: your-tenant-id
        oauth-token-path: /path/to/federated-token
      ```
   5. Mount the container:
      ```bash
      sudo blobfuse2 mount /mnt/cloud/sessions --config-file=/etc/blobfuse2/config.yaml
      ```

   **Option C: Storage Account Key (last resort)**
   
   Only use if managed identities and Workload Identity Federation are not available.
   
   Create config file at `/etc/blobfuse2/config.yaml`:
   ```yaml
   allow-other: true
   logging:
     type: syslog
     level: log_warning
   components:
     - libfuse
     - file_cache
     - attr_cache
     - azstorage
   libfuse:
     attribute-expiration-sec: 120
     entry-expiration-sec: 120
   file_cache:
     path: /tmp/blobfuse2cache
     timeout-sec: 120
   attr_cache:
     timeout-sec: 7200
   azstorage:
     type: block
     account-name: your-storage-account
     account-key: your-storage-account-key
     container: your-container-name
     endpoint: https://your-storage-account.blob.core.windows.net
   ```
   
   Secure and mount:
   ```bash
   sudo chmod 600 /etc/blobfuse2/config.yaml
   sudo blobfuse2 mount /mnt/cloud/sessions --config-file=/etc/blobfuse2/config.yaml
   ```
   
   For persistent mount, add to `/etc/fstab`:
   ```
   /mnt/cloud/sessions fuse blobfuse2,config-file=/etc/blobfuse2/config.yaml,_netdev 0 0
   ```

## Configuration

The script uses environment variables that can be set in the systemd service file:

| Variable | Default | Description |
|----------|---------|-------------|
| `WATCHPATH` | `/var/log/sft/sessions` | Directory to watch for new session logs |
| `DESTPATH` | `/mnt/cloud/sessions` | Destination for output files |
| `SSH_MODE` | `convert` | SSH processing mode: `convert` (to asciinema .cast) or `copy` (raw source) |
| `RDP_MODE` | `convert` | RDP processing mode: `convert` (to .mkv) or `copy` (raw source) |
| `RETENTION_DAYS` | `0` | Days to retain source files before deletion (0 = disabled) |
| `CLEANUP_INTERVAL` | `3600` | Seconds between cleanup runs (default: 1 hour) |
