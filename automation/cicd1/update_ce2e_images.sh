#!/bin/bash
sudo docker service update --image atsigncompany/secondary:dess_cicd \
 ce2e1_secondary
sudo docker service update --image atsigncompany/secondary:canary \
 ce2e3_secondary
