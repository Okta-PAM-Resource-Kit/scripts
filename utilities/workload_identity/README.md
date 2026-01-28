# OPA Workload Identity with GCP Example Script

## Overview

This script, `sftSshWithGcpJwt.sh`, demonstrates how to use Okta Privileged Access (OPA) Workload Identity to securely access a server from a Google Cloud Platform (GCP) virtual machine.

It automates the process of:
1.  Requesting a JSON Web Token (JWT) from the GCP metadata service for the VM's associated service account.
2.  Exchanging this JWT for a short-lived OPA access token via an OPA Workload Identity Connection.
3.  Using the OPA token to initiate an SSH session to a target server managed by OPA.

This serves as a practical example for machine-to-machine authentication flows where a workload (in this case, a GCP VM) needs to programmatically and securely access other infrastructure.

**_This script is provided as-is, with no support or warranty expressed or implied. Please review and understand the script before using it. Use at your own risk._**

## Prerequisites

Before running this script, ensure the following requirements are met:

1.  **GCP Environment**: The script must be run on a GCP VM that has an associated service account.
2.  **OPA Configuration**:
    *   An OPA **Workload Identity Connection** for GCP must be configured in your OPA team.
    *   The GCP service account used by the VM must be authorized to use this connection and assume a specific role within your OPA project.
3.  **Required Tools**: The following command-line utilities must be installed and available in the system's `PATH`:
    *   `sft` (Okta Privileged Access client)
    *   `curl`
    *   `jq`
    *   `base64` (standard on Linux) or `gbase64` (from `coreutils` on macOS)

## Configuration

The script can be configured in two ways:

1.  **Command-Line Arguments (Recommended)**: Pass arguments at runtime to specify connection details. This is the most flexible method.
2.  **Editing Defaults**: Modify the default values for variables at the beginning of the `main()` function within the script for a hardcoded configuration.

### Command-Line Options

```
Usage: ./sftSshWithGcpJwt.sh [options]

Options:
  -t <team>          Specify the SFT_TEAM. (Default: auto-discovered via sftd agent)
  -o <address>       Specify the OPA_ADDR (Default: assembled from SFT_TEAM and OPA_ENVIRONMENT)
  -s <server>        Specify the SFT_SERVER to connect to.
  -c <connection>    Specify the Workload Identity connection name.
  -r <role>          Specify the Workload Identity role.
  -a <audience>      Specify the JWT audience.
  -e <env>           Specify the OPA environment: prod, preview, or trex.
  -v                 Enable verbose output for debugging.
  -h                 Display this help message and exit.
```

## Usage Examples

### Basic Usage

Connect to the server `target-server-01` using the Workload Identity connection `gcp-prod-connection` and the role `cicd-runner`.

```bash
./sftSshWithGcpJwt.sh \
  -s target-server-01 \
  -c gcp-prod-connection \
  -r cicd-runner \
  -a "1234567890-abcdefghijklmnopqrstuvwxyz.apps.googleusercontent.com"
```

### Verbose Mode for Debugging

If you encounter issues, run the script with the `-v` flag to see detailed step-by-step output, including the tokens being used.

```bash
./sftSshWithGcpJwt.sh -v \
  -s target-server-01 \
  -c gcp-prod-connection \
  -r cicd-runner \
  -a "1234567890-abcdefghijklmnopqrstuvwxyz.apps.googleusercontent.com"
```