# Demo cluster

A simple terraform project to quickly test out K8s variations.

# Requirements 

- terraform
- cloud account
- a bit of time

# How to

> I'm not going to say give it star since you Obviously have done it before getting to this step ;)

Clone the repository.
```
git clone https://github.com/frozenprocess/demo-cluster.git
cd demo-cluster
```

Copy a template from examples folder.
```
cp examples/main.tf-gcpmulticluster main.tf
```

Open up the newly created `main.tf` and adjust the variables as you like.

Use the following command to install the require provider:
```
terraform init
```

Use the following command to check the resources that will be populated in your account:
```
terraform plan
```

> Note: At this point resources will be generated in your cloud account.

Use the following command to create the project:
```
terraform apply
```

after a successful deployment use the `demo_connection` from the output to ssh into the controlplane.

# Clean up
Keep in mind that cloud providers charge you based on the time that you have spent on running resources,at any point you can use `terraform destroy` to completely destroy the project and.

# Available variables

Each templates offers variables that can be changed to adjust aspects of your deployment.
You can change these values by adjusting the `examples` files.
```

# Disclaimer

This project is for educational purposes. Do not use this project to start a production environment.
