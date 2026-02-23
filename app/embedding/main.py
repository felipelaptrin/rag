import json
import logging
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List
from uuid import NAMESPACE_URL, uuid5

import boto3
from dotenv import load_dotenv
from qdrant_client import QdrantClient
from qdrant_client.http import models as qmodels
from utils.env_vars import validate_required_env
from utils.s3 import download_s3_object, parse_s3_uri

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    force=True,
)
logger = logging.getLogger(__name__)
load_dotenv()

TMP_DIR = Path("/tmp")
INPUT_CHUNKS_PATH = TMP_DIR / "chunks.jsonl"

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

EMBEDDING_MODEL_ID = os.getenv("EMBEDDING_MODEL_ID", "amazon.titan-embed-text-v2:0")
EMBEDDING_DIMENSIONS = int(os.getenv("EMBEDDING_DIMENSIONS", "1024"))
EMBEDDING_NORMALIZE = os.getenv("EMBEDDING_NORMALIZE", "true").lower() == "true"
SLEEP_BETWEEN_CALLS_MS = int(os.getenv("SLEEP_BETWEEN_CALLS_MS", "0"))
QDRANT_URL = os.getenv("QDRANT_URL")
QDRANT_API_KEY = os.getenv("QDRANT_API_KEY")  # optional for local/self-hosted
QDRANT_COLLECTION = os.getenv("QDRANT_COLLECTION")
QDRANT_UPSERT_BATCH_SIZE = int(os.getenv("QDRANT_UPSERT_BATCH_SIZE", "64"))
QDRANT_SSL_VERIFY = os.getenv("QDRANT_SSL_VERIFY", "true").lower() == "true"

if EMBEDDING_DIMENSIONS not in (1024, 512, 256):
    raise ValueError("EMBEDDING_DIMENSIONS must be one of 1024, 512, 256")
if QDRANT_UPSERT_BATCH_SIZE < 1:
    raise ValueError("QDRANT_UPSERT_BATCH_SIZE must be >= 1")

bedrock_runtime = boto3.client("bedrock-runtime", region_name=AWS_REGION)
s3_client = boto3.client("s3")

qdrant_client = QdrantClient(
    url=QDRANT_URL, api_key=QDRANT_API_KEY, verify=bool(QDRANT_SSL_VERIFY)
)


def read_jsonl(path: Path) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError as e:
                raise ValueError(f"Invalid JSONL at line {line_no}: {e}") from e

            if not isinstance(rec, dict):
                raise ValueError(
                    f"Expected JSON object at line {line_no}, got {type(rec).__name__}"
                )
            records.append(rec)
    return records


def invoke_embedding_model(text: str) -> List[float]:
    body = {
        "inputText": text,
        "dimensions": EMBEDDING_DIMENSIONS,
        "normalize": EMBEDDING_NORMALIZE,
    }

    response = bedrock_runtime.invoke_model(
        modelId=EMBEDDING_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(body).encode("utf-8"),
    )

    payload_bytes = response["body"].read()
    payload = json.loads(payload_bytes)

    embedding = payload.get("embedding")
    if not isinstance(embedding, list) or not embedding:
        raise RuntimeError(f"Bedrock response missing embedding vector: {payload}")

    if len(embedding) != EMBEDDING_DIMENSIONS:
        raise RuntimeError(
            f"Unexpected embedding length={len(embedding)} expected={EMBEDDING_DIMENSIONS}"
        )

    return embedding


def qdrant_point_id_from_chunk_id(chunk_id: str) -> str:
    # Deterministic UUID based on chunk_id (stable across reruns)
    return str(uuid5(NAMESPACE_URL, chunk_id))


def build_qdrant_point(
    chunk: Dict[str, Any], embedding: List[float]
) -> qmodels.PointStruct:
    chunk_meta = chunk.get("meta")
    if chunk_meta is None:
        chunk_meta = {}
    if not isinstance(chunk_meta, dict):
        raise ValueError(f"Chunk {chunk['chunk_id']} meta must be an object if present")

    embedded_at_utc = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    payload = {
        "chunk_id": chunk["chunk_id"],
        "doc_id": chunk["doc_id"],
        "chunk_index": chunk["chunk_index"],
        "text": chunk["text"],
        "meta": {
            **chunk_meta,
            "embedding_model_id": EMBEDDING_MODEL_ID,
            "embedding_dimensions": EMBEDDING_DIMENSIONS,
            "embedding_normalize": EMBEDDING_NORMALIZE,
            "embedded_at_utc": embedded_at_utc,
        },
    }

    return qmodels.PointStruct(
        id=qdrant_point_id_from_chunk_id(chunk["chunk_id"]),
        vector=embedding,
        payload=payload,
    )


def upsert_points(points: List[qmodels.PointStruct]) -> None:
    if not points:
        return

    qdrant_client.upsert(
        collection_name=QDRANT_COLLECTION,
        points=points,
        wait=True,
    )


def process_chunks_from_s3(s3_uri: str) -> Dict[str, Any]:
    in_bucket, in_key = parse_s3_uri(s3_uri)

    if not in_key.endswith("/chunks.jsonl"):
        raise ValueError(f"Expected chunks/<doc_id>/chunks.jsonl, got: {in_key}")

    download_s3_object(s3_client, in_bucket, in_key, INPUT_CHUNKS_PATH)

    chunks = read_jsonl(INPUT_CHUNKS_PATH)
    if not chunks:
        raise RuntimeError("Input chunks.jsonl is empty")

    doc_ids = {rec["doc_id"] for rec in chunks}
    if len(doc_ids) != 1:
        raise ValueError(f"Expected one doc_id in input, got: {sorted(doc_ids)}")
    doc_id = next(iter(doc_ids))

    logger.info(
        f"Embedding+Upsert doc_id={doc_id} chunk_count={len(chunks)} model={EMBEDDING_MODEL_ID} dims={EMBEDDING_DIMENSIONS} normalize={EMBEDDING_NORMALIZE} qdrant_collection={QDRANT_COLLECTION}"
    )

    text_lengths = [len(r["text"]) for r in chunks]
    logger.info(
        f"Input chunk lengths (chars): min={min(text_lengths)} avg={sum(text_lengths) // len(text_lengths)} max={max(text_lengths)}",
    )

    # Process sequentially for embeddings, batch only for Qdrant upsert
    pending_points: List[qmodels.PointStruct] = []
    upserted_count = 0

    for chunk in chunks:
        embedding = invoke_embedding_model(chunk["text"])
        point = build_qdrant_point(chunk, embedding)
        pending_points.append(point)

        if len(pending_points) >= QDRANT_UPSERT_BATCH_SIZE:
            upsert_points(pending_points)
            upserted_count += len(pending_points)
            logger.info(f"Upserted {upserted_count}/{len(chunks)} points to Qdrant")
            pending_points = []

        if SLEEP_BETWEEN_CALLS_MS > 0:
            time.sleep(SLEEP_BETWEEN_CALLS_MS / 1000.0)

    if pending_points:
        upsert_points(pending_points)
        upserted_count += len(pending_points)

    logger.info(f"Generated and upserted {upserted_count} embeddings to Qdrant")

    return {
        "doc_id": doc_id,
        "input_chunks_s3_uri": s3_uri,
        "qdrant_collection": QDRANT_COLLECTION,
        "embedding_count": upserted_count,
        "embedding_model_id": EMBEDDING_MODEL_ID,
        "embedding_dimensions": EMBEDDING_DIMENSIONS,
        "embedding_normalize": EMBEDDING_NORMALIZE,
        "sdk_retry_mode": "standard",
        "sdk_max_attempts": int(os.getenv("AWS_MAX_ATTEMPTS", "5")),
    }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    logger.info("Input Event => %s", event)
    validate_required_env(["QDRANT_URL", "QDRANT_API_KEY", "QDRANT_COLLECTION"])

    s3_uri = event.get("s3_uri")
    if not isinstance(s3_uri, str) or not s3_uri:
        raise ValueError("Expected event['s3_uri'] as a non-empty string")

    result = process_chunks_from_s3(s3_uri)
    return {"ok": True, "result": result}


if os.getenv("ENV", "").upper() == "DEVELOPMENT":
    event = {
        "s3_uri": "s3://knowledge-base-dev-937168356724/chunks/2d9c79cb32d574af/chunks.jsonl"
    }
    lambda_handler(event, {})
