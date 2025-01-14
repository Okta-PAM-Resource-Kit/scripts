
### include OPA terraform provider
terraform {
  required_providers {
    oktapam = {
      source = "okta/oktapam"
      version = "0.5.3"
    }
  }
}

### retrieve necessary credentials and team details to interact with OPA API
data "external" "secrets" {
  program = ["bash", "./get_terrafrom_creds.sh"]
}

### establish parameters for connecting to your OPA team
provider "oktapam" {
  # Authentication options
  oktapam_key = data.external.secrets.result["apikey"]
  oktapam_secret = data.external.secrets.result["apisecret"]
  oktapam_team = data.external.secrets.result["team"]
  oktapam_api_host = data.external.secrets.result["url"]
}

### replace k8slab-1 everywhere below with your cluster name
### define the k8s cluster
resource "oktapam_kubernetes_cluster" "k8slab-1" {
  auth_mechanism    = "OIDC_RSA2048"
  key		 	= "k8slab-1"
  labels		= { env = "POC", tier = "bronze" }
}

### define the k8s cluster connection to be included in k8s context
resource "oktapam_kubernetes_cluster_connection" "k8slab-1" {
  cluster_id         = oktapam_kubernetes_cluster.k8slab-1.id
### update the line below to indicate the URL of the k8s apiserver
  api_url            = "https://your-k8s-apiserver:6443"
  public_certificate = file("./ca.crt")
}

### duplicate the below block for each group to k8s role binding
### define OPA group to k8s cluster role binding
resource "oktapam_kubernetes_cluster_group" "k8slab-1" {
  cluster_selector  = "env=POC"
  group_name		    = "PAM-K8s-Admins"
  claims            = { groups = "system:masters" }
}

