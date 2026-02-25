import logging
from typing import Generator

logger = logging.getLogger(__name__)


class GenerationService:
    """
    Streams text from Bedrock using ConverseStream.
    This is a good default because it is more model-portable inside Bedrock than
    hand-coding provider-specific invoke_model_with_response_stream payloads.
    """

    def __init__(
        self,
        bedrock_runtime,
        model_id: str,
        temperature: float,
        max_tokens: int,
    ) -> None:
        self.bedrock_runtime = bedrock_runtime
        self.model_id = model_id
        self.temperature = temperature
        self.max_tokens = max_tokens

    def stream_answer(
        self,
        system_prompt: str,
        messages: list[dict],
    ) -> Generator[str, None, None]:
        response = self.bedrock_runtime.converse_stream(
            modelId=self.model_id,
            system=[{"text": system_prompt}],
            messages=messages,
            inferenceConfig={
                "temperature": self.temperature,
                "maxTokens": self.max_tokens,
            },
        )

        stream = response.get("stream")
        if stream is None:
            raise RuntimeError("Bedrock converse_stream response missing 'stream'")

        # Event stream format includes multiple event types.
        # We emit only text deltas to the client.
        for event in stream:
            if "contentBlockDelta" in event:
                delta = event["contentBlockDelta"].get("delta", {})
                text = delta.get("text")
                if text:
                    logger.info("Generated chunk: %s", text)
                    yield text
            elif "messageStop" in event:
                # Normal end of generation
                return
            elif "metadata" in event:
                # Token usage / metrics may appear here. Ignore for now.
                continue
            elif "internalServerException" in event:
                raise RuntimeError(f"Bedrock internal server exception: {event}")
            elif "validationException" in event:
                raise RuntimeError(f"Bedrock validation exception: {event}")
            elif "throttlingException" in event:
                raise RuntimeError(f"Bedrock throttling exception: {event}")
            elif "modelStreamErrorException" in event:
                raise RuntimeError(f"Bedrock model stream error: {event}")
            # Other events can be safely ignored for now.
