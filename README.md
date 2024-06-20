prepare/clone from Github
		provider.tf                     
    var-values.tfvars
    services.tf
    variables.tf

Run
  % terraform init
  % terraform plan -var-file=var-values.tfvars
  % terraform apply -var-file=var-values.tfvars -destroy
