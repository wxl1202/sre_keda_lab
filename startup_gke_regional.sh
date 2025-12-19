#!/usr/bin/env bash

echo "preparing..."
export GCLOUD_PROJECT=$(gcloud config get-value project)
export INSTANCE_REGION=asia-east1
export INSTANCE_ZONE=asia-east1-b
export INSTANCE_REGION=asia-east1
export PROJECT_NAME=gke-poc
export CLUSTER_NAME=${PROJECT_NAME}-cluster
export NUM_NODES=1
#export CONTAINER_NAME=${PROJECT_NAME}-container

echo "setup"
gcloud config set compute/zone ${INSTANCE_ZONE}

echo "enable services"
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com

echo "creating container engine cluster - spot"
gcloud container clusters create ${CLUSTER_NAME} \
    --region ${INSTANCE_REGION} \
    --scopes cloud-platform \
    --enable-autorepair \
    --enable-autoupgrade \
    --enable-ip-alias \
    --enable-autoscaling --min-nodes 0 --max-nodes 1 \
    --machine-type e2-medium \
    --cluster-version 1.33.5-gke.1162000 \
    --spot

# echo "create spot vm node pool"
gcloud container node-pools create e2m-spot-pool \
    --cluster ${CLUSTER_NAME} \
    --region ${INSTANCE_REGION} \
    --machine-type e2-medium \
    --enable-autoscaling --min-nodes 0 --max-nodes 1 \
    --spot \
    --scopes cloud-platform

# echo "Create node pool"
# gcloud container node-pools create np-e2m --cluster ${CLUSTER_NAME} --enable-autoscaling --min-nodes 0 --max-nodes 2 --num-nodes 1 --region ${INSTANCE_REGION}

echo "Delete default pool"
gcloud container node-pools delete default-pool --cluster ${CLUSTER_NAME} --region ${INSTANCE_REGION} --quiet

echo "confirm cluster is running"
gcloud container clusters list

echo "get credentials"
gcloud container clusters get-credentials ${CLUSTER_NAME} \
    --zone ${INSTANCE_ZONE}

echo "confirm connection to cluster"
kubectl cluster-info

echo "create cluster administrator"
kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin --user=$(gcloud config get-value account)

echo "confirm the pod is running"
kubectl get pods

echo "list production services"
kubectl get svc

echo "enable services"
gcloud services enable cloudbuild.googleapis.com
