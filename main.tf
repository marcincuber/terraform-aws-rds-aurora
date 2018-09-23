// DB Subnet Group
resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-${var.environment}-db-sg"
  description = "Group of DB subnets"
  subnet_ids  = ["${var.subnets}"]

  tags {
    Name = "${var.name}-${var.environment}"
    Project = "${var.name}"
    Environment = "${var.environment}"
  }
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-${var.environment}-db-pg"
  family      = "${var.family}"
  description = "Terraform-managed parameter group for ${var.name}-${var.environment}-db}"

  parameter = ["${var.db_parameters}"]

  tags {
    Name = "${var.name}-${var.environment}"
    Project = "${var.name}"
    Environment = "${var.environment}"
  }
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name}-${var.environment}-cluster-pg"
  family      = "${var.family}"                                                                              
  description = "Terraform-managed cluster parameter group for ${var.name}-${var.environment}-cluster}"

  parameter = ["${var.cluster_parameters}"]

  tags {
    Name = "${var.name}-${var.environment}"
    Project = "${var.name}"
    Environment = "${var.environment}"
  }
}

// Geneate an ID used for snapshot identifier which must be unique
resource "random_id" "this" {
  keepers = {
    id = "${aws_db_subnet_group.this.name}"
  }

  byte_length = 8
}

// Create initial DB instance
resource "aws_rds_cluster_instance" "cluster_instance_0" {
  identifier                   = "${var.identifier_prefix != "" ? format("%s-node-0", var.identifier_prefix) : format("%s-aurora-node-0", var.environment)}"
  cluster_identifier           = "${aws_rds_cluster.this.id}"
  engine                       = "${var.engine}"
  engine_version               = "${var.engine-version}"
  instance_class               = "${var.instance_class}"
  publicly_accessible          = "${var.publicly_accessible}"
  db_subnet_group_name         = "${aws_db_subnet_group.this.id}"
  db_parameter_group_name      = "${aws_db_parameter_group.this.id}"
  preferred_maintenance_window = "${var.preferred_maintenance_window}"
  apply_immediately            = "${var.apply_immediately}"
  monitoring_role_arn          = "${join("", aws_iam_role.rds-enhanced-monitoring.*.arn)}"
  monitoring_interval          = "${var.monitoring_interval}"
  auto_minor_version_upgrade   = "${var.auto_minor_version_upgrade}"
  promotion_tier               = "0"
  performance_insights_enabled = "${var.performance_insights_enabled}"

  tags {
    Name = "${var.name}-${var.environment}"
    Project = "${var.name}"
    Environment = "${var.environment}"
  }
}

// Create 'n' number of additional DB instance(s) in same cluster
resource "aws_rds_cluster_instance" "cluster_instance_n" {
  depends_on                   = ["aws_rds_cluster_instance.cluster_instance_0"]
  count                        = "${var.replica_scale_enabled ? var.replica_scale_min : var.replica_count}"
  engine                       = "${var.engine}"
  engine_version               = "${var.engine-version}"
  identifier                   = "${var.identifier_prefix != "" ? format("%s-node-%d", var.identifier_prefix, count.index + 1) : format("%s-aurora-node-%d", var.envname, count.index + 1)}"
  cluster_identifier           = "${aws_rds_cluster.this.id}"
  instance_class               = "${var.instance_class}"
  publicly_accessible          = "${var.publicly_accessible}"
  db_subnet_group_name         = "${aws_db_subnet_group.this.id}"
  db_parameter_group_name      = "${aws_db_parameter_group.this.id}"
  preferred_maintenance_window = "${var.preferred_maintenance_window}"
  apply_immediately            = "${var.apply_immediately}"
  monitoring_role_arn          = "${join("", aws_iam_role.rds-enhanced-monitoring.*.arn)}"
  monitoring_interval          = "${var.monitoring_interval}"
  auto_minor_version_upgrade   = "${var.auto_minor_version_upgrade}"
  promotion_tier               = "${count.index + 1}"
  performance_insights_enabled = "${var.performance_insights_enabled}"

  tags {
    Name = "${var.name}-${var.environment}"
    Project = "${var.name}"
    Environment = "${var.environment}"
  }
}

// Create DB Cluster
resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.identifier_prefix != "" ? format("%s-cluster", var.identifier_prefix) : format("%s-aurora-cluster", var.envname)}"
  availability_zones = ["${var.azs}"]
  engine             = "${var.engine}"

  database_name                   = "${var.database_name}"
  engine_version                  = "${var.engine-version}"
  master_username                 = "${var.username}"
  master_password                 = "${var.password}"
  final_snapshot_identifier       = "${var.final_snapshot_identifier}-${random_id.this.hex}"
  skip_final_snapshot             = "${var.skip_final_snapshot}"
  backup_retention_period         = "${var.backup_retention_period}"
  preferred_backup_window         = "${var.preferred_backup_window}"
  preferred_maintenance_window    = "${var.preferred_maintenance_window}"
  port                            = "${var.port}"
  db_subnet_group_name            = "${aws_db_subnet_group.this.id}"
  db_cluster_parameter_group_name = "${aws_rds_cluster_parameter_group.this.id}"
  vpc_security_group_ids          = ["${var.security_groups}"]
  snapshot_identifier             = "${var.snapshot_identifier}"
  storage_encrypted               = "${var.storage_encrypted}"
  apply_immediately               = "${var.apply_immediately}"

  iam_database_authentication_enabled = "${var.iam_database_authentication_enabled}"

  lifecycle {
    prevent_destroy = "true"
    ignore_changes  = [
      "availability_zones"
    ]
  }

  tags {
    Name = "${var.name}-${var.environment}"
    Project = "${var.name}"
    Environment = "${var.environment}"
  }
}

// IAM Role with policy required for Enhanced Monitoring
data "aws_iam_policy_document" "monitoring-rds-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds-enhanced-monitoring" {
  count              = "${var.monitoring_interval > 0 ? 1 : 0}"
  name               = "rds-enhanced-monitoring-${var.environment}"
  assume_role_policy = "${data.aws_iam_policy_document.monitoring-rds-assume-role-policy.json}"
}

resource "aws_iam_role_policy_attachment" "rds-enhanced-monitoring-policy-attach" {
  count      = "${var.monitoring_interval > 0 ? 1 : 0}"
  role       = "${aws_iam_role.rds-enhanced-monitoring.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

// Autoscaling
resource "aws_appautoscaling_target" "this" {
  count              = "${var.replica_scale_enabled ? 1 : 0}"
  max_capacity       = "${var.replica_scale_max}"
  min_capacity       = "${var.replica_scale_min}"
  resource_id        = "cluster:${aws_rds_cluster.this.cluster_identifier}"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  service_namespace  = "rds"
}

resource "aws_appautoscaling_policy" "autoscaling" {
  count              = "${var.replica_scale_enabled ? 1 : 0}"
  depends_on         = ["aws_appautoscaling_target.this"]
  name               = "target-metric"
  policy_type        = "TargetTrackingScaling"
  resource_id        = "cluster:${aws_rds_cluster.this.cluster_identifier}"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  service_namespace  = "rds"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }

    scale_in_cooldown  = "${var.replica_scale_in_cooldown}"
    scale_out_cooldown = "${var.replica_scale_out_cooldown}"
    target_value       = "${var.replica_scale_cpu}"
  }
}