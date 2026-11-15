aws_region      = "eu-west-1"
project_name    = "job-matcher"
environment     = "dev"
db_app_username = "job_matcher"

# Existing bucket holding the input file. Fill in before applying.
# input_bucket_name = ""
input_key_prefix = ""

bedrock_model_id = "anthropic.claude-haiku-5-5"

schedule_expression = "cron(0 11 ? * MON *)"
schedule_timezone   = "Europe/Madrid"
schedule_enabled    = true

# alert_email = ""
