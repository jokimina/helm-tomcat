#!/bin/bash
source ~/.bashrc
set -x 

helm get ${JOB_BASE_NAME} &> /dev/null
if [ $? -eq 0 ];then
  helm get values ${JOB_BASE_NAME} | sed "/imageTag/c\imageTag: \"${BUILD_NUMBER}\"" | helm upgrade --debug --wait -f - ${JOB_BASE_NAME} wesd/tomcat
else
  while true
  do
    DEBUG_PORT=$(expr 30000 + $RANDOM % 2767)
    if ! kubectl get  svc -n kube-system nginx-ingress-lb  --template={{.spec.ports}}| grep -qrn $DEBUG_PORT  ;then
        break
    fi
    sleep 1s
  done

  helm install -n test --debug --dry-run --set "imageTag=${BUILD_NUMBER},appName=${JOB_BASE_NAME},debugPort=${DEBUG_PORT}" wesd/tomcat \
| awk '/COMPUTED VALUES/{F=1;next}NF==0{F=0}F' \
| helm install --debug --wait -f - -n ${JOB_BASE_NAME} wesd/tomcat 
  [ $? -ne 0 ] && exit 500
  echo "## Patch ingress tcp-services port config "
  kubectl patch -n kube-system cm tcp-services  --patch '{"data":{"'${DEBUG_PORT}'": "default/'${JOB_BASE_NAME}'0debug:'${DEBUG_PORT}'"}}'
  
  echo "## Patch nginx-ingress-lb port listener config"
  kubectl patch -n kube-system svc nginx-ingress-lb  --patch '{"spec":{"ports":[{"name":"'${JOB_BASE_NAME}'0debug","port": '${DEBUG_PORT}', "protocol":"TCP", "targetPort": '${DEBUG_PORT}'}]}}'
fi
