from __future__ import annotations

import hashlib
import json
import logging
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict
from urllib.parse import unquote_plus

import boto3
import pymupdf4llm
from dotenv import load_dotenv
from utils.env_vars import validate_required_env
from utils.s3 import download_s3_object, parse_s3_uri, upload_s3_object

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    force=True,
)

logger = logging.getLogger(__name__)
load_dotenv()

TMP_DIR = Path("/tmp")
CORPUS_PATH = TMP_DIR / "corpus.json"
MD_PATH = TMP_DIR / "extracted.md"
BUCKET = os.getenv("KNOWLEDGE_BASE_BUCKET")
s3_client = boto3.client("s3")


def safe_name(name: str, max_len: int = 160) -> str:
    name = re.sub(r"[^\w\-. ]+", "_", name).strip()
    name = re.sub(r"\s+", "_", name)
    return name[:max_len]


def normalize_md(text: str) -> str:
    if not text:
        return ""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = "\n".join(line.rstrip() for line in text.split("\n"))
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def pdf_to_markdown(pdf_path: Path) -> str:
    logging.info("Extracting PDF content to Markdown")
    md = pymupdf4llm.to_markdown(str(pdf_path), page_chunks=False)
    logging.info("PDF content extracted to Markdown successfully")
    return normalize_md(md)


def extract_s3_uri_from_event(event: Dict[str, Any]) -> str:
    logging.info("Extracting S3 URI from lambda event")
    if isinstance(event.get("detail"), dict):
        bucket = event["detail"]["bucket"]["name"]
        key = event["detail"]["object"]["key"]
        if bucket and key:
            s3_uri = f"s3://{bucket}/{unquote_plus(key)}"
            logging.info(f"Extracted S3 URI from S3 Event format: {s3_uri}")
            return s3_uri

    raise ValueError(
        "Could not determine s3_uri. Provide event['s3_uri'] or an S3 event payload."
    )


def process_pdf_from_s3(s3_uri: str) -> Dict[str, Any]:
    bucket, key = parse_s3_uri(s3_uri)
    if not key.lower().endswith(".pdf"):
        raise ValueError(f"Object is not a PDF (key={key})")

    # Put the downloaded PDF in /tmp
    local_pdf = TMP_DIR / safe_name(Path(key).name)
    download_s3_object(s3_client, bucket, key, local_pdf)

    doc_id = sha256_file(local_pdf)[:16]
    title = Path(key).stem
    extracted_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    md = pdf_to_markdown(local_pdf)
    if not md:
        raise RuntimeError("No text extracted. PDF may be scanned or protected.")

    # Write markdown file (overwrite)
    MD_PATH.write_text(md, encoding="utf-8")

    # Write single record to corpus.json (overwrite)
    record = {
        "doc_id": doc_id,
        "title": title,
        "source_s3_uri": s3_uri,
        "extracted_at_utc": extracted_at,
        "format": "markdown",
        "text": md,
    }
    CORPUS_PATH.write_text(
        json.dumps(record, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    md_key = f"clean/{doc_id}/extract_text.md"
    corpus_key = f"clean/{doc_id}/corpus.json"
    upload_s3_object(s3_client, BUCKET, md_key, file_path=MD_PATH)
    upload_s3_object(s3_client, BUCKET, corpus_key, file_path=CORPUS_PATH)

    return record


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    logger.info(f"Input Event => {event}")
    validate_required_env(["KNOWLEDGE_BASE_BUCKET"])
    s3_uri = event.get("s3_uri")
    if not isinstance(s3_uri, str) or not s3_uri:
        raise ValueError("Expected event['s3_uri'] as a non-empty string")
    result = process_pdf_from_s3(s3_uri)
    return {"result": result}


if os.getenv("ENV", "").upper() == "DEVELOPMENT":
    event = {"s3_uri": "s3://knowledge-base-dev-937168356724/raw/Buying-as-a-guest.pdf"}
    lambda_handler(
        event,
        {},
    )
