# applies Flannel CNI, Metal Load Balancer, and NGINX Ingress Controller
kubectl apply -f ./flannel/flannel.yaml
kubectl apply -f ./metallb/metallb-namespace.yaml
kubectl apply -f ./metallb/metallb.yaml
kubectl apply -f ./metallb/metallb-config.yaml
kubectl apply -f ./ingress-nginx/ingress-nginx-baremetal.yaml