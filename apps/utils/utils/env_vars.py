import os
from typing import List


def validate_required_env(env_vars: List[str]) -> None:
    missing = []
    for env_var in env_vars:
        if not os.getenv(env_var):
            missing.append(env_var)

    if missing:
        raise ValueError(
            f"Missing required environment variables: {', '.join(missing)}"
        )
