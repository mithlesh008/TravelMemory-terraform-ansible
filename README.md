# TravelMemory — Terraform and Ansible

Deploy TravelMemory on AWS using a public web EC2 instance and a private MongoDB EC2 instance.

Run the commands below on an Amazon Linux 2023 controller EC2. Your Mac is only used to SSH into the controller and open the application in a browser. The controller must be separate from the infrastructure managed by this repository.

## Prerequisites

* Terraform 1.6 or newer, Ansible, Git, AWS CLI, and OpenSSH installed on the controller.
* An attached controller IAM role with permissions to create the project's EC2, VPC/networking, and IAM resources, including permission to pass the application role to EC2. The application SSM policy alone is not sufficient.
* Outbound internet access from the controller and its public IPv4 address available for the web server's SSH allowlist.
* An Amazon Linux 2023 x86_64 AMI ID in your chosen AWS region.
* The `ansible.posix.firewalld` module available to Ansible.

Check prerequisites:

```bash
terraform version
ansible --version
git --version
aws sts get-caller-identity
ansible-doc ansible.posix.firewalld
```

Press `q` to leave the module documentation. If the module is missing, install a version of `ansible.posix` compatible with your installed Ansible Core. For the Amazon Linux Core 2.15 package used in this setup:

```bash
ansible-galaxy collection install 'ansible.posix:1.5.4'
```

Use the same controller Linux account throughout so the SSH key and Ansible paths stay consistent.

## 1. Clone the repository

```bash
git clone https://github.com/mithlesh008/TravelMemory-terraform-ansible.git
cd TravelMemory-terraform-ansible
export PROJECT_DIR="$PWD"
```

For a private repository, authenticate with GitHub first. Confirm the expected files are present:

```bash
ls terraform/*.tf terraform/terraform.tfvars.example
ls ansible/site.yml ansible/ansible.cfg
ls ansible/group_vars/all/vars.yml ansible/group_vars/all/vault.yml.example
```

If you already have a working deployment, reuse its project folder, Terraform state, and SSH key instead of deploying again from a fresh clone. Do not overwrite existing real configuration files with examples when rerunning these instructions.

## 2. Create the application SSH key

On the controller:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [ ! -f ~/.ssh/travelmemory ]; then
  ssh-keygen -t ed25519 -f ~/.ssh/travelmemory
fi
chmod 400 ~/.ssh/travelmemory
```

For an unattended lab key, press Enter twice at the passphrase prompts. If you set a passphrase, load the key into an SSH agent before running Ansible. Never commit or copy the private key to the application instances.

This is separate from the key you use on your Mac to log into the controller.

## 3. Configure Terraform

```bash
cd "$PROJECT_DIR/terraform"
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Set these values:

* `aws_region`: your AWS region.
* `ami_id`: Amazon Linux 2023 x86_64 AMI ID for that region.
* `admin_cidr`: controller public IPv4 address followed by `/32`.
* `public_key_path`: `~/.ssh/travelmemory.pub`.

Do not leave the example `0.0.0.0/0` SSH range open for a secured deployment. The controller's own SSH rule should allow your Mac's public IP; the web instance's rule should allow the controller's public IP. If the controller's public IP changes, update the access configuration.

## 4. Create the infrastructure

```bash
terraform init
terraform fmt
terraform validate
```

<img width="999" height="831" alt="Screenshot 2026-10-25 at 1 38 36 PM" src="https://github.com/user-attachments/assets/4899221e-a054-4326-806b-5fff17e82394" />


```bash
terraform plan
terraform apply
```

Review the plan and enter `yes` only when the changes are expected. AWS resources incur charges.

Export the outputs in the same controller terminal:

```bash
export WEB_PUBLIC_IP="$(terraform output -raw web_public_ip)"
export WEB_PRIVATE_IP="$(terraform output -raw web_private_ip)"
export DB_PRIVATE_IP="$(terraform output -raw db_private_ip)"
terraform output
```

The database should have no public IP. Terraform creates its private subnet's NAT route for outbound package downloads.

## 5. Configure Ansible

```bash
cd "$PROJECT_DIR/ansible"
nano group_vars/all/vars.yml
```

Update:

* `repo_url`: your TravelMemory application fork, containing `backend/` and `frontend/` on the branch expected by `site.yml`. Do not point it at a deployment-only repository.
* `admin_ip`: the controller's public IPv4 `/32`, matching Terraform's `admin_cidr`.
* Other non-secret settings only if your application requires changes.

The sample deployment expects `backend/index.js`, backend variables `MONGO_URI` and `PORT`, and a frontend that uses `REACT_APP_BACKEND_URL=/api`. Confirm these match your application fork; a hard-coded frontend backend URL must be corrected in the application before rebuilding.

### Create and encrypt secrets

```bash
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
chmod 600 group_vars/all/vault.yml
nano group_vars/all/vault.yml
```

Replace `mongo_app_password` and `mongo_admin_password` with different, strong random alphanumeric passwords. Keep placeholder values in `vault.yml.example`, not real passwords. This sample interpolates the real values into a shell command and MongoDB URI, so avoid spaces, quotes, and URI-special characters.

Encrypt the real file:

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

Keep the Vault password safe; it is separate from the MongoDB passwords. To update an existing encrypted vault, use `ansible-vault edit group_vars/all/vault.yml` instead of copying the example over it.

### Generate the inventory

The following uses the Terraform output variables exported in Step 4. It creates the real inventory on the controller and explicitly supplies the SSH key for the web jump-host connection.

```bash
cat > inventory.ini <<EOF
[web]
web ansible_host=${WEB_PUBLIC_IP} private_ip=${WEB_PRIVATE_IP}

[db]
db ansible_host=${DB_PRIVATE_IP}

[all:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=${HOME}/.ssh/travelmemory

[db:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -i ${HOME}/.ssh/travelmemory -o IdentitiesOnly=yes -W %h:%p ec2-user@${WEB_PUBLIC_IP}"'
EOF
```

If you opened a new controller session, restore `PROJECT_DIR` to the existing clone's absolute path and rerun the Step 4 output exports before generating the inventory.

## 6. Test connectivity and run the playbook

Test web SSH first:

```bash
ssh -i ~/.ssh/travelmemory ec2-user@"$WEB_PUBLIC_IP"
```

If prompted, verify the server's host key through a trusted channel before accepting it. Type `exit` to return to the controller. Then:

```bash
cd "$PROJECT_DIR/ansible"
ansible-inventory --graph
ansible all -m ping --ask-vault-pass
```

Both hosts must return `SUCCESS` and `pong`. The same-name group/host warnings for `web` and `db` are not fatal; do not rename the hosts without updating the playbook's `hostvars` references.

Validate and deploy:

```bash
ansible-playbook site.yml --syntax-check --ask-vault-pass
ansible-playbook site.yml --ask-vault-pass
```
<img width="1253" height="465" alt="Screenshot 2026-10-25 at 2 12 21 PM" src="https://github.com/user-attachments/assets/d69f12a8-0102-48ef-8f6f-8e85550eba99" />

<img width="1254" height="106" alt="Screenshot 2026-10-25 at 2 05 52 PM" src="https://github.com/user-attachments/assets/cf693cde-ce93-4961-8981-dcfe5a027593" />

<img width="1706" height="468" alt="Screenshot 2026-10-25 at 2 19 57 PM" src="https://github.com/user-attachments/assets/2143efef-2d03-4ca5-8950-a3ec75f43711" />

The final recap should show `failed=0` and `unreachable=0` for both hosts. The playbook configures MongoDB, deploys the application, starts the backend and Nginx, and configures firewalls.

## 7. Verify the application

On the controller, get the URL:

```bash
cd "$PROJECT_DIR/terraform"
terraform output -raw web_url
```

Open that URL in your Mac's browser. Create a sample travel memory and confirm it is still displayed after refreshing.

<img width="1895" height="987" alt="Screenshot 2026-10-25 at 2 20 59 PM" src="https://github.com/user-attachments/assets/02229801-76f6-4579-8fb1-11ea1374fde1" />


For service checks, SSH to the web instance:

```bash
ssh -i ~/.ssh/travelmemory ec2-user@"$WEB_PUBLIC_IP"
sudo systemctl status travelmemory-backend nginx --no-pager
sudo nginx -t
curl -i http://localhost/api/trip
exit
```

<img width="1728" height="888" alt="Screenshot 2026-10-25 at 2 21 56 PM" src="https://github.com/user-attachments/assets/9c9316cb-10c5-4b71-8ad3-88d847ce1fe8" />


Use your application's actual route if it differs from `/trip`. After `exit`, check MongoDB from the controller:

```bash
cd "$PROJECT_DIR/ansible"
ansible db --ask-vault-pass -b -m command -a "systemctl is-active mongod"
```

## Common errors

* Vault decryption error: include `--ask-vault-pass`, even for `ansible ... -m ping`, because encrypted group variables load automatically.
* Database SSH fails while web succeeds: verify the inventory ProxyCommand, database private IP, shared application key pair, and database security-group rule allowing port 22 from the web security group. Do not give the database a public IP or copy the key onto the web server.
* `curl-minimal` / `gnupg2-minimal` conflicts: ensure the database prerequisite task in `site.yml` requests only `[ca-certificates, firewalld]`, not the conflicting full `curl` and `gnupg2` packages. Keep the existing minimal packages.
* Backend failure: inspect `sudo journalctl -u travelmemory-backend -n 100 --no-pager` on the web instance. Redact connection strings before sharing logs.

## 8. Clean up

When finished, run from the controller using the same Terraform directory and state:

```bash
cd "$PROJECT_DIR/terraform"
terraform plan -destroy
terraform destroy
```

Review the proposed deletions before confirming. This does not delete the separately created controller or its Elastic IP. Securely retain needed state and data before removing the controller.

## Keep secrets out of Git

Commit source files, placeholder examples, and `.terraform.lock.hcl`. Do not commit real `terraform.tfvars`, inventory, vault files, `.env`, Terraform state/plans, private keys, AWS credentials, or GitHub tokens. A `.example` extension is safe only when the file contains placeholders. Ignore rules do not remove already-tracked secrets or erase Git history.
