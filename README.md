# My k8s cluster (poiuytre.nl)

Kubernetes cluster based on k3s for my pet projects 

It also runs docker on a machine that  will be used as a proxy to the master nodes and as a container registry to my projects

---

## Distro Setup (Ubuntu Server)

### Prevent machine from sleeping 

```
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### Turn display off

Create paste the following content into the file

```
sudo vim /etc/systemd/system/enable-console-blanking.service
```

```
[Unit]
Description=Enable virtual console blanking

[Service]
Type=oneshot
Environment=TERM=linux
StandardOutput=tty
TTYPath=/dev/console
ExecStart=/usr/bin/setterm -blank 1

[Install]
WantedBy=multi-user.target
```

Change its permission and enable the service

```
sudo chmod 664 /etc/systemd/system/enable-console-blanking.service
```

```
sudo systemctl enable enable-console-blanking.service
```

### Reboot just to be sure

```
sudo reboot
```

---
## Developement machine

Generate ssh key and copy to the nodes
```
ssh-keygen -t rsa 
```

```
ssh-copy-id worker-0.poiuytre.nl
ssh-copy-id master-0.poiuytre.nl
ssh-copy-id master-1.poiuytre.nl
```
---
## All machines

Add those to /etc/hosts
```
# Cluster machines
192.168.178.10 registry.poiuytre.nl
192.168.178.10 mariadb.poiuytre.nl
192.168.178.10 proxy.poiuytre.nl
192.168.178.10 worker-0.poiuytre.nl
192.168.178.11 master-0.poiuytre.nl
192.168.178.12 master-1.poiuytre.nl
# End of Cluster machines
```
---
## Setup a local docker registry

### Install docker
See: https://docs.docker.com/engine/install/ubuntu/

### Run the registry

To run an externally-accessible registry, you need to issue a certificate. 
For that I'm using letsencrypt/certbot.

#### Create the certificates
```
sudo ./certs/gen_cert.sh poiuytre.nl 
```

```
sudo chmod 644 ./certs/poiuytre.nl.key

scp ./certs/poiuytre.nl.crt ./certs/poiuytre.nl.key registry.poiuytre.nl:.

sudo chmod 600 ./certs/poiuytre.nl.key

ssh -C "chmod 600 ./poiuytre.nl.key"  registry.poiuytre.nl
```

#### Deploy the registry

More info here: https://docs.docker.com/registry/deploying/#run-an-externally-accessible-registry

SSH to registry.poiuytre.nl and run the following

```
sudo docker container stop registry

sudo docker run -d \
  --restart=always \
  --name registry \
  -v "$(pwd)":/certs \
  -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/poiuytre.nl.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/poiuytre.nl.key \
  -p 443:443 \
  registry:latest

```

## Run mariadb on docker
This will be used by the k8s cluster


Create a password and run the database on docker

```
DB_PASSWORD=`date +%s | sha256sum | base64 | head -c 32`

sudo docker run -d --name mariadb --restart=always  -e MYSQL_ROOT_PASSWORD=$DB_PASSWORD -p 3306:3306 -d docker.io/library/mariadb

echo $DB_PASSWORD
```

``*******************``

``Don't forget to save the password somewhere safe``

``*******************``

## Run nginx as a proxy on docker

Build the docker image and push it to the registry
```
docker build --platform linux/amd64 -t nginx-poiuytre:3.1 .
```
```
docker tag nginx-poiuytre:3.1 registry.poiuytre.nl/nginx-poiuytre:3.1
```
```
docker push registry.poiuytre.nl/nginx-poiuytre:3.1
```

Run proxy on the docker host:

```
sudo docker pull registry.poiuytre.nl/nginx-poiuytre:3.1
```
```
sudo docker stop proxy && sudo docker rm proxy
```
```
sudo docker run -d \
  --name proxy \
  --restart=always \
  -p 6443:6443 -p 80:80\
  registry.poiuytre.nl/nginx-poiuytre:3.1
```

## HA k8s cluster setup

### Master 0

Install k3s
```
curl -sfL https://get.k3s.io | \
INSTALL_K3S_EXEC="--disable servicelb --disable traefik " \
K3S_DATASTORE_ENDPOINT='mysql://root:<DB_PASSWORD>@tcp(mariadb.poiuytre.nl:3306)/k3s_datastore' \
K3S_KUBECONFIG_MODE="644" \
sh -s - server --node-taint CriticalAddonsOnly=true:NoExecute --tls-san proxy.poiuytre.nl
```

Save the server token to be used on other masters and workers
```
sudo cat /var/lib/rancher/k3s/server/node-token
```

### Master n

Install k3s
```
curl -sfL https://get.k3s.io | \
INSTALL_K3S_EXEC="--disable servicelb --disable traefik " \
K3S_DATASTORE_ENDPOINT='mysql://root:<DB_PASSWORD>@tcp(mariadb.poiuytre.nl:3306)/k3s_datastore' \
K3S_TOKEN="<SERVER_TOKEN>" \
K3S_KUBECONFIG_MODE="644" \
sh -s - server --node-taint CriticalAddonsOnly=true:NoExecute --tls-san proxy.poiuytre.nl
```

### Workers

Install k3s
```
curl -sfL https://get.k3s.io | K3S_URL="https://proxy.poiuytre.nl:6443" K3S_TOKEN="<SERVER_TOKEN>" sh -
```

### Developement machine

Copy kubeconf from one of the masters to your machine
```
ssh master-0.poiuytre.nl -C 'cat /etc/rancher/k3s/k3s.yaml' | sed 's/127\.0\.0\.1/'"proxy.poiuytre.nl"'/g' > ~/.kube/k3s.yaml
```

## Expose services with MetalLB

# Install MLB
More info here: https://metallb.universe.tf/installation/


```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.10.3/manifests/namespace.yaml
```
```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.10.3/manifests/metallb.yaml
```
```
kubectl apply -f mlb/mlb-config-map.yaml  
```

## Using the private container registry on k3s

Copy the  following to ``/etc/rancher/k3s/registries.yaml`` on each of the master nodes
```
mirrors:
  "registry.poiuytre.nl":
    endpoint:
      - "https://registry.poiuytre.nl"
```

Restart the service 
```
systemctl restart k3s
```

Check if the changes were applied
```
sudo crictl info | grep registry -A 4
```
```
"registry": {
      "mirrors": {
        "docker.io": {
          "endpoint": [
            "https://registry-1.docker.io"
          ],
          "rewrite": null
        },
        "registry.poiuytre.nl": {
          "endpoint": [
            "https://registry.poiuytre.nl"
          ],
          "rewrite": null
        }
      },
      (...)
```



