#!/usr/bin/env python3
"""Software to run apbs and pdb2pqr jobs."""

from argparse import ArgumentDefaultsHelpFormatter, ArgumentParser
from datetime import datetime
from enum import Enum
from json import dumps, loads, JSONDecodeError
from logging import basicConfig, getLogger, DEBUG, INFO, StreamHandler
from os import chdir, getenv, getpid, listdir, makedirs
from pathlib import Path
from resource import getrusage, RUSAGE_CHILDREN
from shutil import rmtree
import signal
from subprocess import run, CalledProcessError, PIPE
from time import sleep, time
from typing import Any, Dict, List, Optional
from urllib import request
from sys import stderr
import sys
import os
import json
import pathlib
import base64
import asyncio
import contextlib


from azure.storage.queue import QueueClient, QueueMessage
from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import ResourceNotFoundError
from azure.identity import DefaultAzureCredential

from dataclasses import dataclass


@dataclass
class Settings:
    job_path: os.PathLike = "/var/tmp/"
    log_level: int = INFO


# Global Environment Variables
GLOBAL_VARS = {
    "Q_TIMEOUT": None,
    "AWS_REGION": None,
    "MAX_TRIES": None,
    "RETRY_TIME": None,
    "LOG_LEVEL": INFO,
    "JOB_PATH": None,
    "S3_TOPLEVEL_BUCKET": None,
    "QUEUE": None,
}
_LOGGER = getLogger(__name__)
basicConfig(
    format=("[%(levelname)s] [%(filename)s:%(lineno)s:%(funcName)s()] %(message)s"),
    # level=GLOBAL_VARS["LOG_LEVEL"],
    handlers=[StreamHandler(stderr)],
)


# Default to start processing immediately
PROCESSING = True


class JOBTYPE(Enum):
    """The valid values for a job's type."""

    APBS = 1
    PDB2PQR = 2
    DRY = 3
    UNKNOWN = -1


class JOBSTATUS(Enum):
    """The valid values for a job's status."""

    COMPLETE = 1
    RUNNING = 2
    UNKNOWN = 3
    FAILED = 4


class Storage:
    """Wrapper around Azure Blob Storage."""

    def __init__(self, container_name: str, blob_service_client: BlobServiceClient):
        # self.container_client = container_client
        # self.container_name = container_client.container_name
        self.blob_service_client = blob_service_client
        self.container_client = blob_service_client.get_container_client(container_name)

    @staticmethod
    def _kwargs_from_env(container_name: str):
        credential = DefaultAzureCredential()
        storage_account_url = getenv("APBS_STORAGE_ACCOUNT_URL")
        if not storage_account_url:
            raise ValueError("APBS_STORAGE_ACCOUNT_URL is not set")
        return {
            "container_name": container_name,
            "blob_service_client": BlobServiceClient(
                storage_account_url, credential=credential
            ),
        }
        # connection_string = getenv("APBS_QUEUE_CONNECTION_STRING")
        # if not connection_string:
        #     raise ValueError("APBS_QUEUE_CONNECTION_STRING is not set")
        # return {"container_client": ContainerClient(connection_string, container_name)}

    @classmethod
    def from_environment(cls, container_name: str):
        return cls(**cls._kwargs_from_env(container_name))

    def update_from_environment(self):
        self.__dict__.update(self._kwargs_from_env(self.container_name))

    def download_file(self, key: str, filename: os.PathLike):
        with open(filename, "wb") as data:
            data.write(self.get_contents(key))

    def upload_file(
        self,
        filepath: os.PathLike,
        prefix: os.PathLike,
        name: os.PathLike,
        overwrite: bool = False,
    ):
        """Upload a file to the storage container.

        Args
        ----
        filename: os.PathLike
            The path to the file to upload.
        prefix: os.PathLike
            The prefix to add to the filename.
        overwrite: bool
            Whether to overwrite the file if it already exists.
        """
        blob = self.container_client.get_blob_client(f"{prefix}/{name}")
        _LOGGER.info(f"Uploading {filepath} to {prefix}/{name}")
        with open(filepath, "rb") as data:
            return blob.upload_blob(data, overwrite=overwrite)

    def get_contents(self, key: str):
        """Get the contents of a blob in the container.

        Args
        ----
        key: str
            The key of the blob to retrieve.

        Returns
        -------
        bytes
            The contents of the blob.

        Throws
        ------
        ResourceNotFoundError
            If the blob is not found in the container.

        """
        blob = self.container_client.get_blob_client(key)
        try:
            return blob.download_blob().readall()
        except ResourceNotFoundError as error:
            print(f"Can't find blob '{key}' in container '{self.container_name}'")
            raise

    def put_contents(self, key: str, data: bytes, overwrite: bool = False):
        blob = self.container_client.get_blob_client(key)
        return blob.upload_blob(data, overwrite=overwrite)


class Queue:
    """Wrapper around Azure Storage Queue."""

    def __init__(
        self,
        queue: QueueClient,
        max_tries: int,
        visibility_timeout: int,
        retry_time: int,
    ):
        self.queue = queue
        self.max_tries = max_tries
        self.visibility_timeout = visibility_timeout
        self.retry_time = retry_time

    def __repr__(self):
        return (
            f"Queue(queue={self.queue}, max_tries={self.max_tries}, "
            f"visibility_timeout={self.visibility_timeout}, "
            f"retry_time={self.retry_time})"
        )

    @staticmethod
    def _kwargs_from_env():
        credential = DefaultAzureCredential()
        storage_queue_name = getenv("APBS_QUEUE_NAME")
        if not storage_queue_name:
            raise ValueError("APBS_QUEUE_NAME is not set")
        queue_url = getenv("APBS_QUEUE_URL")
        if not queue_url:
            raise ValueError("APBS_QUEUE_URL is not set")
        queue_client = QueueClient(
            queue_url, queue_name=storage_queue_name, credential=credential
        )
        dct = {
            "queue": queue_client,
            "max_tries": int(getenv("MAX_TRIES", "60")),
            "retry_time": int(getenv("RETRY_TIME", "15")),
            "visibility_timeout": int(getenv("Q_TIMEOUT", "300")),
        }
        dct["max_tries"] = 3  # TODO DEBUG TESTING
        dct["retry_time"] = 1  # TODO DEBUG TESTING
        return dct

    @classmethod
    def from_environment(cls):
        return cls(**cls._kwargs_from_env())

    def update_from_environment(self):
        self.__dict__.update(self._kwargs_from_env())

    def extract_jobinfo(self, message):
        content = message.content
        decoded = base64.b64decode(content).decode("utf-8")
        try:
            return json.loads(decoded)
        except json.JSONDecodeError as error:
            _LOGGER.error(
                "ERROR: Unable to load json information for job, %s \n\t%s",
                decoded,
                error,
            )
            raise

    def mark_message_completed(self, message):
        self.queue.delete_message(message)

    def requeue_message(self, message):
        content = message.content
        self.queue.send_message(content)
        self.queue.delete_message(message)

    def set_visibility_timeout(self, message, timeout):
        self.queue.update_message(message, visibility_timeout=timeout)

    def _get_single_message(self):
        return self.queue.receive_message(visibility_timeout=self.visibility_timeout)

    def get_message(self):
        message = None
        tries = 0
        while message is None and tries < self.max_tries:
            tries += 1
            message = self._get_single_message()
            if message is None:
                _LOGGER.info(f"No message ({tries})")
                sleep(self.retry_time)

        return message


class JobMetrics:
    """
    A way to collect metrics from a subprocess.

    To get memory, we use resource.getrusage(RUSAGE_CHILDREN).
    To avoid accumulating the memory usage from all subprocesses
    we subtract the previous rusage values to get a delta for
    just the current subprocess.

    To get the time to run metrics we subtract the start time from
    the end time (e.g., {jobtype}_end_time - {jobtype}_start_time)

    To get the disk usage we sum up the stats of all the files in
    the output directory.

    The result for each job will to to output a file named:
        {jobtype}-metrics.json
    Where {jobtype} will be apbs or pdb2pqr.
    The contents of the file will be JSON and look like:
    {
        "metrics": {
            "rusage": {
                "ru_utime": 0.004102999999999999,
                "ru_stime": 0.062483999999999984,
                "ru_maxrss": 1003520,
                "ru_ixrss": 0,
                "ru_idrss": 0,
                "ru_isrss": 0,
                "ru_minflt": 823,
                "ru_majflt": 0,
                "ru_nswap": 0,
                "ru_inblock": 0,
                "ru_oublock": 0,
                "ru_msgsnd": 0,
                "ru_msgrcv": 0,
                "ru_nsignals": 0,
                "ru_nvcsw": 903,
                "ru_nivcsw": 4
            },
            "runtime_in_seconds": 262,
            "disk_storage_in_bytes": 4003345,
        },
    }
    """

    def __init__(self):
        """Capture the initial state of the resource usage."""
        metrics = getrusage(RUSAGE_CHILDREN)
        self.output_dir = None
        self._start_time = 0
        self._end_time = 0
        self.exit_code = None
        self.values: Dict = {}
        self.values["ru_utime"] = metrics.ru_utime
        self.values["ru_stime"] = metrics.ru_stime
        self.values["ru_maxrss"] = metrics.ru_maxrss
        self.values["ru_ixrss"] = metrics.ru_ixrss
        self.values["ru_idrss"] = metrics.ru_idrss
        self.values["ru_isrss"] = metrics.ru_isrss
        self.values["ru_minflt"] = metrics.ru_minflt
        self.values["ru_majflt"] = metrics.ru_majflt
        self.values["ru_nswap"] = metrics.ru_nswap
        self.values["ru_inblock"] = metrics.ru_inblock
        self.values["ru_oublock"] = metrics.ru_oublock
        self.values["ru_msgsnd"] = metrics.ru_msgsnd
        self.values["ru_msgrcv"] = metrics.ru_msgrcv
        self.values["ru_nsignals"] = metrics.ru_nsignals
        self.values["ru_nvcsw"] = metrics.ru_nvcsw
        self.values["ru_nivcsw"] = metrics.ru_nivcsw

    def get_rusage_delta(self):
        """
        Caluculate the difference between the last time getrusage
        was called and now.

        :param memory_disk_usage: Need to subtract out the files in memory.
        :return:  The rusage values as a dictionary
        :rtype:  Dict
        """
        metrics = getrusage(RUSAGE_CHILDREN)
        self.values["ru_utime"] = round(metrics.ru_utime - self.values["ru_utime"], 2)
        self.values["ru_stime"] = round(metrics.ru_stime - self.values["ru_stime"], 2)
        self.values["ru_maxrss"] = metrics.ru_maxrss - self.values["ru_maxrss"]
        self.values["ru_ixrss"] = metrics.ru_ixrss - self.values["ru_ixrss"]
        self.values["ru_idrss"] = metrics.ru_idrss - self.values["ru_idrss"]
        self.values["ru_isrss"] = metrics.ru_isrss - self.values["ru_isrss"]
        self.values["ru_minflt"] = metrics.ru_minflt - self.values["ru_minflt"]
        self.values["ru_majflt"] = metrics.ru_majflt - self.values["ru_majflt"]
        self.values["ru_nswap"] = metrics.ru_nswap - self.values["ru_nswap"]
        self.values["ru_inblock"] = metrics.ru_inblock - self.values["ru_inblock"]
        self.values["ru_oublock"] = metrics.ru_oublock - self.values["ru_oublock"]
        self.values["ru_msgsnd"] = metrics.ru_msgsnd - self.values["ru_msgsnd"]
        self.values["ru_msgrcv"] = metrics.ru_msgrcv - self.values["ru_msgrcv"]
        self.values["ru_nsignals"] = metrics.ru_nsignals - self.values["ru_nsignals"]
        self.values["ru_nvcsw"] = metrics.ru_nvcsw - self.values["ru_nvcsw"]
        self.values["ru_nivcsw"] = metrics.ru_nivcsw - self.values["ru_nivcsw"]
        return self.values

    def get_storage_usage(self):
        """Get the total number of bytes of the output files.

        Returns:
            int: The total bytes in all the files in the job directory
        """
        return sum(
            f.stat().st_size for f in self.output_dir.glob("**/*") if f.is_file()
        )

    @property
    def start_time(self):
        """The time the job started."""
        return self._start_time

    @start_time.setter
    def start_time(self, value):
        """Set the current time to denote that the job started."""
        self._start_time = value

    @property
    def end_time(self):
        """The time the job ended."""
        return self._end_time

    @end_time.setter
    def end_time(self, value):
        """Set the current time to denote that the job ended."""
        self._end_time = value

    @property
    def exit_code(self):
        """The exit code of the process."""
        return self._exit_code

    @exit_code.setter
    def exit_code(self, exit_code: int):
        """
        Set the exit code of the job executed.
        """
        self._exit_code = exit_code

    def get_metrics(self):
        """
        Create a dictionary of memory usage, execution time, and amount of
        disk storage used.

        Returns:
            Dict: A dictionary of (memory), execution time, and disk storage.
        """
        metrics = {
            "metrics": {"rusage": {}},
        }
        disk_usage = self.get_storage_usage()
        metrics["metrics"]["rusage"] = self.get_rusage_delta()
        metrics["metrics"]["runtime_in_seconds"] = round(
            self.end_time - self.start_time, 2
        )
        metrics["metrics"]["disk_storage_in_bytes"] = disk_usage
        metrics["metrics"]["exit_code"] = self.exit_code
        return metrics

    def write_metrics(self, job_tag: str, job_type: str, output_dir: str):
        """Get the metrics of the latest subprocess and create the output file.

        Args:
            job_type (str): Either "apbs" or "pdb2pqr".
            output_dir (str): The directory to find the output files.
        Returns:
            N/A
        """
        self.output_dir = Path(output_dir)
        metrics = self.get_metrics()
        _LOGGER.info(
            "%s %s METRICS: exit_code %s %s",
            job_tag,
            job_type.upper(),
            metrics["metrics"]["exit_code"],
            metrics,
        )
        with open(f"{job_type}-metrics.json", "w") as fout:
            fout.write(dumps(metrics, indent=4))


def print_current_state():
    # DWHS TODO -- see if this can be changed (remove globals?)
    for idx in sorted(GLOBAL_VARS):
        _LOGGER.info("VAR: %s, VALUE: %s", idx, GLOBAL_VARS[idx])
        print(f"VAR: {idx}, VALUE: set to: {GLOBAL_VARS[idx]}", file=stderr)
    _LOGGER.info("PROCESSING state: %s", PROCESSING)
    print(f"PROCESSING state: {PROCESSING}\n", file=stderr)


def receive_signal(signal_number, frame):
    _LOGGER.info("Received signal: %s, %s", signal_number, frame)
    print(f"Received signal: {signal_number}, {frame}", file=stderr)
    signal_help(signal_number, frame)


def signal_help(signal_number, frame):
    # pylint: disable=unused-argument
    print("\n", file=stderr)
    print(f"RECEIVED SIGNAL: {signal_number}\n\n", file=stderr)
    print("\tYou have asked for help:\n\n", file=stderr)
    print(
        f"\tTo update environment variables, type: kill -USR1 {getpid()}\n\n",
        file=stderr,
    )
    print(f"\tTo toggle processing, type: kill -USR2 {getpid()}\n\n", file=stderr)
    print_current_state()


def terminate_process(signal_number, frame):
    # pylint: disable=unused-argument
    print("Caught (SIGTERM) terminating the process\n", file=stderr)
    sys.exit()


def toggle_processing(signal_number, frame):
    # pylint: disable=unused-argument
    global PROCESSING
    PROCESSING = not PROCESSING
    _LOGGER.info("PROCESSING set to: %s", PROCESSING)
    print(f"PROCESSING set to:{PROCESSING}\n", file=stderr)


def update_environment(signal_number, frame):
    pass
    # DWHS TODO -- update to remove AWS-specific stuff
    # pylint: disable=unused-argument
    # TODO: This may need to be increased or calculated based
    #       on complexity of the job (dimension of molecule?)
    #       The job could get launched multiple times if the
    #       job takes longer than Q_TIMEOUT
    # global GLOBAL_VARS
    # GLOBAL_VARS["Q_TIMEOUT"] = int(getenv("SQS_QUEUE_TIMEOUT", "300"))
    # GLOBAL_VARS["AWS_REGION"] = getenv("SQS_AWS_REGION", "us-west-2")
    # GLOBAL_VARS["MAX_TRIES"] = int(getenv("SQS_MAX_TRIES", "60"))
    # GLOBAL_VARS["RETRY_TIME"] = int(getenv("SQS_RETRY_TIME", "15"))
    # GLOBAL_VARS["LOG_LEVEL"] = int(getenv("LOG_LEVEL", str(INFO)))
    # GLOBAL_VARS["JOB_PATH"] = getenv("JOB_PATH", "/var/tmp/")
    # GLOBAL_VARS["S3_TOPLEVEL_BUCKET"] = getenv("OUTPUT_BUCKET")
    # GLOBAL_VARS["QUEUE"] = getenv("JOB_QUEUE_NAME")
    # _LOGGER.setLevel(GLOBAL_VARS["LOG_LEVEL"])

    # if GLOBAL_VARS["S3_TOPLEVEL_BUCKET"] is None:
    # raise ValueError("Environment variable 'OUTPUT_BUCKET' is not set")
    # if GLOBAL_VARS["QUEUE"] is None:
    # raise ValueError("Environment variable 'JOB_QUEUE_NAME' is not set")


def get_messages(sqs, qurl: str) -> Any:
    # DWHS TODO -- this can probably be removed
    """Get SQS Messages from the queue.

    :param sqs:  S3 output bucket for the job being updated
    :type sqs:  boto3.client connection
    :param qurl:  URL for the SNS Queue to listen for new messages
    :return:  List of messages from the queue
    :rtype:  Any
    """
    loop = 0

    messages = sqs.receive_message(
        QueueUrl=qurl,
        MaxNumberOfMessages=1,
        VisibilityTimeout=GLOBAL_VARS["Q_TIMEOUT"],
    )

    while "Messages" not in messages:
        loop += 1
        if loop == GLOBAL_VARS["MAX_TRIES"]:
            return None
        _LOGGER.debug("Waiting ....")
        sleep(GLOBAL_VARS["RETRY_TIME"])
        messages = sqs.receive_message(
            QueueUrl=qurl,
            MaxNumberOfMessages=1,
            VisibilityTimeout=GLOBAL_VARS["Q_TIMEOUT"],
        )
    return messages


def update_status(
    output_storage: Storage,
    job_tag: str,
    jobtype: str,
    status: JOBSTATUS,
    output_files: List,
    message: Optional[str] = None,
) -> Dict:
    """Update the status file in the S3 bucket for the current job.

    :param s3:  S3 output bucket for the job being updated
    :param job_tag:  Unique ID for this job
    :param jobtype:  The job type (apbs, pdb2pqr, etc.)
    :param status:  The job status
    :param output_files:  List of output files
    :return:  Response from storing status file in S3 bucket
    :rtype:  Dict
    """
    # load current status from blob storage
    objectfile = f"{job_tag}/{jobtype}-status.json"
    storage_bytes = output_storage.get_contents(objectfile)
    statobj: dict = loads(storage_bytes.decode("utf-8"))

    # Update status and timestamps
    statobj[jobtype]["status"] = status.name.lower()
    if status == JOBSTATUS.COMPLETE or status == JOBSTATUS.FAILED:
        statobj[jobtype]["endTime"] = time()

    if status == JOBSTATUS.FAILED and message is not None:
        statobj[jobtype]["message"] = message

    statobj[jobtype]["outputFiles"] = output_files

    object_response = {}
    try:
        object_response: dict = output_storage.put_contents(
            objectfile,
            dumps(statobj),
            overwrite=True,
        )
    except Exception as error:
        _LOGGER.exception(
            "%s ERROR: Failed to update status file, %s \n\t%s",
            job_tag,
            objectfile,
            error,
        )

    return object_response


def cleanup_job(job_tag: str, rundir: str, settings: Settings) -> int:
    """Remove the directory for the job.

    :param rundir:  The local directory where the job is being executed.
    :return:  int
    """
    _LOGGER.info("%s Deleting run directory, %s", job_tag, rundir)
    chdir(settings.job_path)
    rmtree(rundir)
    return 1


async def read_stream(stream, is_stderr=False, output_file=None):
    while True:
        line = await stream.readline()
        if not line:
            break
        line_str = line.decode("utf-8").rstrip("\n")

        if is_stderr:
            print(line_str, file=sys.stderr, flush=True)
        else:
            print(line_str, file=sys.stdout, flush=True)

        if output_file:
            output_file.write(line_str + "\n")
            output_file.flush()


async def monitor_termination(process, stop_event):
    await stop_event.wait()
    print("Terminating process", flush=True)
    try:
        process.terminate()
        print("Sent SIGTERM, waiting for process to finish", flush=True)
        try:
            await asyncio.wait_for(process.wait(), timeout=5)
            print("Process finished", flush=True)
        except asyncio.TimeoutError:
            print("Process did not finish in time, killing it", flush=True)
            process.kill()
            await process.wait()
            print("Process killed", flush=True)
    except ProcessLookupError:
        print("Process already finished", flush=True)


async def handle_signal(stop_event):
    print("Received SIGTERM, stopping", flush=True)
    stop_event.set()


async def execute_command_async(
    job_tag: str,
    command_line_str: str,
    stdout_filename: str,
    stderr_filename: str,
    stop_event: asyncio.Event,
) -> int:
    """Spawn a subprocess and collect all the information about it.
    Returns the exit code the of the executed command.

    Args:
        job_tag (str): The unique job id.
        command_line_str (str): The command and arguments.
        stdout_filename (str): The name of the output file for stdout.
        stderr_filename (str): The name of the output file for stderr.
    Return:
        exit_code (int): The exit code of the executed command

    """
    command_split = command_line_str.split()
    process = await asyncio.create_subprocess_exec(
        *command_split,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    termination_task = asyncio.create_task(monitor_termination(process, stop_event))
    with contextlib.ExitStack() as stack:
        files = [
            stack.enter_context(open(file, "w"))
            for file in (stdout_filename, stderr_filename)
        ]
        stdout_task = asyncio.create_task(read_stream(process.stdout, False, files[0]))
        stderr_task = asyncio.create_task(read_stream(process.stderr, True, files[1]))

        done, pending = await asyncio.wait(
            [stdout_task, stderr_task, termination_task],
            return_when=asyncio.FIRST_COMPLETED,
        )

        if termination_task in done:
            print("Termination task requested, cancelling...", flush=True)
            for task in pending:
                task.cancel()
            try:
                await asyncio.gather(*pending, return_exceptions=True)
            except asyncio.CancelledError:
                pass
            return 130

    code = await process.wait()
    if code != 0:
        _LOGGER.exception(f"{job_tag} failed to run command, {command_line_str}")

    return code


def get_job_info(
    job: str,
) -> Dict:
    """Get the job information from the SQS message.

    :param job:  The job file describing what needs to be run.
    :param s3client:  S3 input bucket with input files.
    :return:  dict
    """
    job_info: dict
    try:
        decoded = base64.b64decode(job).decode("utf-8")
        job_info = loads(decoded)
        if "job_date" not in job_info:
            _LOGGER.error("ERROR: Missing job date for job, %s", job)
            job_info = {}
        if "job_id" not in job_info:
            _LOGGER.error("ERROR: Missing job id for job, %s", job)
            job_info = {}
    except JSONDecodeError as error:
        _LOGGER.error(
            "ERROR: Unable to load json information for job, %s \n\t%s", job, error
        )
        job_info = {}
    return job_info


# TODO: intendo - 2021/05/10 - Break run_job into multiple functions
#                              to reduce complexity.
async def run_job(
    message: QueueMessage,
    output_storage: Storage,
    input_storage: Storage,
    metrics: JobMetrics,
    settings: Settings,
    stop_event: asyncio.Event,
) -> int:
    """Run the job described in the queue message.

    Args:
        message (QueueMessage): The message from the queue.
        output_storage (Storage): The storage for output files.
        input_storage (Storage): The storage for input files.
        metrics (JobMetrics): The metrics for the job.
        settings (Settings): The settings for the job.
        stop_event (asyncio.Event): The event to stop the job.
    Return:
        int: The exit code of the job.
    """
    job = message.content
    ret_val = 1
    job_info = get_job_info(job)
    if not job_info:
        return ret_val

    job_type = job_info["job_type"]
    job_tag = f"{job_info['job_date']}/{job_info['job_id']}"
    rundir = pathlib.Path(settings.job_path) / job_tag

    # Prepare job directory and download input files
    makedirs(rundir, exist_ok=True)
    chdir(rundir)

    for file in job_info["input_files"]:
        if "https" in file:
            name = f"{job_tag}/{file.split('/')[-1]}"
            try:
                request.urlretrieve(file, f"{settings.job_path}/{name}")
            except Exception as error:
                # TODO: intendo 2021/05/05 - Find more specific exception
                _LOGGER.exception(
                    "%s ERROR: Download failed for file, %s \n\t%s",
                    job_tag,
                    name,
                    error,
                )
                update_status(
                    output_storage,
                    job_tag,
                    job_type,
                    JOBSTATUS.FAILED,
                    [],
                    "Failed to download input file. Job did not run.",
                )
                return cleanup_job(job_tag, rundir, settings)

        else:
            try:
                # DWHS: TODO -- check where this downloads to
                _LOGGER.info(f"Downloading file, {file} to {file}")
                input_storage.download_file(file, Path(file).name)
                # s3client.download_file(
                #     inbucket, file, f"{GLOBAL_VARS['JOB_PATH']}{file}"
                # )
            except Exception as error:
                # TODO: intendo 2021/05/05 - Find more specific exception
                _LOGGER.exception(
                    "%s ERROR: Download failed for file, %s \n\t%s",
                    job_tag,
                    file,
                    error,
                )
                update_status(
                    output_storage,
                    job_tag,
                    job_type,
                    JOBSTATUS.FAILED,
                    [],
                    "Failed to download input file. Job did not run.",
                )
                return cleanup_job(job_tag, rundir, settings)

    # Run job and record associated metrics
    update_status(
        output_storage,
        job_tag,
        job_type,
        JOBSTATUS.RUNNING,
        [],
    )

    # TODO: (Eo300) consider moving binary
    #       command (e.g. 'apbs', 'pdb2pqr30') into SQS message
    if JOBTYPE.APBS.name.lower() in job_type:
        command = f"apbs {job_info['command_line_args']}"
    elif JOBTYPE.PDB2PQR.name.lower() in job_type:
        command = f"pdb2pqr30 {job_info['command_line_args']}"
    elif JOBTYPE.DRY.name.lower() in job_type:
        command = f"echo '{job_info}'"
    else:
        raise KeyError(f"Invalid job type, {job_type}")

    # DWHS TODO -- move this elsewhere
    # if "max_run_time" in job_info:
    #     sqs = client("sqs", region_name=GLOBAL_VARS["AWS_REGION"])
    #     sqs.change_message_visibility(
    #         QueueUrl=queue_url,
    #         ReceiptHandle=receipt_handle,
    #         VisibilityTimeout=int(job_info["max_run_time"]),
    #     )

    # Execute job binary with appropriate arguments and record metrics
    try:
        metrics.start_time = time()
        metrics.exit_code = await execute_command_async(
            job_tag,
            command,
            f"{job_type}.stdout.txt",
            f"{job_type}.stderr.txt",
            stop_event,
        )
        metrics.end_time = time()
        # We need to create the {job_type}-metrics.json before we upload
        # the files to the S3_TOPLEVEL_BUCKET.
        metrics.write_metrics(job_tag, job_type, ".")
    except Exception as error:
        # TODO: intendo 2021/05/05 - Find more specific exception
        _LOGGER.exception(
            "%s ERROR: Failed to execute job: %s",
            job_tag,
            error,
        )
        # TODO: Should this return 1 because noone else will succeed?
        ret_val = 1

    # Upload directory contents to S3
    for file in listdir("."):
        try:
            file_path = f"{job_tag}/{file}"
            _LOGGER.info("%s Uploading file to output bucket, %s", job_tag, file)
            output_storage.upload_file(
                filepath=os.path.join(settings.job_path, file_path),
                prefix=job_tag,
                name=file,
            )
            # output_storage.upload_file(
            #     os.path.join(settings.job_path, file_path), file_path
            # )
        except Exception as error:
            _LOGGER.exception(
                "%s ERROR: Failed to upload file, %s \n\t%s",
                job_tag,
                f"{job_tag}/{file}",
                error,
            )
            ret_val = 1

    # TODO: 2021/03/30, Elvis - Will need to address how we bundle output
    #       subdirectory for PDB2PKA when used; I previous bundled it as
    #       a compressed tarball (i.e. "{job_id}-pdb2pka_output.tar.gz")

    # Create list of output files
    input_files_no_id = [  # Remove job_id prefix from input file list
        "".join(name.split("/")[-1]) for name in job_info["input_files"]
    ]
    output_files = [
        f"{job_tag}/{filename}"
        for filename in listdir(".")
        if filename not in input_files_no_id
    ]

    # Cleanup job directory and update status
    cleanup_job(job_tag, rundir, settings)
    if metrics.exit_code != 0:
        update_status(
            output_storage,
            job_tag,
            job_type,
            JOBSTATUS.FAILED,
            output_files,
            "Job failed to run.",
        )
    else:
        update_status(
            output_storage,
            job_tag,
            job_type,
            JOBSTATUS.COMPLETE,
            output_files,
        )

    return metrics.exit_code


def dry_run(jobinfo, inputs, outputs: Storage, metrics):
    job_tag = f"{jobinfo['job_date']}/{jobinfo['job_id']}"
    update_status(
        outputs,
        job_tag,
        jobinfo["job_type"],
        JOBSTATUS.RUNNING,
        [],
    )

    with open("jobinfo.json", "w") as fout:
        fout.write(dumps(jobinfo, indent=4))

    # outputs.upload_file("jobinfo.json", jobinfo["job_id"])
    outputs.upload_file(
        filepath="jobinfo.json",
        prefix=job_tag,
        name="jobinfo.json",
    )
    print(jobinfo)


async def main() -> int:
    stop_event = asyncio.Event()
    loop = asyncio.get_event_loop()
    loop.add_signal_handler(
        signal.SIGTERM, lambda: asyncio.create_task(handle_signal(stop_event))
    )
    lasttime = datetime.now()
    queue = Queue.from_environment()
    inputs = Storage.from_environment("inputs")
    outputs = Storage.from_environment("outputs")
    settings = Settings()
    metrics = JobMetrics()
    while message := queue.get_message():
        code = await run_job(message, outputs, inputs, metrics, settings, stop_event)
        # 130 is the exit code for a SIGTERM signal and we want to requeue the message
        if code == 130:
            _LOGGER.info("SIGTERM received, requeuing message")
            queue.requeue_message(message)
            _LOGGER.info("DONE: %s", str(datetime.now() - lasttime))
            return 130
        queue.mark_message_completed(message)
        while not PROCESSING:
            sleep(10)

    _LOGGER.info("DONE: %s", str(datetime.now() - lasttime))
    return 0


if __name__ == "__main__":
    _LOGGER.setLevel(INFO)
    sys.exit(asyncio.run(main()))
    # main()
