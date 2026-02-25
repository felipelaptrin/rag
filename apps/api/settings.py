import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class Settings:
    aws_region: str
    vector_db_host: str
    qdrant_collection: str
    bedrock_embedding_model_id: str
    bedrock_generation_model_id: str

    qdrant_api_key: str | None
    top_k_default: int
    top_k_max: int
    max_context_chunks: int
    max_context_chars: int

    gen_temperature: float
    gen_max_tokens: int

    log_level: str


def _required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def load_settings() -> Settings:
    return Settings(
        aws_region=_required("AWS_REGION"),
        vector_db_host=_required("VECTOR_DB_HOST"),
        qdrant_collection=_required("QDRANT_COLLECTION"),
        bedrock_embedding_model_id=_required("BEDROCK_EMBEDDING_MODEL_ID"),
        bedrock_generation_model_id=_required("BEDROCK_GENERATION_MODEL_ID"),
        qdrant_api_key=os.getenv("QDRANT_API_KEY"),
        top_k_default=int(os.getenv("TOP_K_DEFAULT", "5")),
        top_k_max=int(os.getenv("TOP_K_MAX", "10")),
        max_context_chunks=int(os.getenv("MAX_CONTEXT_CHUNKS", "5")),
        max_context_chars=int(os.getenv("MAX_CONTEXT_CHARS", "12000")),
        gen_temperature=float(os.getenv("GEN_TEMPERATURE", "0.2")),
        gen_max_tokens=int(os.getenv("GEN_MAX_TOKENS", "800")),
        log_level=os.getenv("LOG_LEVEL", "INFO").upper(),
    )
