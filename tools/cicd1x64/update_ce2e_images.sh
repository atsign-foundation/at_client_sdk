#!/bin/bash
sudo docker service update --image atsigncompany/secondary:dev_env \
 ce2e1_secondary
sudo docker service update --image atsigncompany/secondary:canary \
 ce2e3_secondary
