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
            "You are a helpful support assistant from eBay called eHelp."
            "Answer ONLY using the provided context. "
            "If the context is insufficient, say clearly that you do not have enough information in the provided knowledge base. "
            "Be factual and no more than one paragraph response."
            "Do not return Markdown as response, only text in plain conside english."
        )

        user_text = (
            f"User question:\n{question.strip()}\n\n"
            f"Retrieved context:\n{context if context else '[No context retrieved]'}\n\n"
            "Write the answer for the user."
        )

        messages = [
            {
                "role": "user",
                "content": [{"text": user_text}],
            }
        ]
        return system_prompt, messages
