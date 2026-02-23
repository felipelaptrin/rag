# Chunking

This Lambda function downloads a cleaned document corpus file from S3, splits the document text into chunks (optimized for Markdown), writes the chunks as JSONL, and uploads the result back to S3.

## What it does
Given an input event like:

```sh
{
  "s3_uri": "s3://your-bucket/clean/<doc_id>/corpus.json"
}
```

the function will:
1) Validate and parse the S3 URI
2) Download `corpus.json` to `/tmp/corpus.json`
3) Read the document payload (single JSON object)
4) Split the text field into chunks using:
- `MarkdownTextSplitter` first (preserves heading structure better)
- `RecursiveCharacterTextSplitter` fallback for oversized chunks
5) Build chunk records with metadata
6) Write chunks to `/tmp/chunks.jsonl`
7) Upload the JSONL to `s3://<KNOWLEDGE_BASE_BUCKET>/chunks/<doc_id>/chunks.jsonl`

## Environment variables

`KNOWLEDGE_BASE_BUCKET` (required): Destination bucket where chunk files are uploaded
`CHUNK_SIZE`: Target chunk size (characters)
`CHUNK_OVERLAP`: Overlap between chunks (characters)
`ENV`: If set to DEVELOPMENT, runs the local test block at import time
`MAX_EMBED_INPUT_CHARS`: Safety limit in characters before sending text to the embedding model. The maximum value here should be the checked in the embedding models documentation. E.g. for [Titan V2](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html) can intake up to 50,000 characters. Do not use the maximum!
`TOKEN_RATIO`: Ratio to transform chars (in English) to tokens. E.g. for [Titan V2](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html?utm_source=chatgpt.com) this ratio is `4.7`

## How to run the project

1) Make sure you have `uv` installed
2) AWS credentials should be available to the runtime
3) Create a virtual environment using `uv`

```sh
uv venv
```

4) Active the environment

```sh
source .venv/bin/activate
```

5) Install dependencies

```sh
uv sync
```

6) Set environment variables using `.env.example` as reference

7) Run the code

```sh
python main.py
```
