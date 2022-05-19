#!/bin/bash
sudo docker service update --image atsigncompany/secondary:dess_cicd \
 ce2e2_secondary
sudo docker service update --image atsigncompany/secondary:canary \
 ce2e4_secondary
