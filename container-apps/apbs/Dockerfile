# REQUIRED ENVIRONMENT VARIABLES (SET IN TERRAFORM):
# - APBS_QUEUE_CONNECTION_STRING
# - APBS_QUEUE_NAME
FROM python:3.11

RUN python -m pip install azure-storage-blob azure-storage-queue

#COPY azure_job_control.py /app/azure_job_control.py
#RUN chmod +x /app/azure_job_control.py
#ENTRYPOINT [ "/app/azure_job_control.py" ]

COPY job_control.py /app/job_control.py
RUN chmod +x /app/job_control.py
ENTRYPOINT [ "/app/job_control.py" ]
