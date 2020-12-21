#!/bin/sh
# deploys Flannel CNI, Metal Load Balancer, NGINX Ingress Controller, and Fluent Bit to K8s cluster
kubectl apply -f ./flannel/flannel.yaml
kubectl apply -f ./metallb/metallb-namespace.yaml
kubectl apply -f ./metallb/metallb.yaml
kubectl apply -f ./metallb/metallb-config.yaml
kubectl apply -f ./ingress-nginx/ingress-nginx-baremetal.yaml
kubectl apply -f ./fluent-bit/fluent-bit-namespace.yaml
kubectl apply -f ./fluent-bit/fluent-bit-service-account.yaml
kubectl apply -f ./fluent-bit/fluent-bit-role.yaml
kubectl apply -f ./fluent-bit/fluent-bit-role-binding.yaml
kubectl apply -f ./fluent-bit/fluent-bit-configmap.yaml
kubectl apply -f ./fluent-bit/fluent-bit-daemon-set.yaml
