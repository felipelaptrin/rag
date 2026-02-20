resource "aws_s3_bucket" "knowledge_base" {
  bucket = "knowledge-base-${var.environment}-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "knowledge_base" {
  bucket                  = aws_s3_bucket.knowledge_base.id
  restrict_public_buckets = true
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
}
