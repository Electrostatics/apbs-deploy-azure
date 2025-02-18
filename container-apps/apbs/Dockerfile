# REQUIRED ENVIRONMENT VARIABLES (SET IN TERRAFORM):
# - APBS_QUEUE_CONNECTION_STRING
# - APBS_QUEUE_NAME
# We install the debiang version of the container
FROM python:3.11-bookworm

ARG APBS_VERSION=3.3.0

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt
RUN apt-get update -y \
    && apt-get install wget zip libgomp1 dumb-init -y \
    && wget https://github.com/Electrostatics/apbs/releases/download/v${APBS_VERSION}/APBS-${APBS_VERSION}.Linux.zip \
    && unzip APBS-${APBS_VERSION}.Linux.zip \
    && rm APBS-${APBS_VERSION}.Linux.zip \
    && rm -r APBS-${APBS_VERSION}.Linux/share/apbs/examples \
    && apt remove zip wget -y \
    && apt-get autoremove -y \
    && apt-get clean -y

ENV LD_LIBRARY_PATH=/app/APBS-${APBS_VERSION}.Linux/lib
ENV PATH="${PATH}:/app/APBS-${APBS_VERSION}.Linux/bin"

COPY job_control.py /app/
RUN chmod +x /app/job_control.py
WORKDIR /app/run

ENTRYPOINT [ "/usr/bin/dumb-init", "--" ]
CMD [ "/app/job_control.py" ]
