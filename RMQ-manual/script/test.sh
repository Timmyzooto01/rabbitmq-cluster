#!/usr/bin/sh
sudo scp -o StrictHostKeyChecking=no /etc/hosts ubuntu@rabbitmq1:/home/ubuntu/
sudo scp -o StrictHostKeyChecking=no /etc/hosts ubuntu@rabbitmq2:/home/ubuntu/ 
sudo ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo mv /etc/hosts /home/ubuntu/tmp'
sudo ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo mv /etc/hosts /home/ubuntu/tmp'