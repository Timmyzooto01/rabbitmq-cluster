
#### copy the host file from bastion to each rmq 
scp -o StrictHostKeyChecking=no /etc/hosts ubuntu@rabbitmq1:/home/ubuntu/
scp -o StrictHostKeyChecking=no /etc/hosts ubuntu@rabbitmq2:/home/ubuntu/ 
####  copy the old hosts to to tmp 
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo mv /etc/hosts /home/ubuntu/tmp'
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo mv /etc/hosts /home/ubuntu/tmp'
### update the hosts file to use the new hosts file  to /etc/
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo mv /home/ubuntu/hosts /etc/'
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo mv /home/ubuntu/hosts /etc/'
#### copy the script files to each rmq server
scp -o StrictHostKeyChecking=no script ubuntu@rabbitmq1:/home/ubuntu
scp -o StrictHostKeyChecking=no script ubuntu@rabbitmq2:/home/ubuntu

#### update the hostname using hostnamecll
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo hostnamectl set-hostname rabbitmq1'
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo hostnamectl set-hostname rabbitmq2'


#####run the script to install RMQ on all server

sudo chmod +x /home/ubuntu/script/install.sh && sudo bash /home/ubuntu/script/install.sh
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo chmod +x /home/ubuntu/script/install.sh && sudo bash /home/ubuntu/script/install.sh'
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo chmod +x /home/ubuntu/script/install.sh && sudo bash /home/ubuntu/script/install.sh'


##### copy the cookies bastion to  rmq1 to rmq2 
scp -o StrictHostKeyChecking=no /var/lib/rabbitmq/.erlang.cookie ubuntu@rabbitmq1:/home/ubuntu/
scp -o StrictHostKeyChecking=no /var/lib/rabbitmq/.erlang.cookie ubuntu@rabbitmq2:/home/ubuntu/

### stop RMQ application on RMQ1 and RMQ2
ssh -o StrictHostKeyChecking=no  rabbitmq1 'sudo systemctl stop rabbitmq-server'
ssh -o StrictHostKeyChecking=no  rabbitmq2 'sudo systemctl stop rabbitmq-server'


#### Move the default cookie to tmp on both server

ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo mv  /var/lib/rabbitmq/.erlang.cookie /home/ubuntu/tmp'
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo mv  /var/lib/rabbitmq/.erlang.cookie /home/ubuntu/tmp'


##### move the new cookie to rabbitmq folder
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo mv   /home/ubuntu/.erlang.cookie /var/lib/rabbitmq/'
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo mv   /home/ubuntu/.erlang.cookie /var/lib/rabbitmq/'

#####start RMQ 1 and 2 
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo systemctl start rabbitmq-server'
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo systemctl start rabbitmq-server'

#####join the cluster 

ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo rabbitmqctl stop_app && sudo rabbitmqctl join_cluster rabbit@rabbitmq1 && sudo rabbitmqctl start_app'


####verify that they are working

ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo rabbitmqctl cluster_status'
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo rabbitmqctl cluster_status'

####setup password and users on rmq1

ssh -o StrictHostKeyChecking=no  rabbitmq1 'sudo rabbitmqctl add_user admin QWRtaW4xMjMh && sudo rabbitmqctl set_user_tags admin administrator && sudo rabbitmqctl set_permissions -p / admin ".*" ".*" ".*" && sudo rabbitmqctl delete_user guest && sudo rabbitmqctl list_users'

# create virtual host and enable rabbitmq_management
ssh -o StrictHostKeyChecking=no  rabbitmq1 'sudo rabbitmqctl add_vhost app-qa1 && sudo rabbitmqctl list_vhosts && sudo rabbitmq-plugins enable rabbitmq_management && sudo rabbitmqctl cluster_status'

####verify that they are working

ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo rabbitmqctl cluster_status'
ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo rabbitmqctl cluster_status'




