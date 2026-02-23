# PDF to Markdown Corpus Lambda

AWS Lambda that reacts to an event containing `s3_uri` for a PDF, downloads the PDF to `/tmp`, extracts its text into Markdown, creates a small JSON "corpus" record, then uploads both outputs back to an S3 bucket (the knowledge base bucket).

## What it does

Given an S3 PDF at `s3://<bucket>/<key>`

1) Downloads the PDF to `/tmp`
2) Computes a SHA-256 hash of the file and uses the first 16 chars as doc_id
3) Extracts text from the PDF into Markdown using `pymupdf4llm`
4) Writes two files to `/tmp`:
- `/tmp/extracted.md`: Extracted PDF in Markdown format
- `/tmp/corpus.json`: JSON containing metadata for RAG system and the context of the extracted PDF.
5) Uploads both files to `KNOWLEDGE_BASE_BUCKET` (environment variable) under: `clean/<doc_id>/extract_text.md` and `clean/<doc_id>/corpus.json`

## Requirements
Make sure you have `uv` installed and that  (to run the code locally).

## Environment variables

`KNOWLEDGE_BASE_BUCKET` (required): destination bucket for outputs
`ENV`: when set to DEVELOPMENT, the module will run a test event at import time. Set this if you would like to run the code locally using (`python main.py` command)

## How to run the project

1) Make sure you have `uv` installed
2) AWS credentials should be available to the runtime
3) Create a virtual environment using `uv`

```sh
source .venv/bin/activate
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
