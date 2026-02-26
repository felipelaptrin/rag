import json
import os

import boto3
from botocore.exceptions import ClientError


def get_api_key(secret_name: str) -> str:
    secrets_manager_client = boto3.client(
        "secretsmanager", region_name=os.getenv("AWS_REGION", "us-east-1")
    )

    if not secret_name.startswith("arn:aws:secretsmanager"):
        return secret_name

    try:
        response = secrets_manager_client.get_secret_value(SecretId=secret_name)
    except ClientError as e:
        raise RuntimeError(f"Failed to retrieve secret '{secret_name}': {e}") from e

    secret_str = response["SecretString"]
    return json.loads(secret_str)["api_key"]
