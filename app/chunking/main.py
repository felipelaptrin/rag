import json
import logging
import os
from pathlib import Path
from typing import Any, Dict, List

import boto3
from dotenv import load_dotenv
from langchain_text_splitters import (
    MarkdownTextSplitter,
    RecursiveCharacterTextSplitter,
)
from utils.s3 import download_s3_object, upload_s3_object

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    force=True,
)
logger = logging.getLogger(__name__)
load_dotenv()

TMP_DIR = Path("/tmp")
INPUT_CORPUS_PATH = TMP_DIR / "corpus.json"
OUTPUT_CHUNKS_PATH = TMP_DIR / "chunks.jsonl"

BUCKET = os.getenv("KNOWLEDGE_BASE_BUCKET")
s3_client = boto3.client("s3")

CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "1200"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "200"))


def parse_s3_uri(s3_uri: str) -> tuple[str, str]:
    if not s3_uri.startswith("s3://"):
        raise ValueError(f"Invalid S3 URI: {s3_uri}")
    rest = s3_uri[5:]
    bucket, sep, key = rest.partition("/")
    if not sep or not bucket or not key:
        raise ValueError(f"Invalid S3 URI: {s3_uri}")
    return bucket, key


def load_corpus_record(path: Path) -> Dict[str, Any]:
    raw = path.read_text(encoding="utf-8").strip()
    # Your extractor writes one JSON object (with newline), not JSONL list
    return json.loads(raw)


def split_markdown_text(text: str) -> List[str]:
    """
    Two-step split:
    1) Markdown-aware splitter (better heading boundaries)
    2) Fallback recursive splitter if any chunk is still too large
    """
    md_splitter = MarkdownTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
    )

    recursive_splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
    )

    first_pass = md_splitter.split_text(text)

    final_chunks: List[str] = []
    for chunk in first_pass:
        if len(chunk) <= CHUNK_SIZE * 1.2:
            final_chunks.append(chunk)
        else:
            final_chunks.extend(recursive_splitter.split_text(chunk))

    # Remove empty / whitespace chunks
    return [c.strip() for c in final_chunks if c and c.strip()]


def build_chunk_records(doc: Dict[str, Any], chunks: List[str]) -> List[Dict[str, Any]]:
    doc_id = doc["doc_id"]

    records: List[Dict[str, Any]] = []
    for i, chunk_text in enumerate(chunks):
        chunk_id = f"{doc_id}:{i:06d}"
        records.append(
            {
                "chunk_id": chunk_id,
                "doc_id": doc_id,
                "chunk_index": i,
                "text": chunk_text,
                "meta": {
                    "title": doc.get("title"),
                    "source_s3_uri": doc.get("source_s3_uri"),
                    "extracted_at_utc": doc.get("extracted_at_utc"),
                    "format": doc.get("format"),
                },
            }
        )
    return records


def write_chunks_jsonl(chunk_records: List[Dict[str, Any]], path: Path) -> None:
    with path.open("w", encoding="utf-8") as f:
        for rec in chunk_records:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def process_corpus_from_s3(s3_uri: str) -> Dict[str, Any]:
    bucket, key = parse_s3_uri(s3_uri)

    if not key.endswith("/corpus.json"):
        raise ValueError(f"Expected clean/<doc_id>/corpus.json, got: {key}")

    download_s3_object(s3_client, bucket, key, INPUT_CORPUS_PATH)

    doc = load_corpus_record(INPUT_CORPUS_PATH)
    text = doc.get("text", "")
    if not text.strip():
        raise RuntimeError("Corpus text is empty")

    logger.info(f"Chunking doc_id={doc.get('doc_id')} title={doc.get('title')}")
    chunks = split_markdown_text(text)
    chunk_records = build_chunk_records(doc, chunks)
    lengths = [len(c["text"]) for c in chunk_records]
    if lengths:
        logger.info(
            "Chunk lengths (chars): min=%d avg=%d max=%d",
            min(lengths),
            sum(lengths) // len(lengths),
            max(lengths),
        )

    logger.info("Generated %d chunks", len(chunk_records))
    write_chunks_jsonl(chunk_records, OUTPUT_CHUNKS_PATH)

    doc_id = doc["doc_id"]
    chunks_key = f"chunks/{doc_id}/chunks.jsonl"
    upload_s3_object(s3_client, BUCKET, chunks_key, OUTPUT_CHUNKS_PATH)

    return {
        "doc_id": doc_id,
        "input_corpus_s3_uri": s3_uri,
        "output_chunks_s3_uri": f"s3://{BUCKET}/{chunks_key}",
        "chunk_count": len(chunk_records),
        "chunk_size": CHUNK_SIZE,
        "chunk_overlap": CHUNK_OVERLAP,
    }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    logger.info(f"Input Event => {event}")
    s3_uri = event.get("s3_uri")
    if not isinstance(s3_uri, str) or not s3_uri:
        raise ValueError("Expected event['s3_uri'] as a non-empty string")
    result = process_corpus_from_s3(s3_uri)
    return {"ok": True, "result": result}


if os.getenv("ENV", "").upper() == "DEVELOPMENT":
    event = {
        "s3_uri": "s3://knowledge-base-dev-937168356724/clean/2d9c79cb32d574af/corpus.json"
    }
    lambda_handler(
        event,
        {},
    )
