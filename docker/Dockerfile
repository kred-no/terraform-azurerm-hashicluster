FROM hashicorp/terraform:light

WORKDIR /run/tf
COPY . .

ENV ARM_SUBSCRIPTION_ID= \
    ARM_TENANT_ID=

RUN set -x \
  && terraform init \
  && terraform validate
