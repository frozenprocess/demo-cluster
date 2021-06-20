# Demo cluster

A simple terraform project to quickly testout K8s variations.

# Available variables

By default this project creates resources in `us-west-2` region. You can use `terraform.tfvars-example` file to change your region.

```
make sure you remove `-example` from suffix.
```

`region` default : `us-west-2`
`profile` default : `default`
`credential_file` default : `~/.aws/credentials`

`cidr_block` default: `172.16.0.0/16`

`instance_type` default: `t3.small`
  default = "ami-003e59a0293e20957"
`image_id` default: `ami-03e3c5e419088e824`



# Disclaimer

Do not use this project to start a production environment.
