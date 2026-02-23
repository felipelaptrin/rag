import logging
import mimetypes
from pathlib import Path
from typing import Tuple

from botocore.client import BaseClient

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    force=True,
)

logger = logging.getLogger(__name__)


def download_s3_object(
    s3_client: BaseClient, bucket: str, key: str, dest_path: Path
) -> None:
    logging.info(f"Downloading file '{key}' from S3 bucket '{bucket}'...")
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        s3_client.download_file(bucket, key, str(dest_path))
        logging.info("Downloaded file completed")
    except Exception as error:
        logging.error(f"Could not download file from S3 Bucket because of: {error}")


def upload_s3_object(
    s3_client: BaseClient, bucket: str, key: str, file_path: Path
) -> None:
    logging.info(
        f"Uploading file '{file_path}' to S3 bucket '{bucket}' using key '{key}'..."
    )
    suffix = file_path.suffix.lower()
    if suffix == ".json":
        content_type = "application/json; charset=utf-8"
    elif suffix in (".md", ".markdown"):
        content_type = "text/markdown; charset=utf-8"
    else:
        content_type, _ = mimetypes.guess_type(str(file_path))
        content_type = content_type or "text/plain; charset=utf-8"

    try:
        s3_client.upload_file(
            str(file_path),
            bucket,
            key,
            ExtraArgs={
                "ContentType": content_type,
                "ContentDisposition": "inline",
            },
        )
        logging.info("Upload completed")
    except Exception as error:
        logging.error(f"Could not upload file to S3 Bucket because of: {error}")


def parse_s3_uri(s3_uri: str) -> Tuple[str, str]:
    if not s3_uri.startswith("s3://"):
        raise ValueError(f"Expected s3://bucket/key, got: {s3_uri}")
    rest = s3_uri[5:]
    bucket, sep, key = rest.partition("/")
    if not sep or not bucket or not key:
        raise ValueError(f"Invalid S3 URI (missing bucket or key): {s3_uri}")
    return bucket, key
