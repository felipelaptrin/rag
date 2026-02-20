#!/usr/bin/env python3
"""
Lambda-friendly: S3 PDF -> /tmp corpus.jsonl (+ .md) using pymupdf4llm.

What it does
- Takes a single S3 URI like: s3://my-bucket/path/to/file.pdf
- Downloads the PDF to /tmp
- Converts PDF -> Markdown using pymupdf4llm
- Writes (overwriting if they already exist):
  - /tmp/<doc_id>_<title>.md
  - /tmp/corpus.jsonl  (single JSON object, not JSONL append)

Requires:
  pip install -U boto3 pymupdf4llm pymupdf_layout
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Tuple
from urllib.parse import unquote_plus

import boto3
import pymupdf4llm

TMP_DIR = Path("/tmp")
CORPUS_PATH = (
    TMP_DIR / "corpus.jsonl"
)  # kept name for compatibility, but overwritten with 1 JSON record


def parse_s3_uri(s3_uri: str) -> Tuple[str, str]:
    if not s3_uri.startswith("s3://"):
        raise ValueError(f"Expected s3://bucket/key, got: {s3_uri}")
    rest = s3_uri[5:]
    bucket, sep, key = rest.partition("/")
    if not sep or not bucket or not key:
        raise ValueError(f"Invalid S3 URI (missing bucket or key): {s3_uri}")
    return bucket, key


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


def download_s3_object(bucket: str, key: str, dest_path: Path) -> None:
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    boto3.client("s3").download_file(bucket, key, str(dest_path))


def pdf_to_markdown(pdf_path: Path) -> str:
    md = pymupdf4llm.to_markdown(str(pdf_path), page_chunks=False)
    return normalize_md(md)


def extract_s3_uri_from_event(event: Dict[str, Any]) -> str:
    # 1) Direct invoke format
    if isinstance(event.get("s3_uri"), str):
        return event["s3_uri"]

    # 2) S3 event notification format
    records = event.get("Records")
    if isinstance(records, list) and records:
        r0 = records[0]
        s3_info = r0.get("s3", {})
        bucket = s3_info.get("bucket", {}).get("name")
        key = s3_info.get("object", {}).get("key")
        if bucket and key:
            return f"s3://{bucket}/{unquote_plus(key)}"

    raise ValueError(
        "Could not determine s3_uri. Provide event['s3_uri'] or an S3 event payload."
    )


def process_one_pdf_from_s3(s3_uri: str) -> Dict[str, Any]:
    bucket, key = parse_s3_uri(s3_uri)
    if not key.lower().endswith(".pdf"):
        raise ValueError(f"Object is not a PDF (key={key})")

    # Put the downloaded PDF in /tmp
    local_pdf = TMP_DIR / safe_name(Path(key).name)
    download_s3_object(bucket, key, local_pdf)

    doc_id = sha256_file(local_pdf)[:16]
    title = Path(key).stem
    extracted_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    md = pdf_to_markdown(local_pdf)
    if not md:
        raise RuntimeError("No text extracted. PDF may be scanned or protected.")

    # Write markdown file (overwrite)
    md_path = TMP_DIR / (safe_name(f"{doc_id}_{title}") + ".md")
    md_path.write_text(md, encoding="utf-8")

    # Write ONE record to corpus.jsonl (overwrite)
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

    return {
        "doc_id": doc_id,
        "title": title,
        "source_s3_uri": s3_uri,
        "downloaded_pdf_path": str(local_pdf),
        "md_path": str(md_path),
        "corpus_jsonl_path": str(CORPUS_PATH),
        "markdown_chars": len(md),
    }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    s3_uri = extract_s3_uri_from_event(event)
    result = process_one_pdf_from_s3(s3_uri)
    return {"ok": True, "result": result}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--s3-uri", required=True, help="Example: s3://bucket/key.pdf")
    args = ap.parse_args()
    res = process_one_pdf_from_s3(args.s3_uri)
    print(json.dumps(res, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
