# Embedding Lambda

AWS Lambda that reads chunked text from S3, generates embeddings using AWS Bedrock, and stores them in Qdrant vector database.

## What it does

Given an S3 URI for a `chunks.jsonl` file (e.g., `s3://<bucket>/chunks/<doc_id>/chunks.jsonl`):

1. Downloads the chunks.jsonl file from S3 to /tmp
2. Reads each chunk record from the JSONL file
3. Generates embeddings for each chunk text using AWS Bedrock (Titan embedding model)
4. Upserts the embeddings into Qdrant vector database with metadata
5. Returns a result with embedding count and metadata

The Lambda expects an event with `s3_uri` key containing the S3 path to the chunks file.

## Requirements

- Python 3.12
- AWS credentials with Bedrock access
- Qdrant vector database running and accessible (you can use the Docker Compose)
- `uv` package manager

## Environment variables

`AWS_REGION`: AWS region for Bedrock and Secrets Manager
`QDRANT_URL` (required): Qdrant server URL (e.g., http://localhost:6333)
`QDRANT_API_KEY` (required): Qdrant API key or AWS Secrets Manager ARN
`QDRANT_COLLECTION` (required): Qdrant collection name
`QDRANT_SSL_VERIFY` (required): Enable SSL verification for Qdrant
`EMBEDDING_MODEL_ID`: Bedrock embedding model ID
`EMBEDDING_DIMENSIONS`: Embedding dimensions - must be 1024, 512, or 256
`EMBEDDING_NORMALIZE` (required): Normalize embedding vectors
`SLEEP_BETWEEN_CALLS_MS`: Sleep duration between Bedrock API calls in milliseconds
`QDRANT_UPSERT_BATCH_SIZE`: Batch size for Qdrant upsert operations
`ENV`: Set to "DEVELOPMENT" to run test event at import time

## How to run the project

1. Make sure you have `uv` installed

2. Create a virtual environment using `uv`

```sh
uv venv
```

3. Activate the environment

```sh
source .venv/bin/activate
```

4. Install dependencies

```sh
uv sync
```

5. Set environment variables using `.env.example` as reference

```sh
cp .env.example .env
# Edit .env with your actual values
```

6. Run the code (for development)

```sh
python main.py
```

Or deploy as AWS Lambda with an event trigger:

```json
{
  "s3_uri": "s3://your-bucket/chunks/<doc_id>/chunks.jsonl"
}
```

## Qdrant Collection Setup

Before running, ensure the Qdrant collection exists with the correct vector configuration:

```sh
curl -sS -X PUT "$QDRANT_URL/collections/$QDRANT_COLLECTION" \
  -H "Content-Type: application/json" \
  -H "api-key: $QDRANT_API_KEY" \
  --data '{
    "vectors": {
      "size": 1024,
      "distance": "Cosine"
    }
  }'
```

Note: The size should match `EMBEDDING_DIMENSIONS` (default: 1024).
