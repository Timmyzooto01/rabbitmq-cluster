provider "aws" {
  region = "eu-west-2"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "main-vpc"
  }
}



resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "private"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.internet_gateway.id
  }
}


resource "aws_route_table_association" "route_table_association" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# elastic ip
resource "aws_eip" "elastic_ip" {
  vpc = true
}

# NAT gateway
resource "aws_nat_gateway" "nat_gateway" {
  depends_on = [
    aws_subnet.public,
    aws_eip.elastic_ip,
  ]
  allocation_id = aws_eip.elastic_ip.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "nat-gateway"
  }
}

# route table with target as NAT gateway
resource "aws_route_table" "NAT_route_table" {
  depends_on = [
    aws_vpc.main,
    aws_nat_gateway.nat_gateway,
  ]

  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "NAT-route-table"
  }
}

# associate route table to private subnet
resource "aws_route_table_association" "associate_routetable_to_private_subnet" {
  depends_on = [
    aws_subnet.private,
    aws_route_table.NAT_route_table,
  ]
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.NAT_route_table.id
}




resource "aws_security_group" "rabbitmq" {
  name        = "rabbitmq"
  description = "Allow traffic for RabbitMQ"
  vpc_id      = aws_vpc.main.id
  tags = {
    Name = "rabbitmq-sg"
  }

  ingress {
    from_port   = 4369
    to_port     = 4369
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }


  ingress {
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }


  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    /* self = true */
  }

  ingress {
    from_port = -1
    to_port   = -1
    protocol  = "icmp"
    self      = true
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}



##### RMQ1



resource "aws_instance" "rabbitmq_1" {
  depends_on = [
    aws_nat_gateway.nat_gateway,
    aws_route_table_association.associate_routetable_to_private_subnet,
  ]
  ami                         = "ami-038d76c4d28805c09"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  key_name                    = "rabbitmq"
  vpc_security_group_ids      = [aws_security_group.rabbitmq.id]

  tags = {
    Name = "rabbitmq1"
  }
}


#####   RMQ2 ####################
resource "aws_instance" "rabbitmq_2" {
  depends_on = [
    aws_nat_gateway.nat_gateway,
    aws_route_table_association.associate_routetable_to_private_subnet,
  ]
  ami                         = "ami-038d76c4d28805c09"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id
  key_name                    = "rabbitmq"
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.rabbitmq.id]

  tags = {
    Name = "rabbitmq2"
  }
}


resource "aws_instance" "bastion" {
  ami                         = "ami-038d76c4d28805c09"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  key_name                    = "rabbitmq"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.rabbitmq.id]

  provisioner "file" {
    source      = "script"
    destination = "/home/ubuntu/"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./script/rabbitmq.pem")
      host        = self.public_ip
      /* agent = true */

    }
  }

  tags = {
    Name = "bastion"
  }
}




#### create host-file in all and install all
resource "null_resource" "join_cluster" {

  depends_on = [
    aws_instance.bastion, aws_instance.rabbitmq_1, aws_instance.rabbitmq_2
  ]
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${aws_instance.bastion.tags.Name}",
      "echo ${aws_instance.bastion.private_ip} ${aws_instance.bastion.tags.Name} | sudo tee -a /etc/hosts",
      "echo ${aws_instance.rabbitmq_1.private_ip} ${aws_instance.rabbitmq_1.tags.Name} | sudo tee -a /etc/hosts",
      "echo ${aws_instance.rabbitmq_2.private_ip} ${aws_instance.rabbitmq_2.tags.Name} | sudo tee -a /etc/hosts",
      "echo 172.31.0.102 main | sudo tee -a /etc/hosts",
      "sudo cat /etc/hosts",
      "sudo echo 'IdentityFile /home/ubuntu/script/rabbitmq.pem' >> /home/ubuntu/config",
      "sudo mv /home/ubuntu/config ~/.ssh/",
      "sudo chmod 600 script/rabbitmq.pem",
      "sudo cat ~/.ssh/config",
      /* "sudo chmod +x /home/ubuntu/install.sh && sudo bash /home/ubuntu/script/install.sh" */
      /* "scp -o StrictHostKeyChecking=no /etc/hosts ubuntu@rabbitmq1:/home/ubuntu/",
      "scp -o StrictHostKeyChecking=no /etc/hosts ubuntu@rabbitmq2:/home/ubuntu/",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo mv /etc/hosts /home/ubuntu/tmp'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo mv /etc/hosts /home/ubuntu/tmp' " */
      /* "sudo chmod +x script/all.sh",
      "sudo bash /home/ubuntu/script/all.sh"  */

    ]
    connection {
      host        = aws_instance.bastion.public_ip
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./script/rabbitmq.pem")
      /* agent = true */
      /* options     = ["-o StrictHostKeyChecking=no"] */
    }
  }
}



resource "null_resource" "test" {
  depends_on = [
    aws_instance.bastion, aws_instance.rabbitmq_1, aws_instance.rabbitmq_2, null_resource.join_cluster
  ]
  provisioner "remote-exec" {
    inline = [
      /* "sudo chmod +x /home/ubuntu/script/install.sh && sudo bash /home/ubuntu/script/install.sh", */
      #### copy the host file from bastion to each rmq
      "scp -o StrictHostKeyChecking=no /etc/hosts ubuntu@rabbitmq1:/home/ubuntu/",
      "scp -o StrictHostKeyChecking=no /etc/hosts ubuntu@rabbitmq2:/home/ubuntu/",
      ####  copy the old hosts to to tmp 
      /* "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo mv /etc/hosts /home/ubuntu/tmp'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo mv /etc/hosts /home/ubuntu/tmp'", */
      ### update the hosts file to use the new hosts file  to /etc/
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo mv /home/ubuntu/hosts /etc/'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo mv /home/ubuntu/hosts /etc/'",
      #### copy the script files to each rmq server
      "scp  -o StrictHostKeyChecking=no /home/ubuntu/script/test.txt ubuntu@rabbitmq1:/home/ubuntu/",
      "scp  -o StrictHostKeyChecking=no /home/ubuntu/script/test.txt ubuntu@rabbitmq2:/home/ubuntu/",
      /* "sudo cat /home/ubuntu/script/test.txt > /home/ubuntu/install.sh", */

      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo cat /home/ubuntu/test.txt > /home/ubuntu/install.sh'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo cat /home/ubuntu/test.txt > /home/ubuntu/install.sh'",





      #### update the hostname using hostnamecll
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo hostnamectl set-hostname rabbitmq1'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo hostnamectl set-hostname rabbitmq2'",


      #copying rabbitmq.pem to RM1 and RM2
      "scp  -o StrictHostKeyChecking=no /home/ubuntu/script/rabbitmq.pem ubuntu@rabbitmq1:/home/ubuntu/",
      "scp  -o StrictHostKeyChecking=no /home/ubuntu/script/rabbitmq.pem ubuntu@rabbitmq2:/home/ubuntu/",

      #enabling identityfile to use rabbitmq.pem 
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo echo 'IdentityFile /home/ubuntu/rabbitmq.pem' >> /home/ubuntu/config'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo echo 'IdentityFile /home/ubuntu/rabbitmq.pem' >> /home/ubuntu/config'",

      #copying config to ssh file
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo mv /home/ubuntu/config ~/.ssh/ && sudo chmod 600 /home/ubuntu/rabbitmq.pem && sudo cat ~/.ssh/config'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo mv /home/ubuntu/config ~/.ssh/ && sudo chmod 600 /home/ubuntu/rabbitmq.pem && sudo cat ~/.ssh/config'",


      #####run the script to install RMQ on all server

      "sudo chmod +x /home/ubuntu/script/install.sh && sudo bash /home/ubuntu/script/install.sh",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo chmod +x /home/ubuntu/install.sh && sudo bash /home/ubuntu/install.sh'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo chmod +x /home/ubuntu/install.sh && sudo bash /home/ubuntu/install.sh'",

      ####verify that they are working

      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo rabbitmqctl cluster_status'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo rabbitmqctl cluster_status'",


      ### stop RMQ application on RMQ1 and RMQ2
      "ssh -o StrictHostKeyChecking=no  rabbitmq1 'sudo systemctl stop rabbitmq-server'",
      "ssh -o StrictHostKeyChecking=no  rabbitmq2 'sudo systemctl stop rabbitmq-server'",

      ##### copy the cookies bastion to  rmq1 to rmq2
      /* "sudo  chmod 775 /var/lib/rabbitmq/.erlang.cookie",
      "sudo cat /var/lib/rabbitmq/.erlang.cookie > /home/ubuntu/erlang.cookie",
      "sudo  chmod 775 /home/ubuntu/erlang.cookie",
      "sudo scp -o StrictHostKeyChecking=no /home/ubuntu/erlang.cookie ubuntu@rabbitmq1:/home/ubuntu/",
      "sudo scp -o StrictHostKeyChecking=no /home/ubuntu/erlang.cookie ubuntu@rabbitmq2:/home/ubuntu/", */


      #### Move the default cookie to tmp on both server
      /* "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo  chmod 755 /var/lib/rabbitmq/.erlang.cookie'", */
      /* "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo cat /var/lib/rabbitmq/.erlang.cookie  /home/ubuntu/tmp_cookie'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo rm -R /home/ubuntu/tmp_cookie'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo  chmod 755 /var/lib/rabbitmq/.erlang.cookie'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo mv /var/lib/rabbitmq/.erlang.cookie /home/ubuntu/tmp_cookie'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo rm -R /home/ubuntu/tmp_cookie'", */


      ##### move the new cookie to rabbitmq folder
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo  chmod 777 /var/lib/rabbitmq/.erlang.cookie'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo cat BFAZFDLFAMFFSPFFDQZA > /var/lib/rabbitmq/.erlang.cookie'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo  chmod 777 /var/lib/rabbitmq/.erlang.cookie'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo cat BFAZFDLFAMFFSPFFDQZA > /var/lib/rabbitmq/.erlang.cookie'",

      #####start RMQ 1 and 2 
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo systemctl start rabbitmq-server'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo systemctl start rabbitmq-server'",

      #####join the cluster 

      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo rabbitmqctl stop_app && sudo rabbitmqctl join_cluster rabbit@rabbitmq2 && sudo rabbitmqctl start_app'",
      /* "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo rabbitmqctl stop_app && sudo rabbitmqctl join_cluster rabbit@bastion && sudo rabbitmqctl start_app'", */

      ####verify that they are working

      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo rabbitmqctl cluster_status'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo rabbitmqctl cluster_status'",

      /* ####setup password and users on rmq1

      "ssh -o StrictHostKeyChecking=no  rabbitmq1 'sudo rabbitmqctl add_user admin QWRtaW4xMjMh && sudo rabbitmqctl set_user_tags admin administrator && sudo rabbitmqctl set_permissions -p / admin '.*' '.*' '.*' && sudo rabbitmqctl delete_user guest && sudo rabbitmqctl list_users'",

      # create virtual host and enable rabbitmq_management
      "ssh -o StrictHostKeyChecking=no  rabbitmq1 'sudo rabbitmqctl add_vhost app-qa1 && sudo rabbitmqctl list_vhosts && sudo rabbitmq-plugins enable rabbitmq_management && sudo rabbitmqctl cluster_status'",

      ####verify that they are working

      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq1 'sudo rabbitmqctl cluster_status'",
      "ssh -o StrictHostKeyChecking=no  ubuntu@rabbitmq2 'sudo rabbitmqctl cluster_status'", */
    ]
    connection {
      host        = aws_instance.bastion.public_ip
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("./script/rabbitmq.pem")
      /* agent = true */

    }

  }
}


/* resource "null_resource" "quorum_queue" {
  provisioner "remote-exec" {
    inline = [
      "echo ${aws_instance.rabbitmq_2.private_ip} ${aws_instance.rabbitmq_2.tags.Name} | sudo tee -a /etc/hosts",
      # "sudo scp /var/lib/rabbitmq/.erlang.cookie root@${aws_instance.rabbitmq_2.private_ip}:/var/lib/rabbitmq/",
      # "sudo rabbitmqctl set_policy ha-all \"^quorum\\.\" '{\"ha-mode\":\"all\"}' --apply-to queues"
    ]
    connection {
      host = aws_instance.rabbitmq_1.public_ip
      type        = "ssh"
      user        = "ubuntu"
      private_key = "${file("/mnt/e/IMAGINATION/ssh-keys/rabbitmq.pem")}"
    }
  }
} */




