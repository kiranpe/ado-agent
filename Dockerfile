### Dockerfile
FROM registry.access.redhat.com/ubi9/ubi

RUN yum -y update && \
    yum -y install curl sudo jq libcurl unzip git tar hostname which shadow-utils \
    gpg ca-certificates gcc glibc-langpack-en && \
    yum clean all

# Install gcloud CLI
RUN echo "[google-cloud-sdk]" > /etc/yum.repos.d/google-cloud-sdk.repo && \
    echo "name=Google Cloud SDK" >> /etc/yum.repos.d/google-cloud-sdk.repo && \
    echo "baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64" >> /etc/yum.repos.d/google-cloud-sdk.repo && \
    echo "enabled=1" >> /etc/yum.repos.d/google-cloud-sdk.repo && \
    echo "gpgcheck=1" >> /etc/yum.repos.d/google-cloud-sdk.repo && \
    echo "repo_gpgcheck=1" >> /etc/yum.repos.d/google-cloud-sdk.repo && \
    echo "gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg" >> /etc/yum.repos.d/google-cloud-sdk.repo

RUN yum -y install google-cloud-sdk && yum -y install kubectl

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

RUN useradd adoagent
USER adoagent
WORKDIR /ado-agent

ENV AGENT_VERSION=3.240.1

RUN curl -O https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz && \
    tar zxvf vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz

COPY entrypoint.sh .

ENTRYPOINT ["./entrypoint.sh"]


### entrypoint.sh
#!/bin/bash
set -e

# Use Workload Identity Federation credentials
export GOOGLE_APPLICATION_CREDENTIALS=/home/adoagent/wif-creds.json
gcloud auth login --cred-file="$GOOGLE_APPLICATION_CREDENTIALS"

# Pull PAT token securely from Secret Manager
export ADO_PAT=$(gcloud secrets versions access latest --secret=ado-pat-token)

./config.sh --unattended \
  --url "$ADO_ORG_URL" \
  --auth pat \
  --token "$ADO_PAT" \
  --pool "$ADO_POOL" \
  --agent "$AGENT_NAME" \
  --acceptTeeEula \
  --replace

trap './config.sh remove --unattended --auth pat --token "$ADO_PAT"' EXIT

./svc.sh install
./svc.sh start

while true; do sleep 30; done

#Docker run
docker build -t ado-agent .

docker run -d --name ado-agent-1 \
  -e ADO_ORG_URL="https://dev.azure.com/<your-org>" \
  -e ADO_PAT="<your-pat>" \
  -e ADO_POOL="Default" \
  -e AGENT_NAME="bastion-agent-docker-1" \
  ado-agent



