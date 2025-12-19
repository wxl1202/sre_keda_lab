#!/bin/bash

PROJECT_ID="gcp-poc-384805"

for num in {1..20}
do
  gcloud pubsub topics publish keda-echo --project=${PROJECT_ID} --message="Test"
done