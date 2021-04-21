terraform {
  required_version = ">= 0.12.0"
}

provider "aws" {
  profile = "lab"
  version = ">= 2.28.1"
  region  = var.region
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

data "aws_availability_zones" "available" {
}

resource "aws_efs_file_system" "eks_efs" {
  creation_token = "eks_efs_emma2"
}

/*resource "aws_efs_mount_target" "efs_eks_emma2_mount" {
  file_system_id = aws_efs_file_system.eks_efs.id
  subnet_id = module.vpc.
}
*/

resource "aws_security_group" "worker_group_mgmt_one" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

resource "aws_security_group" "allow_ingress_to_efs" {
  name_prefix = "ingress_efs_emma2"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 2049
    to_port   = 2049
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.6.0"

  name                 = "test-vpc"
  cidr                 = "10.18.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.18.1.0/24", "10.18.2.0/24"]
  public_subnets       = ["10.18.4.0/24", "10.18.5.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
    } 
}


module "eks" {
  source       = "terraform-aws-modules/eks/aws"
  cluster_name    = var.cluster_name
  cluster_version = "1.17"
  subnets         = module.vpc.private_subnets
  version = "12.2.0"
  cluster_create_timeout = "1h"
  cluster_endpoint_private_access = true 

  vpc_id = module.vpc.vpc_id

  worker_groups = [
    {
      name                          = "worker-group"
      key_name                      = "emmanuel-eolab-project"
      instance_type                 = "t3.medium"
      asg_desired_capacity          = 1
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    },
/*    {
      name                          = "worker-group-2"
      key_name                      = "emmanuel-eolab-project"
      instance_type                 = "t2.medium"
      asg_desired_capacity          = 1
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    },  
*/ 
  ]
}



provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.11"
}

resource "kubernetes_deployment" "jenkins" {
  metadata {
    name = "jenkins"
    labels = {
      app = "jenkins"
    }
  }

  spec {
    replicas =1

    selector {
      match_labels = {
        app = "jenkins"
      }
    }

    template {
      metadata {
        labels = {
          app = "jenkins"
        }
      }

      spec {
        container {
          image = "elontsi007/jenkins:latest"
          name  = "jenkins"

          resources {
            limits {
              cpu    = "800m"
              memory = "1000Mi"
            }
            requests {
              cpu    = "700m"
              memory = "700Mi"
            }
          }
        }
      }
    }
  }
}

/*resource "kubernetes_service" "jenkins-service" {
  metadata {
    name = "jenkins-service"
  }
  spec {
    selector = {
      app = "jenkins"
    }
    port {
      port        = 8080
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}
*/

resource "null_resource" "efs_storage" {
  depends_on = [module.eks.aws_eks_cluster]
  provisioner "local-exec" {
    command = format("kubectl apply -k 'github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master'")
  }
}

resource "null_resource" "service_account" {
  depends_on = [module.eks.aws_eks_cluster]
  provisioner "local-exec" {
    command = format("kubectl apply -f serviceaccount.yaml")
  }
}

resource "null_resource" "jenkins_service" {
  depends_on = [module.eks.aws_eks_cluster]
  provisioner "local-exec" {
    command = format("kubectl apply -f jenkins-service.yaml")
  }
}

resource "null_resource" "jenkins_pv" {
  depends_on = [module.eks.aws_eks_cluster]
  provisioner "local-exec" {
    command = format("kubectl apply -f jenkins_pv1.yaml")
  }
}

resource "null_resource" "jenkins_pvc" {
  depends_on = [module.eks.aws_eks_cluster]
  provisioner "local-exec" {
    command = format("kubectl apply -f jenkins_pvc1.yaml")
  }
}


