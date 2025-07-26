# Trader

## Gmail API Credentials Setup

### Overview

The `trade-alerts-email-fetcher/setup-secrets.py` script is used to set up and refresh Gmail API OAuth credentials for the email fetcher service.

### Purpose

This script runs **ad-hoc** when we need to refresh the OAuth token for the Gmail API integration. It handles the complete OAuth flow and securely stores the credentials in AWS Secrets Manager.

### How it works

1. **1Password Integration**: The script authenticates with 1Password CLI and retrieves the Google service account client secret file from the `Machines` vault
2. **OAuth Flow**: It initiates the Google OAuth flow, opening a browser for user authentication
3. **Token Storage**: After successful authentication, it stores the credentials (client ID, client secret, and refresh token) in AWS Secrets Manager under the key `gmail/api/credentials`
4. **Security**: All credentials are encrypted using AWS KMS before storage

### Google Project Details

- **Project**: `forge-home-prod`
- **Service Account**: The OAuth app is registered under this Google Cloud project
- **Scopes**: `https://www.googleapis.com/auth/gmail.readonly` (read-only access to Gmail)

### Prerequisites

- 1Password CLI installed and configured
- AWS credentials configured with access to Secrets Manager
- Access to the Google OAuth app (must be added as a test user if not verified)

### Usage

```bash
cd trader
poetry run python trade-alerts-email-fetcher/setup-secrets.py
```

The script will:
1. Prompt for your 1Password password
2. Open a browser for Google OAuth authentication
3. Store the credentials in AWS Secrets Manager

### When to run

Run this script when:
- Setting up the email fetcher for the first time
- The OAuth refresh token expires (typically after 6 months)
- You need to update the service account credentials
