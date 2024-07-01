# Credit for this script goes to Roland Otta [mongodb-incremental-backups](https://tech.willhaben.at/mongodb-incremental-backups-dff4c8f54d58) 

# MongoDB Backup and Restore Scripts from s3

This repository contains two Bash scripts for backing up and restoring MongoDB databases. The scripts use AWS S3 for storing the backup files and handle both full and incremental backups.

## Files

- `mongodb-backup.sh`: This script performs incremental backups of MongoDB oplog.
- `mongodb-restore.sh`: This script restores MongoDB from backup files stored in AWS S3.

## Prerequisites

- AWS CLI: Make sure you have AWS CLI installed and configured with the necessary permissions to access your S3 bucket.
- MongoDB CLI tools: Ensure you have MongoDB CLI tools (`mongodump`, `mongorestore`, etc.) installed.

## Environment Variables

Both scripts require certain environment variables to be set:

- `MONGODB_HOST`: The MongoDB server URL.
- `MONGODB_PORT`: The MongoDB server port (default is 27017).
- `MONGODB_USER`: The MongoDB username.
- `MONGODB_PWD`: The MongoDB password.
- `S3_BUCKET_NAME`: The name of the S3 bucket where backups are stored.
- `S3_BUCKET_REGION`: The AWS region of the S3 bucket.
- `S3_BACKUP_DIR`: The S3 directory path where backups are stored (used only in the restore script).

## Usage

### Backup Script (`mongodb-backup.sh`)

This script performs incremental backups of MongoDB oplog and uploads the backup files to an S3 bucket.

#### Steps:
1. Set the required environment variables.
2. Run the backup script.

```bash
export MONGODB_HOST=<your-mongodb-host>
export MONGODB_PORT=27017
export MONGODB_USER=<your-mongodb-user>
export MONGODB_PWD=<your-mongodb-password>
export S3_BUCKET_NAME=<your-s3-bucket-name>
export S3_BUCKET_REGION=<your-s3-bucket-region>

./mongodb-backup.sh

Restore Script (mongodb-restore.sh)
This script restores MongoDB from backup files stored in an S3 bucket. It performs a full restore if no previous backups are found, or an incremental restore if previous backups exist.

Steps:
Set the required environment variables.
Run the restore script.
bash
Copy code
export MONGODB_HOST=<your-mongodb-host>
export MONGODB_PORT=27017
export MONGODB_USER=<your-mongodb-user>
export MONGODB_PWD=<your-mongodb-password>
export S3_BUCKET_NAME=<your-s3-bucket-name>
export S3_BUCKET_REGION=<your-s3-bucket-region>
export S3_BACKUP_DIR=<your-s3-backup-directory>

./mongodb-restore.sh
Notes
Ensure that the AWS CLI and MongoDB CLI tools are installed and properly configured on the system where you run these scripts.
Adjust the log level in the mongodb-backup.sh script if needed.
The scripts use bsondump and mongodump to handle the backup and restoration of oplog entries.
Always test your backup and restore process in a development or staging environment before using it in production.