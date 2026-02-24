## UV Stage (Just used to use the binary)
FROM ghcr.io/astral-sh/uv:0.10.4 AS uv

## Intermediate Stage
FROM public.ecr.aws/lambda/python:3.12 AS builder

ARG APP_DIR

ENV UV_COMPILE_BYTECODE=1
ENV UV_NO_INSTALLER_METADATA=1
ENV UV_LINK_MODE=copy

# Copy only dependency metadata first for better caching
WORKDIR /work/app
COPY ${APP_DIR}/pyproject.toml /work/app/pyproject.toml
COPY ${APP_DIR}/uv.lock /work/app/uv.lock
RUN mkdir -p /work/utils
COPY utils/ /work/utils/

RUN dnf install -y gcc gcc-c++ make && dnf clean all

# Install third-party dependencies (excluding workspace/local packages)
RUN --mount=from=uv,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/root/.cache/uv \
    uv export --frozen --no-emit-workspace --no-dev --no-editable -o requirements.txt && \
    uv pip install -r requirements.txt --target "${LAMBDA_TASK_ROOT}"

## Final Stage
FROM public.ecr.aws/lambda/python:3.12

ARG APP_DIR

# Copy dependencies from builder
COPY --from=builder ${LAMBDA_TASK_ROOT} ${LAMBDA_TASK_ROOT}

# Copy app code
COPY ${APP_DIR}/main.py ${LAMBDA_TASK_ROOT}/main.py

# Lambda handler
CMD ["main.lambda_handler"]
