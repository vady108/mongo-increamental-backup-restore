#!/bin/bash
set -e

# Function to initialize static parameters
function initStaticParams {
    MONGODB_SERVER=$MONGODB_HOST  # MongoDB server URL
    MONGODB_PORT=27017  # MongoDB default port
    MONGODB_USER=$MONGODB_USER  # MongoDB username
    MONGODB_PWD=$MONGODB_PWD  # MongoDB password
    S3_BUCKET_NAME=$S3_BUCKET_NAME  # S3 bucket name
    S3_BUCKET_REGION=$S3_BUCKET_REGION  # S3 bucket region

    OUTPUT_DIRECTORY=/tmp/backups  # Directory for local backups

    # Log levels
    LOG_MESSAGE_ERROR=1
    LOG_MESSAGE_WARN=2
    LOG_MESSAGE_INFO=3
    LOG_MESSAGE_DEBUG=4
    LOG_LEVEL=$LOG_MESSAGE_DEBUG  # Set log level to debug
    SCRIPT=`readlink -f ${BASH_SOURCE[0]}`
    ABSOLUTE_SCRIPT_PATH=$(cd `dirname "$SCRIPT"` && pwd)
}

# Function to log messages with different levels
function log {
    MESSAGE_LEVEL=$1
    shift
    MESSAGE="$@"

    if [ $MESSAGE_LEVEL -le $LOG_LEVEL ]; then
        echo "`date +'%Y-%m-%dT%H:%M:%S.%3N'` $MESSAGE"
    fi
}

# Initialize static parameters
initStaticParams

log $LOG_MESSAGE_INFO "[INFO] Starting incremental backup of oplog"

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIRECTORY

# Find the last backup file in S3
BACKUP_NAME=`aws s3 ls $S3_BUCKET_NAME --region $S3_BUCKET_REGION --recursive | sort | grep ".gz" | tail -n 1 | awk -F'/' '{print $4}'`
if [[ $BACKUP_NAME != "" ]]; then
    log $LOG_MESSAGE_INFO "[INFO] Last backup file found $BACKUP_NAME, downloading..."
    aws s3 cp s3://$S3_BUCKET_NAME/$BACKUP_NAME $OUTPUT_DIRECTORY --region $S3_BUCKET_REGION
    cd $OUTPUT_DIRECTORY && tar xzvf $BACKUP_NAME
else 
    log $LOG_MESSAGE_INFO "[INFO] No last backup file found"
fi

# Get the last oplog dump file
LAST_OPLOG_DUMP=`ls -t ${OUTPUT_DIRECTORY}/*.bson 2> /dev/null | head -1`

if [ "$LAST_OPLOG_DUMP" != "" ]; then
    log $LOG_MESSAGE_DEBUG "[DEBUG] Last incremental oplog backup is $LAST_OPLOG_DUMP"
    LAST_OPLOG_ENTRY=`bsondump ${LAST_OPLOG_DUMP} | grep ts | tail -1`
    if [ "$LAST_OPLOG_ENTRY" == "" ]; then
        log $LOG_MESSAGE_ERROR "[ERROR] Evaluating last backuped oplog entry with bsondump failed"
        exit 1
    else
        TIMESTAMP_LAST_OPLOG_ENTRY=`echo $LAST_OPLOG_ENTRY | jq '.ts[].t'`
        INC_NUMBER_LAST_OPLOG_ENTRY=`echo $LAST_OPLOG_ENTRY | jq '.ts[].i'`
        START_TIMESTAMP="Timestamp( ${TIMESTAMP_LAST_OPLOG_ENTRY}, ${INC_NUMBER_LAST_OPLOG_ENTRY} )"
        log $LOG_MESSAGE_DEBUG "[DEBUG] Dumping everything newer than $START_TIMESTAMP"
    fi
    log $LOG_MESSAGE_DEBUG "[DEBUG] Last backuped oplog entry: $LAST_OPLOG_ENTRY"
else
    log $LOG_MESSAGE_WARN "[WARN] No backuped oplog available. Creating initial backup"
fi

# Perform the incremental backup
if [ "$LAST_OPLOG_ENTRY" != "" ]; then
    mongodump -h $MONGODB_SERVER -u $MONGODB_USER -p $MONGODB_PWD --authenticationDatabase=admin -d local -c oplog.rs --query "{\"ts\" : { \"\$gt\": { \"\$timestamp\" : { \"t\": $TIMESTAMP_LAST_OPLOG_ENTRY, \"i\": $INC_NUMBER_LAST_OPLOG_ENTRY } } },\"o.msg\" : { \"\$ne\": \"periodic noop\"} }" -o - > ${OUTPUT_DIRECTORY}/${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_oplog.bson 
    RET_CODE=$?
else 
    TIMESTAMP_LAST_OPLOG_ENTRY=0000000000
    INC_NUMBER_LAST_OPLOG_ENTRY=0
    BACKUP_NAME=${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_full_oplog.gz
    echo "Dumping Full MongoDB database to compressed archive"
    cd /tmp/ && mongodump -h $MONGODB_SERVER -u $MONGODB_USER -p $MONGODB_PWD --readPreference=secondary
    cd /tmp/dump && rm -rf admin config local
    cd /tmp && tar czvf $BACKUP_NAME dump/
    echo "Copy dump to S3"
    aws s3 cp /tmp/$BACKUP_NAME s3://$S3_BUCKET_NAME/$BACKUP_NAME
    mongodump -h $MONGODB_SERVER -u $MONGODB_USER -p $MONGODB_PWD --authenticationDatabase=admin -d local -c oplog.rs -o - > ${OUTPUT_DIRECTORY}/${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_oplog.bson 
    RET_CODE=$?
fi

if [ $RET_CODE -gt 0 ]; then
    log $LOG_MESSAGE_ERROR "[ERROR] Incremental backup of oplog with mongodump failed with return code $RET_CODE"
fi

# Check the file size of the backup
FILESIZE=`stat --printf="%s" ${OUTPUT_DIRECTORY}/${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_oplog.bson`

if [ $FILESIZE -eq 0 ]; then
    log $LOG_MESSAGE_WARN "[WARN] No documents have been dumped with incremental backup (no changes in MongoDB since last backup?). Deleting ${OUTPUT_DIRECTORY}/${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_oplog.bson"
    rm -f ${OUTPUT_DIRECTORY}/${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_oplog.bson
else
    log $LOG_MESSAGE_INFO "[INFO] Finished incremental backup of oplog to ${OUTPUT_DIRECTORY}/${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_oplog.bson"
    log $LOG_MESSAGE_INFO "[INFO] Compressing file"
    cd ${OUTPUT_DIRECTORY} && tar czvf ${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_oplog.bson.gz ${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_oplog.bson
    aws s3 --region $S3_BUCKET_REGION cp ${OUTPUT_DIRECTORY}/${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_oplog.bson.gz s3://$S3_BUCKET_NAME/${TIMESTAMP_LAST_OPLOG_ENTRY}_${INC_NUMBER_LAST_OPLOG_ENTRY}_oplog.bson.gz 
fi
