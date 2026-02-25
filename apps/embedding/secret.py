import json

from botocore.client import BaseClient
from botocore.exceptions import ClientError


def get_api_key(secrets_manager_client: BaseClient, secret_name: str) -> str:
    if not secret_name.startswith("arn:aws:secretsmanager"):
        return secret_name

    try:
        response = secrets_manager_client.get_secret_value(SecretId=secret_name)
    except ClientError as e:
        raise RuntimeError(f"Failed to retrieve secret '{secret_name}': {e}") from e

    secret_str = response["SecretString"]
    return json.loads(secret_str)["api_key"]
