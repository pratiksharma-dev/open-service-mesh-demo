# Install OSM to AKS cluster
$RESOURCE_GROUP="ESLZ-SPOKE"
$AKS_NAME="eslzakscluster"
az aks addon enable --addon open-service-mesh `
  --resource-group $RESOURCE_GROUP `
  --name $AKS_NAME

# Build docker Images
docker build -t bookbuyer bookbuyer/.
docker build -t bookthief bookthief/.
docker build -t bookstore bookstore/.

# Tag images to ACR
docker tag book-buyer eslzacryhl4sttxid2gu.azurecr.io/osm-demo/book-buyer
docker tag book-theif eslzacryhl4sttxid2gu.azurecr.io/osm-demo/book-thief
docker tag bookstore eslzacryhl4sttxid2gu.azurecr.io/osm-demo/bookstore

# Push Images to ACR
docker push eslzacryhl4sttxid2gu.azurecr.io/osm-demo/book-buyer
docker push eslzacryhl4sttxid2gu.azurecr.io/osm-demo/book-thief
docker push eslzacryhl4sttxid2gu.azurecr.io/osm-demo/bookstore

# Deploy images to kubernetes
kubectl apply -f manifests/.
kubectl apply -f .\manifests\ubuntu2.yaml -n ingress-nginx

# Install OSM CLI
$OSM_VERSION="v1.0.0"
[Net.ServicePointManager]::SecurityProtocol = "tls12"
$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -URI "https://github.com/openservicemesh/osm/releases/download/$OSM_VERSION/osm-$OSM_VERSION-windows-amd64.zip" -OutFile "osm-$OSM_VERSION.zip"
Expand-Archive -Path "osm-$OSM_VERSION.zip" -DestinationPath .
copy ./windows-amd64/osm.exe . 

# Now we enable osm for their namespaces
.\osm namespace add bookstore bookbuyer bookthief
# Check what namespaces are monitored by osm
.\osm namespace list

kubectl describe ns bookstore
kubectl describe ns bookbuyer
kubectl describe ns bookthief

# Check side-car injection in containers
kubectl get pods -n bookstore
kubectl get pods -n bookbuyer
kubectl get pods -n bookthief

# As observved only 1 container is running in each pod. Injection will happen only after redeployment
kubectl rollout restart deployment/bookthief -n bookthief
kubectl get pods -n bookthief

kubectl rollout restart deployment/bookbuyer -n bookbuyer
kubectl get pods -n bookbuyer

kubectl rollout restart deployment/bookstore -n bookstore
kubectl get pods -n bookstore

# Configure nginx ingress controller
kubectl create ns ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install osm-nginx-ingess ingress-nginx/ingress-nginx --namespace ingress-nginx

# Copy the ingress IP to replace in manifiest under ingress/. and then apply them
kubectl apply -f ingress/.

## Disable traffic access between pods

# Check permissive mode
kubectl get meshconfig osm-mesh-config -n kube-system -o jsonpath='{.spec.traffic.enablePermissiveTrafficPolicyMode}'

# Change to permissive mode to false
kubectl patch meshconfig osm-mesh-config -n kube-system -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":false}}}'  --type=merge

# Now you need to create traffic policies
kubectl apply -f traffic-access/.

.\osm install `
--mesh-name "osm-mesh-config" `
--osm-namespace "kube-system" `
--set=osm.enablePermissiveTrafficPolicy=false `
--set=osm.deployPrometheus=true `
--set=osm.deployGrafana=true `
--set=osm.deployJaeger=true

# Enable metrics scrapping
.\osm metrics enable --namespace bookstore
.\osm metrics enable --namespace bookbuyer
.\osm metrics enable --namespace bookthief

# Access to Grafana
.\osm dashboard --osm-namespace kube-system
