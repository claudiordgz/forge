import json
import subprocess
import tempfile
import os
import re
import boto3
from botocore.exceptions import ClientError
from google_auth_oauthlib.flow import InstalledAppFlow

# --- Config ---
ACCOUNT_URL = "https://my.1password.com"
ITEM_NAME = "trade-alerts-email-fetcher"
FILE_NAME = "client_secret_530302238416-q2venq4chso10vhahbc8gvg08op1rdj7.apps.googleusercontent.com.json"
VAULT_NAME = "Machines"
SECRET_NAME = "gmail/api/credentials"
REGION = "us-east-1"
KMS_KEY_ID = "arn:aws:kms:us-east-1:358485744732:key/f844d461-bd6c-4718-963a-de50861653e1"
SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]

def ensure_op_signed_in():
    """
    Ensure we have a valid OP session. If not, sign in non-interactively and
    export OP_SESSION_<shorthand>.
    """
    try:
        subprocess.run(["op", "whoami"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=os.environ.copy())
    except subprocess.CalledProcessError:
        # Sign in and get the full output to extract the session variable name
        signin_cmd = ["op", "signin", "--account", ACCOUNT_URL]
        token_proc = subprocess.run(
            signin_cmd,
            check=True, capture_output=True, text=True, env=os.environ.copy()
        )
        # The output should be the eval command
        output = token_proc.stdout.strip()
        print(f"Debug: op signin output: {output}")
        
        # Parse the eval output to extract the session token and variable name
        if "OP_SESSION_" in output:
            # Extract the session variable name and token
            match = re.search(r'(OP_SESSION_[^=]+)="([^"]+)"', output)
            if match:
                session_name = match.group(1)
                token = match.group(2)
                os.environ[session_name] = token
                print(f"Set {session_name} environment variable")
                print(f"Token value: {token[:10]}...")
            else:
                raise SystemExit("Failed to parse session token from op signin output")
        else:
            raise SystemExit("Failed to extract session token from op signin output")

def fetch_client_secret_file():
    """
    Reads the attachment content from 1Password.
    """
    ref = f"op://{VAULT_NAME}/{ITEM_NAME}/{FILE_NAME}"
    
    # Debug: Check what session variables are set
    session_vars = [k for k in os.environ.keys() if k.startswith('OP_SESSION_')]
    print(f"Debug: Session variables in environment: {session_vars}")
    
    try:
        res = subprocess.run(
            ["op", "read", ref],
            check=True,
            capture_output=True,
            text=True,
            env=os.environ.copy()  # Ensure environment variables are passed
        )
        return res.stdout
    except subprocess.CalledProcessError as e:
        raise SystemExit(f"Failed to read file from 1Password ({ref}): {e.stderr}")

def store_secret(payload):
    sm = boto3.client("secretsmanager", region_name=REGION)
    try:
        sm.create_secret(
            Name=SECRET_NAME,
            KmsKeyId=KMS_KEY_ID,
            SecretString=json.dumps(payload),
            Description="Gmail API OAuth credentials"
        )
        print(f"Created secret {SECRET_NAME}")
    except ClientError as e:
        if e.response["Error"]["Code"] == "ResourceExistsException":
            sm.put_secret_value(
                SecretId=SECRET_NAME,
                SecretString=json.dumps(payload)
            )
            print(f"Updated existing secret {SECRET_NAME}")
        else:
            raise

def main():
    ensure_op_signed_in()
    client_secret_json = fetch_client_secret_file()

    # Write to temp file because InstalledAppFlow expects a file path.
    tmp = tempfile.NamedTemporaryFile("w", delete=False)
    try:
        tmp.write(client_secret_json)
        tmp.close()

        flow = InstalledAppFlow.from_client_secrets_file(tmp.name, SCOPES)
        creds = flow.run_local_server(port=0)

        payload = {
            "client_id": creds.client_id,
            "client_secret": creds.client_secret,
            "refresh_token": creds.refresh_token
        }
        store_secret(payload)
        print("Stored credentials securely in Secrets Manager.")
    finally:
        os.remove(tmp.name)

if __name__ == "__main__":
    main()