FROM public.ecr.aws/lambda/python:3.13

COPY main.py ${LAMBDA_TASK_ROOT}/main.py

USER app

CMD [ "main.lambda_handler" ]
