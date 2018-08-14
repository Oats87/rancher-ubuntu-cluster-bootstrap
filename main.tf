# Configure the Amazon AWS Provider
provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.region}"
}

variable "aws_access_key" {
  default     = "xxx"
  description = "Amazon AWS Access Key"
}

variable "aws_secret_key" {
  default     = "xxx"
  description = "Amazon AWS Secret Key"
}

variable "vpc_id" {}

variable "rancher_server" {}
variable "rancher_token" {}
variable "worker_count" {}

variable "prefix" {
  default     = "yourname"
  description = "Cluster Prefix - All resources created by Terraform have this prefix prepended to them"
}

variable "region" {
  default     = "us-west-2"
  description = "Amazon AWS Region for deployment"
}

variable "type" {
  default     = "t2.medium"
  description = "Amazon AWS Instance Type"
}

variable "ssh_key_name" {
  default     = ""
  description = "Amazon AWS Key Pair Name"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "rancher_mgmt_sg" {
  name = "${var.prefix}-mgmt-rancherha"
  vpc_id = "${var.vpc_id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 2376
    to_port     = 2376
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rancher_internal_sg" {
  name = "${var.prefix}-internal-rancherha"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    self = true
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    self = true
  }

  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self = true
  }

  ingress {
    from_port   = 9009
    to_port     = 9009
    protocol    = "tcp"
    self = true
  }

  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self = true
  }

  ingress {
    from_port   = 10250
    to_port     = 10256
    protocol    = "tcp"
    self = true
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    self = true
  }
}

data "template_cloudinit_config" "ranchermgmt_cloudinit" {
  count = "1"
  part {
    content_type = "text/x-shellscript"
    content      = "${file("17.03.sh")}"
  }
  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\nusermod -aG docker ubuntu"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\ndocker run -d --privileged --restart=unless-stopped --net=host -v /etc/kubernetes:/etc/kubernetes -v /var/run:/var/run rancher/rancher-agent:v2.0.7 --server ${var.rancher_server} --token ${var.rancher_token} --address awspublic --internal-address awslocal --etcd --controlplane"
  }
}

resource "aws_instance" "ranchermgmt" {
  count           = 1
  ami             = "${data.aws_ami.ubuntu.id}"
  instance_type   = "${var.type}"
  key_name        = "${var.ssh_key_name}"
  security_groups = ["${aws_security_group.rancher_internal_sg.name}", "${aws_security_group.rancher_mgmt_sg.name}"]
  vpc_security_group_ids = ["${aws_security_group.rancher_internal_sg.id}", "${aws_security_group.rancher_mgmt_sg.id}"]
  user_data = "${data.template_cloudinit_config.ranchermgmt_cloudinit.*.rendered[count.index]}"
  root_block_device {
    volume_size = "35"
  }
  tags {
    Name = "${var.prefix}-k8smgmt-${count.index}"
  }
}

data "template_cloudinit_config" "rancherwrk_cloudinit" {
  count = "${var.worker_count}"
  part {
    content_type = "text/x-shellscript"
    content      = "${file("17.03.sh")}"
  }
  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\nusermod -aG docker ubuntu"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\ndocker run -d --privileged --restart=unless-stopped --net=host -v /etc/kubernetes:/etc/kubernetes -v /var/run:/var/run rancher/rancher-agent:v2.0.7 --server ${var.rancher_server} --token ${var.rancher_token} --address awspublic --internal-address awslocal --worker"
  }
}

resource "aws_instance" "rancherwrk" {
  count           = "${var.worker_count}"
  ami             = "${data.aws_ami.ubuntu.id}"
  instance_type   = "${var.type}"
  key_name        = "${var.ssh_key_name}"
  security_groups = ["${aws_security_group.rancher_internal_sg.name}", "${aws_security_group.rancher_mgmt_sg.name}"]
  vpc_security_group_ids = ["${aws_security_group.rancher_internal_sg.id}", "${aws_security_group.rancher_mgmt_sg.id}"]
  user_data = "${data.template_cloudinit_config.rancherwrk_cloudinit.*.rendered[count.index]}"
  root_block_device {
    volume_size = "35"
  }
  tags {
    Name = "${var.prefix}-k8swrk-${count.index}"
  }
}