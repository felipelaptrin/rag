import json
from typing import List


class EmbeddingService:
    def __init__(self, bedrock_runtime, model_id: str) -> None:
        self.bedrock_runtime = bedrock_runtime
        self.model_id = model_id

    def embed_query(self, text: str) -> List[float]:
        body = {"inputText": text}

        response = self.bedrock_runtime.invoke_model(
            modelId=self.model_id,
            body=json.dumps(body),
            contentType="application/json",
            accept="application/json",
        )

        payload = json.loads(response["body"].read())
        embedding = payload.get("embedding")

        if embedding is None or not isinstance(embedding, list) or not embedding:
            raise RuntimeError(
                f"Invalid embedding response from Bedrock. keys={list(payload.keys())}"
            )

        return embedding
