FROM python:3.12-slim-bullseye AS builder

ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-dev

ADD . /app

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

FROM public.ecr.aws/docker/library/python:3.12.0-slim-bullseye AS app

COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 /lambda-adapter /opt/extensions/lambda-adapter

ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH="."

WORKDIR /app

COPY --from=builder /app /app

RUN chmod -R a+rX /app

CMD [ "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080" ]
