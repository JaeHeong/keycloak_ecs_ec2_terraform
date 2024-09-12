# Keycloak on ECS with RDS

## Building the container image

Build an "optimised" Keycloak container using Docker or Podman ([`container/Dockerfile`](container/Dockerfile)), and push to ECR:

```
docker buildx build --platform linux/amd64 -t ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/example/keycloak:YYYY-MM-DD container
aws ecr get-login-password --region REGION | podman login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com
docker push ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/example/keycloak:YYYY-MM-DD
```

## Deployment

Import a HTTPS certificate to ACM.
For testing you can create a self-signed certificate (run [`scripts/self-signed-cert.sh`](scripts/self-signed-cert.sh))

```sh
cd ecs-cluster
terraform init 
terraform apply 
```
