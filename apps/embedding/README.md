
```sh
curl -sS -X PUT "$QDRANT_URL/collections/$QDRANT_COLLECTION" \
  -H "Content-Type: application/json" \
  -H "api-key: $QDRANT_API_KEY" \
  --data "{
    \"vectors\": {
      \"size\": 1024,
      \"distance\": \"Cosine\"
    }
  }"
```
