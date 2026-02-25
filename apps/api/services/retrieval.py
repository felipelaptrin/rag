from dataclasses import dataclass
from typing import List, Sequence


@dataclass
class RetrievedChunk:
    chunk_id: str
    doc_id: str
    text: str
    score: float
    title: str | None = None
    source_s3_uri: str | None = None


class RetrievalService:
    def __init__(self, qdrant_client, collection_name: str) -> None:
        self.qdrant_client = qdrant_client
        self.collection_name = collection_name

    def similarity_search(
        self,
        query_vector: Sequence[float],
        top_k: int,
    ) -> List[RetrievedChunk]:
        # qdrant-client versions differ a bit. Try query_points first, fallback to search.
        results = None

        if hasattr(self.qdrant_client, "query_points"):
            resp = self.qdrant_client.query_points(
                collection_name=self.collection_name,
                query=list(query_vector),
                limit=top_k,
                with_payload=True,
                with_vectors=False,
            )
            results = getattr(resp, "points", resp)
        else:
            results = self.qdrant_client.search(
                collection_name=self.collection_name,
                query_vector=list(query_vector),
                limit=top_k,
                with_payload=True,
                with_vectors=False,
            )

        chunks: List[RetrievedChunk] = []
        for point in results:
            payload = getattr(point, "payload", None) or {}
            text = payload.get("text")
            chunk_id = payload.get("chunk_id")
            doc_id = payload.get("doc_id")
            score = float(getattr(point, "score", 0.0))

            if not text or not chunk_id or not doc_id:
                # Skip malformed payloads instead of crashing query path
                continue

            chunks.append(
                RetrievedChunk(
                    chunk_id=str(chunk_id),
                    doc_id=str(doc_id),
                    text=str(text),
                    score=score,
                    title=payload.get("title"),
                    source_s3_uri=payload.get("source_s3_uri"),
                )
            )

        return chunks
