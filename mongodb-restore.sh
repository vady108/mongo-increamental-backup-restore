#!/bin/bash

# ENVs
LOCAL_DIRECTORY="/tmp"
FULL_BACKUP_FILE="${S3_BACKUP_DIR}0000000000_0_full_oplog.gz"
FULL_BSON_BACKUP_FILE="${S3_BACKUP_DIR}0000000000_0_oplog.bson.gz"
LAST_BACKUP_STATUS_FILE="${S3_BACKUP_DIR}LastBackUpStatus.txt"



if [ "$S3_BACKUP_DIR" == "" ]; then
   echo "usage: restoreOpLogs.sh No S3_BACKUP_DIR env exists. Please check."
   exit 1
fi

if [ "$S3_BUCKET_REGION" == "" ]; then
   echo "usage: restoreOpLogs.sh No S3_BUCKET_REGION env exists. Please check."
   exit 1
fi

if [ "$MONGODB_USER" == "" ]; then
   echo "usage: restoreOpLogs.sh No MONGODB_USER env exists. Please check."
   exit 1
fi

if [ "$MONGODB_PWD" == "" ]; then
   echo "usage: restoreOpLogs.sh No MONGODB_PWD env exists. Please check."
   exit 1
fi

if [ "$MONGODB_HOST" == "" ]; then
   echo "usage: restoreOpLogs.sh No MONGODB_HOST env exists. Please check."
   exit 1
fi

#################################
mkdir -p /tmp/emptyDirForOpRestore

if aws s3 ls $LAST_BACKUP_STATUS_FILE; then
    echo "Full Backup exists."
else
   echo "No LAST_BACKUP_STATUS file exits So have to do full restore and full oplog restore...."

   echo "################ FULL RESTORE STARTED ################"

   # Copying the full backup file from s3 to local LOCAL_DIRECTORY(/tmp) directory.
   aws s3 cp $FULL_BACKUP_FILE $LOCAL_DIRECTORY --region $S3_BUCKET_REGION
   
   # Extracting the file name from S3 URL.
   fileName=`echo $FULL_BACKUP_FILE |  rev | cut -d'/' -f1 | rev`
   echo "FULL_BACKUP_FILE: ${fileName}"

   # Go to LOCAL_DIRECTORY, uncompressing the FULL_BACKUP file and removing the FULL_BACKUP.gz after that.
   cd $LOCAL_DIRECTORY && tar xzvf $fileName  && rm -rf $fileName
   
   # Here we are performing a full restore, using --drop to get rid of the existing collection before restoring it.
   mongorestore -h $MONGODB_HOST -u $MONGODB_USER -p $MONGODB_PWD --authenticationDatabase=admin --drop
   
   echo "################ FULL RESTORE COMPLETED ################"
   

   echo "################ FULL OPLOG RESTORE STARTED ################"

   # Copying the full oplog backup file from s3 to local LOCAL_DIRECTORY(/tmp) directory.
   aws s3 cp $FULL_BSON_BACKUP_FILE $LOCAL_DIRECTORY --region $S3_BUCKET_REGION
   
   # Extracting the file name from S3 URL.
   fileName=`echo $FULL_BSON_BACKUP_FILE |  rev | cut -d'/' -f1 | rev`
   echo "FULL_OPLOG_FILE: ${fileName}"

   # Go to LOCAL_DIRECTORY, uncompressing the FULL_BACKUP file and removing the FULL_BACKUP.gz after that.
   cd $LOCAL_DIRECTORY && tar xzvf $fileName && OPLOG="${fileName%.gz}" && rm -rf $fileName
   OPLOG_LIMIT=`date +%s`
   # Here we are performing a full oplog restore.
   mongorestore -h $MONGODB_HOST -u $MONGODB_USER -p $MONGODB_PWD --authenticationDatabase=admin --oplogFile $OPLOG --oplogReplay /tmp/emptyDirForOpRestore --oplogLimit=$OPLOG_LIMIT
   
   echo "################ FULL OPLOG RESTORE STARTED ################"

   # Updating the last OPLOG.gz file name into 
   echo $fileName | aws s3 cp - $LAST_BACKUP_STATUS_FILE --region $S3_BUCKET_REGION
   
fi

# Getting the LAST_BACKUP_STATUS. That is basiclly TIMESTAMP.gz file txt
LAST_BACKUP_STATUS=$(aws s3 cp $LAST_BACKUP_STATUS_FILE - --region $S3_BUCKET_REGION)
LAST_OPLOG_BACKUP_TIMESTAMP=`echo $LAST_BACKUP_STATUS | cut -d "_" -f 1 | cut -d "/" -f 1`
echo "LAST OPLOG BACKUP TIMESTAMP: ${LAST_OPLOG_BACKUP_TIMESTAMP}"

# Restoring the rest of the OPLOG_BACKUP file which is greater than LAST_OPLOG_BACKUP_TIMESTAMP...
for OPLOG_gz in `aws s3 ls $S3_BACKUP_DIR --recursive | sort | grep bson.gz | awk -F'/' '{print $4}'`; do
   
   # Getting the OPLOG TIMESTAMP from File name...
   OPLOG_TIMESTAMP=`echo $OPLOG_gz | rev | cut -d "/" -f 1 | rev | cut -d "_" -f 1`

   # Checking if OPLOG_TIMESTAMP greater than LAST_OPLOG_BACKUP_TIMESTAMP
   if [ $OPLOG_TIMESTAMP -gt $LAST_OPLOG_BACKUP_TIMESTAMP ]; then
      
      echo "################ INCREMENTAL OPLOG RESTORE STARTED ################"
      
      # Copy OPLOG_gz file to local directory..
      aws s3 cp $S3_BACKUP_DIR$OPLOG_gz $LOCAL_DIRECTORY --region $S3_BUCKET_REGION
      
      # Go to LOCAL_DIRECTORY, uncompressing the OPLOG_gz file and removing the OPLOG_gz.gz after that.
      cd $LOCAL_DIRECTORY && tar xzvf $OPLOG_gz && OPLOG="${OPLOG_gz%.gz}" && rm -rf $OPLOG_gz
      OPLOG_LIMIT=`date +%s`
      echo "OPLOG_FILE: $OPLOG"
      mongorestore -h $MONGODB_HOST -u $MONGODB_USER -p $MONGODB_PWD --authenticationDatabase=admin --oplogFile $OPLOG --oplogReplay /tmp/emptyDirForOpRestore --oplogLimit=$OPLOG_LIMIT
      
      echo "################ INCREMENTAL OPLOG RESTORE COMPLETED ################"

      # Updating the last OPLOG.gz file name into 
      echo $OPLOG_gz | aws s3 cp - $LAST_BACKUP_STATUS_FILE --region $S3_BUCKET_REGION

      # Removing the the OPLOG file.
      rm -rf $OPLOG
   fi
done