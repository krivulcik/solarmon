import logging
import os
import re

from influxdb_client import InfluxDBClient
from influxdb_client.client.write_api import SYNCHRONOUS

from mppsolar.outputs.baseoutput import baseoutput
from mppsolar.helpers import get_kwargs, key_wanted

log = logging.getLogger("influx2")

INFLUXDB_URL = os.environ.get("INFLUXDB_URL", "http://localhost:8086")
INFLUXDB_TOKEN = os.environ.get("INFLUXDB_TOKEN", "")
INFLUXDB_ORG = os.environ.get("INFLUXDB_ORG", "home")
INFLUXDB_BUCKET = os.environ.get("INFLUXDB_BUCKET", "solar")


class influx2(baseoutput):
    def __str__(self):
        return "outputs the results to InfluxDB 2.x"

    def __init__(self, *args, **kwargs):
        log.debug(f"__init__: kwargs {kwargs}")

    def output(self, *args, **kwargs):
        log.info("Using output processor: influx2")
        log.debug(f"kwargs {kwargs}")

        data = get_kwargs(kwargs, "data")
        keep_case = get_kwargs(kwargs, "keep_case")
        data.pop("raw_response", None)

        filter = get_kwargs(kwargs, "filter")
        if filter is not None:
            filter = re.compile(filter)
        excl_filter = get_kwargs(kwargs, "excl_filter")
        if excl_filter is not None:
            excl_filter = re.compile(excl_filter)

        fields = {}
        for key in data:
            value = data[key]
            if isinstance(value, list):
                value = data[key][0]
            key = key.replace(" ", "_")
            key = key.replace("Device_Mode", "mode")
            if not keep_case:
                key = key.lower()
            if key_wanted(key, filter, excl_filter):
                fields[key] = value

        record = {
            "measurement": "easun_3kw",
            "tags": {"sensor": "easun_3kw"},
            "fields": fields,
        }

        client = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)
        try:
            write_api = client.write_api(write_options=SYNCHRONOUS)
            write_api.write(bucket=INFLUXDB_BUCKET, org=INFLUXDB_ORG, record=record)
        finally:
            client.close()
