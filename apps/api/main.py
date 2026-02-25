import logging
from contextlib import asynccontextmanager

import boto3
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse, StreamingResponse
from qdrant_client import QdrantClient
from schemas import AskRequest, HealthResponse
from services.embeddings import EmbeddingService
from services.generation import GenerationService
from services.prompting import PromptBuilder
from services.rag import RAGService
from services.retrieval import RetrievalService
from settings import Settings, load_settings


def configure_logging(level: str) -> None:
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        force=True,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings: Settings = load_settings()
    configure_logging(settings.log_level)
    logger = logging.getLogger(__name__)
    logger.info("Starting FastAPI RAG API")

    bedrock_runtime = boto3.client(
        "bedrock-runtime",
        region_name=settings.aws_region,
    )
    qdrant_client = QdrantClient(
        url=settings.vector_db_host,
        timeout=15.0,
        api_key=settings.qdrant_api_key,
    )

    embedding_service = EmbeddingService(
        bedrock_runtime=bedrock_runtime,
        model_id=settings.bedrock_embedding_model_id,
    )
    retrieval_service = RetrievalService(
        qdrant_client=qdrant_client,
        collection_name=settings.qdrant_collection,
    )
    prompt_builder = PromptBuilder(
        max_context_chunks=settings.max_context_chunks,
        max_context_chars=settings.max_context_chars,
    )
    generation_service = GenerationService(
        bedrock_runtime=bedrock_runtime,
        model_id=settings.bedrock_generation_model_id,
        temperature=settings.gen_temperature,
        max_tokens=settings.gen_max_tokens,
    )

    app.state.settings = settings
    app.state.rag_service = RAGService(
        embedding_service=embedding_service,
        retrieval_service=retrieval_service,
        prompt_builder=prompt_builder,
        generation_service=generation_service,
        top_k_default=settings.top_k_default,
        top_k_max=settings.top_k_max,
    )

    yield

    logger.info("Shutting down FastAPI RAG API")


app = FastAPI(title="RAG API", version="0.1.0", lifespan=lifespan)


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(ok=True, service="rag-api")


@app.post("/ask/stream")
def ask_stream(payload: AskRequest):
    rag_service = app.state.rag_service
    logger = logging.getLogger(__name__)

    try:
        generator = rag_service.stream_answer(
            question=payload.question,
        )

        return StreamingResponse(
            generator,
            media_type="text/plain; charset=utf-8",
            headers={
                "Cache-Control": "no-cache",
                # Useful if you test behind proxies. Harmless if ignored.
                "X-Content-Type-Options": "nosniff",
            },
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        logger.exception("Failed to start streaming response: %s", error)
        return JSONResponse(
            status_code=500,
            content={"detail": "Failed to process request"},
        )
