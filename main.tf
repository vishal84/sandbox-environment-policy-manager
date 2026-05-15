provider "google" {
  project = var.project_id
  region  = var.region
}

# 2. Enable Required APIs
resource "google_project_service" "compute_api" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# 3. Create a Service Account
resource "google_service_account" "policy_manager_sa" {
  account_id   = "policy-manager-sa"
  display_name = "Policy Manager for GKE Demos"
}

# 4. Grant Project-level IAM
resource "google_project_iam_member" "compute_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.policy_manager_sa.email}"
}

# Grant Logging permissions
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.policy_manager_sa.email}"
}

# Grant Monitoring permissions
resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.policy_manager_sa.email}"
}

# 5. Network with Private Google Access
resource "google_compute_network" "demo_vpc" {
  name                    = "argolis-policy-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute_api]
}

resource "google_compute_subnetwork" "demo_subnet" {
  name                     = "argolis-policy-subnet"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = var.region
  network                  = google_compute_network.demo_vpc.id
  private_ip_google_access = true 
}

# 6. The VM Instance
resource "google_compute_instance" "policy_trigger" {
  name         = "argolis-policy-enforcer"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "projects/debian-cloud/global/images/family/debian-12"
    }
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.demo_subnet.id
  }

  service_account {
    email  = google_service_account.policy_manager_sa.email
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true

  # FIXED STARTUP SCRIPT
  metadata_startup_script = <<-EOT
    #!/bin/bash
    PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
    PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

    sleep 30

    # 1. Disable Shielded VM Requirement
    gcloud org-policies set-policy /dev/stdin << EOF
    name: projects/$PROJECT_NUMBER/policies/compute.requireShieldedVm
    spec:
      rules:
      - enforce: false
    EOF

    # 2. Allow External IPs
    gcloud org-policies set-policy /dev/stdin << EOF
    name: projects/$PROJECT_NUMBER/policies/compute.vmExternalIpAccess
    spec:
      rules:
      - allowAll: true
    EOF

    # 3. Disable OS Login
    gcloud org-policies set-policy /dev/stdin << EOF
    name: projects/$PROJECT_NUMBER/policies/compute.requireOsLogin
    spec:
      rules:
      - enforce: false
    EOF

    # TIMER: Now using a pre-calculated integer from Terraform
    echo "Sleeping for ${local.total_seconds} seconds before self-termination..."
    sleep ${local.total_seconds}
    
    gcloud compute instances delete argolis-policy-enforcer --zone=${var.zone} --quiet
  EOT

  metadata = {
    shutdown-script = <<-EOT
      #!/bin/bash
      PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
      gcloud org-policies delete compute.requireShieldedVm --project=$PROJECT_ID
      gcloud org-policies delete compute.vmExternalIpAccess --project=$PROJECT_ID
      gcloud org-policies delete compute.requireOsLogin --project=$PROJECT_ID
    EOT
  }
}