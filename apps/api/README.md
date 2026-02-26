# RAG API

FastAPI-based REST API that provides a Retrieval-Augmented Generation (RAG) endpoint for question answering using AWS Bedrock and Qdrant vector database.

## What it does

This API provides a streaming endpoint (`/ask`) that answers questions using RAG:

1. Takes a question as input
2. Embeds the question using AWS Bedrock
3. Retrieves relevant context chunks from Qdrant vector database
4. Builds a prompt with the retrieved context and question
5. Generates a streaming answer using AWS Bedrock

The API uses:
- **AWS Bedrock** for text embeddings (Titan) and text generation (Gemma)
- **Qdrant** as the vector database for storing and retrieving document chunks
- **FastAPI** for the REST API with streaming responses

## Requirements

- Python 3.12
- AWS credentials with Bedrock access
- Qdrant vector database running and accessible (you can use the Docker Compose)
- `uv` package manager

## Environment variables

`AWS_REGION` (required): AWS region for Bedrock and Secrets Manager
`VECTOR_DB_HOST` (required): Qdrant server URL (e.g., http://localhost:6333)
`QDRANT_API_KEY` (required): Qdrant API key or AWS Secrets Manager ARN
`QDRANT_COLLECTION` (required): Qdrant collection name
`BEDROCK_EMBEDDING_MODEL_ID` (required): Bedrock embedding model ID (e.g., amazon.titan-embed-text-v2:0)
`BEDROCK_GENERATION_MODEL_ID` (required): Bedrock generation model ID (e.g., google.gemma-3-4b-it)
`TOP_K_DEFAULT`: Default number of chunks to retrieve
`TOP_K_MAX`: Maximum number of chunks to retrieve
`MAX_CONTEXT_CHUNKS`: Maximum chunks to include in context
`MAX_CONTEXT_CHARS`: Maximum characters in context
`GEN_TEMPERATURE`: Generation temperature
`GEN_MAX_TOKENS`: Maximum tokens in generation
`LOG_LEVEL`: Logging level

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

6. Run the development server

```sh
make dev
```

7. Test the API

```sh
curl -X POST http://localhost:8080/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "What is the return policy?"}'
```
