import logging
import time
from typing import Generator

from services.embeddings import EmbeddingService
from services.generation import GenerationService
from services.prompting import PromptBuilder
from services.retrieval import RetrievalService

logger = logging.getLogger(__name__)


class RAGService:
    def __init__(
        self,
        embedding_service: EmbeddingService,
        retrieval_service: RetrievalService,
        prompt_builder: PromptBuilder,
        generation_service: GenerationService,
        top_k_default: int,
        top_k_max: int,
    ) -> None:
        self.embedding_service = embedding_service
        self.retrieval_service = retrieval_service
        self.prompt_builder = prompt_builder
        self.generation_service = generation_service
        self.top_k_default = top_k_default
        self.top_k_max = top_k_max

    def _normalize_top_k(self, top_k: int | None) -> int:
        if top_k is None:
            return self.top_k_default
        return max(1, min(int(top_k), self.top_k_max))

    def stream_answer(
        self,
        question: str,
    ) -> Generator[str, None, None]:
        question = question.strip()
        normalized_top_k = self.top_k_default

        t0 = time.perf_counter()
        query_vector = self.embedding_service.embed_query(question)
        t1 = time.perf_counter()

        chunks = self.retrieval_service.similarity_search(
            query_vector=query_vector,
            top_k=normalized_top_k,
        )
        for i, chunk in enumerate(chunks, start=1):
            logger.info(f"----- Retrieved chunk #{i} -----")
            logger.info(
                f"score={chunk.score} | chunk_id={chunk.chunk_id} | doc_id={chunk.doc_id}"
            )
            logger.info("text:\n%s", chunk.text[:1000])
        t2 = time.perf_counter()

        system_prompt, messages = (
            self.prompt_builder.build_messages_for_bedrock_converse(
                question=question,
                chunks=chunks,
            )
        )
        t3 = time.perf_counter()

        logger.info(
            "RAG query prepared. top_k=%d retrieved=%d embed_ms=%d retrieval_ms=%d prompt_ms=%d",
            normalized_top_k,
            len(chunks),
            int((t1 - t0) * 1000),
            int((t2 - t1) * 1000),
            int((t3 - t2) * 1000),
        )

        yield from self.generation_service.stream_answer(
            system_prompt=system_prompt,
            messages=messages,
        )
