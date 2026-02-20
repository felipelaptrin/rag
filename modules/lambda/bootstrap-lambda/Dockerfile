FROM public.ecr.aws/lambda/python:3.13

RUN groupadd -g 10001 app \
 && useradd  -u 10001 -g app -m -s /sbin/nologin app \
 && chown -R app:app ${LAMBDA_TASK_ROOT}

COPY --chown=app:app main.py ${LAMBDA_TASK_ROOT}/main.py

USER app

CMD [ "main.lambda_handler" ]
