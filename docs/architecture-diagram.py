"""
AWS EKS Secure Architecture Diagram

Generates a professional architecture diagram for the secure fintech
application deployed on Amazon EKS.

Requirements:
    pip install diagrams

Usage:
    python docs/architecture-diagram.py

Output:
    docs/architecture-diagram.png
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS, EC2
from diagrams.aws.network import VPC, ALB, NATGateway, InternetGateway
from diagrams.aws.security import IAMRole, KMS, WAF, GuardDuty, SecretsManager
from diagrams.aws.management import Cloudwatch
from diagrams.aws.database import RDS
from diagrams.aws.containers import ECR
from diagrams.k8s.compute import Pod, Deploy
from diagrams.k8s.network import Service, Ingress
from diagrams.onprem.client import Users

with Diagram(
    "Secure Fintech Application on AWS EKS",
    filename="docs/architecture-diagram",
    show=False,
    direction="TB",
    outformat="png",
):
    users = Users("End Users")
    waf = WAF("AWS WAF")

    with Cluster("AWS Cloud"):

        guardduty = GuardDuty("GuardDuty\nThreat Detection")
        cloudwatch = Cloudwatch("CloudWatch\nLogs & Metrics")
        ecr = ECR("ECR\nImage Registry")
        secrets = SecretsManager("Secrets\nManager")
        kms = KMS("KMS\nEncryption Keys")
        iam = IAMRole("IAM + IRSA")

        with Cluster("VPC (10.0.0.0/16)"):

            igw = InternetGateway("Internet\nGateway")

            with Cluster("Public Subnets (3 AZs)"):
                alb = ALB("Application\nLoad Balancer")
                nat = NATGateway("NAT\nGateway")

            with Cluster("Private Subnets (3 AZs)"):

                with Cluster("EKS Cluster"):
                    eks = EKS("EKS\nControl Plane")

                    with Cluster("Managed Node Group"):
                        nodes = [
                            EC2("Worker\nNode 1"),
                            EC2("Worker\nNode 2"),
                        ]

                    with Cluster("Application Pods"):
                        frontend = Pod("Frontend\n(React)")
                        backend = Pod("Backend\n(API)")

                rds = RDS("RDS PostgreSQL\n(Encrypted)")

    users >> Edge(label="HTTPS") >> waf >> alb
    alb >> igw
    igw >> alb
    alb >> Edge(label="TLS") >> frontend
    frontend >> backend
    backend >> Edge(label="Encrypted") >> rds
    backend >> Edge(label="IRSA") >> secrets

    eks >> cloudwatch
    eks >> guardduty
    nodes[0] >> ecr
    secrets >> kms
    iam >> eks

    nat >> Edge(label="Outbound\nOnly") >> igw
