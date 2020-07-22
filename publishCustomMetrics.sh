#!/bin/bash

# Write logs to /tmp/customMetrics.log
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>>/tmp/customMetrics.log 2>&1
date

# OCI CLI binary location
# Default installation location for Oracle Linux 7 is /home/opc/bin/oci
cliLocation="/root/bin/oci"

# Check if OCI CLI, jq, and curl is installed
if ! [ -x "$(command -v $cliLocation)" ]; then
  echo 'Error: OCI CLI is not installed. Please follow the instructions in this link: https://docs.cloud.oracle.com/iaas/Content/API/SDKDocs/cliinstall.htm' >&2
  exit 1
fi

if ! [ -x "$(command -v jq)" ]; then
  echo 'Error: jq is not installed.' >&2
  exit 1
fi

if ! [ -x "$(command -v curl)" ]; then
  echo 'Error: curl is not installed.' >&2
  exit 1
fi

# Getting instance metadata. For more information, check this link: https://docs.cloud.oracle.com/iaas/Content/Compute/Tasks/gettingmetadata.htm
# By default, metrics are published to the same compartment with the instance being monitored. You may change the following variables if you want to use different values.
compartmentId=$(curl -s -L http://169.254.169.254/opc/v1/instance/ | jq -r '.compartmentId')
metricNamespace="mycustomnamespace"
metricResourceGroup="mycustomnamespace_rg"
instanceName=$(curl -s -L http://169.254.169.254/opc/v1/instance/ | jq -r '.displayName')
instanceId=$(curl -s -L http://169.254.169.254/opc/v1/instance/ | jq -r '.id')
endpointRegion=$(curl -s -L http://169.254.169.254/opc/v1/instance/ | jq -r '.canonicalRegionName')

# Getting disk utilization data and converting it to OCI monitoring compliant values.
Timestamp=$(date --rfc-3339=seconds | sed 's/ /T/')
diskUtilization=$(df -h / | awk '{print $6,$5}' | awk '{print $2}' | tail -1 | cut -c 1)

metricsJson=$(cat << EOF > /tmp/metrics.json
[
   {
      "namespace":"$metricNamespace",
      "compartmentId":"$compartmentId",
      "resourceGroup":"$metricResourceGroup",
      "name":"diskUtilization",
      "dimensions":{
         "resourceId":"$instanceId",
         "instanceName":"$instanceName"
      },
      "metadata":{
         "unit":"Percent",
         "displayName":"Disc_Utilization"
      },
      "datapoints":[
         {
            "timestamp":"$Timestamp",
            "value":$diskUtilization
         }
      ]
   }
]
EOF
)

$cliLocation monitoring metric-data post --metric-data file:///tmp/metrics.json --endpoint https://telemetry-ingestion.$endpointRegion.oraclecloud.com
