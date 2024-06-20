resource "aiven_pg" "cloudland-pg" {
  project      = var.project_name
  service_name = "cloudland-postgres"
  cloud_name   = "do-fra"
  plan         = "startup-4"
}

resource "null_resource" "db_setup" {

  provisioner "local-exec" {
    command =  "psql  ${aiven_pg.cloudland-pg.service_uri} -f aiven_extras.sql"
  }
}

resource "aiven_kafka" "cloudland-kafka" {
  project                 = var.project_name
  cloud_name              = "do-fra"
  plan                    = "startup-2"
  service_name            = "cloudland-kafka"
  maintenance_window_dow  = "saturday"
  maintenance_window_time = "10:00:00"
  kafka_user_config {
    kafka_rest      = true
    kafka_connect   = false
    schema_registry = true
    kafka_version   = "3.7"

    kafka {
      auto_create_topics_enable  = true
      num_partitions             = 3
      default_replication_factor = 2
      min_insync_replicas        = 2
    }

    kafka_authentication_methods {
      certificate = true
    }

  }
}

resource "aiven_kafka_connect" "cloudland-kafka-connect" {
  project                 = var.project_name
  cloud_name              = "do-fra"
  plan                    = "startup-4"
  service_name            = "cloudland-kafka-connect"
  maintenance_window_dow  = "monday"
  maintenance_window_time = "10:00:00"

  kafka_connect_user_config {
    kafka_connect {
      consumer_isolation_level = "read_committed"
    }

    public_access {
      kafka_connect = false
    }
  }
}

resource "aiven_service_integration" "i1" {
  project                  = var.project_name
  integration_type         = "kafka_connect"
  source_service_name      = aiven_kafka.cloudland-kafka.service_name
  destination_service_name = aiven_kafka_connect.cloudland-kafka-connect.service_name

  kafka_connect_user_config {
    kafka_connect {
      group_id             = "connect"
      status_storage_topic = "__connect_status"
      offset_storage_topic = "__connect_offsets"
    }
  }
}

resource "aiven_kafka_connector" "kafka-pg-source" {
  project        = var.project_name
  service_name   = aiven_kafka_connect.cloudland-kafka-connect.service_name
  connector_name = "kafka-pg-source"

  config = {
    "name"                        = "kafka-pg-source"
    "connector.class"             = "io.debezium.connector.postgresql.PostgresConnector"
    "snapshot.mode"               = "initial"
    "database.hostname"           = sensitive(aiven_pg.cloudland-pg.service_host)
    "database.port"               = sensitive(aiven_pg.cloudland-pg.service_port)
    "database.password"           = sensitive(aiven_pg.cloudland-pg.service_password)
    "database.user"               = sensitive(aiven_pg.cloudland-pg.service_username)
    "database.dbname"             = "defaultdb"
    "database.server.name"        = "replicator"
    "database.ssl.mode"           = "require"
    "include.schema.changes"      = true
    "include.query"               = true
    "plugin.name"                 = "pgoutput"
    "topic.prefix"                = "pg_"
    "publication.autocreate.mode" = "all_tables"
    "decimal.handling.mode"       = "double"
    "_aiven.restart.on.failure"   = "true"
    "heartbeat.interval.ms"       = 30000
    "heartbeat.action.query"      = "INSERT INTO heartbeat (status) VALUES (1)"
  }
  depends_on = [aiven_service_integration.i1]
}
