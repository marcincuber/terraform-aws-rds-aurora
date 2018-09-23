# terraform-aws-rds-aurora
Terraform Module: Creates AWS resources: Aurora Cluster and its instances.

Provides you with the following:

1. DB subnet group
2. DB and Cluster parameter groups
3. An Aurora DB cluster
4. An Aurora DB instance and aditional number of replicas
5. You can enable Enhanced Monitoring' and use required IAM role/policy
6. Cloudwatch alarms to SNS (high CPU, high connections, slow replication)
7. Autoscaling for read replicas

Will be added soon:
Examples which are crucial
Custom KMS encryption with new or existing keys
Security Groups

### Outputs

- `rds_cluster_id`
- `writer_endpoint`
- `reader_endpoint`

### Authors

Marcin Cuber [main_github](https://github.com/marcincuber) [sub_github](https://github.com/marcincubernews)

### Contact <a name="contact"></a>

If you have any questions, drop me an email marcincuber@hotmail.com or open an issue and leave stars! :)


