#!/bin/sh

AWS_REGION=$1
AWS_ACCOUNT_ID=$2
ECR_NAME=$3
ECR_URI=$4
ARCHITECTURE=$5

TAG="bootstrap"

if [ "$ARCHITECTURE" = "arm64" ]; then
    ARCHITECTURE="linux/arm64"
elif [ "$ARCHITECTURE" = "x86_64" ]; then
    ARCHITECTURE="linux/amd64"
else
  echo "Architecture $ARCHITECTURE is not a valid architecture. Expected values: arm64, x86_64"
  exit 1
fi

aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
docker build -t bootstrap-lambda:placeholder \
    -f ./bootstrap-lambda/Dockerfile \
    --platform=$ARCHITECTURE \
    ./bootstrap-lambda
docker tag bootstrap-lambda:placeholder $ECR_URI:$TAG
docker push $ECR_URI:$TAG
sleep 5
