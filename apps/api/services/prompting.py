from typing import List

from services.retrieval import RetrievedChunk


def _normalize_ws(text: str) -> str:
    return "\n".join(
        line.rstrip() for line in text.replace("\r\n", "\n").split("\n")
    ).strip()


class PromptBuilder:
    def __init__(self, max_context_chunks: int, max_context_chars: int) -> None:
        self.max_context_chunks = max_context_chunks
        self.max_context_chars = max_context_chars

    def build_context(self, chunks: List[RetrievedChunk]) -> str:
        selected = chunks[: self.max_context_chunks]

        parts: list[str] = []
        current_chars = 0

        for i, chunk in enumerate(selected, start=1):
            text = _normalize_ws(chunk.text)
            header = f"[Context {i}]"
            block = f"{header}\n{text}\n"
            if current_chars + len(block) > self.max_context_chars:
                break
            parts.append(block)
            current_chars += len(block)

        return "\n".join(parts).strip()

    def build_messages_for_bedrock_converse(
        self,
        question: str,
        chunks: List[RetrievedChunk],
    ) -> tuple[str, list[dict]]:
        """
        Returns (system_prompt, messages) for Bedrock Converse/ConverseStream.
        """
        context = self.build_context(chunks)

        system_prompt = (
            "You are answering questions using only the provided eBay help-center context. "
            "Treat the context as the only allowed source of truth. "
            "If the answer is not clearly supported by the context, say: "
            "'I do not have enough information in the provided knowledge base to answer that clearly.' "
            "Do not guess. "
            "Do not invent UI steps, actions, deadlines, or policies. "
            "Do not combine buyer and seller flows unless the context explicitly says both apply. "
            "If the user question is buyer-specific, prefer buyer instructions. "
            "If the user question is seller-specific, prefer seller instructions. "
            "If the role is unclear and the context differs by role, say so. "
            "Ignore irrelevant context. "
            "Return only plain English text, short and factual, in one paragraph."
        )

        user_text = (
            f"Question: {question.strip()}\n\n"
            f"Context:\n{context if context else '[No context retrieved]'}\n\n"
            "Answer the question using only the context above."
        )

        messages = [
            {
                "role": "user",
                "content": [{"text": user_text}],
            }
        ]
        return system_prompt, messages
