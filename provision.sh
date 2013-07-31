#!/bin/bash

function usage {
  echo -e "usage: `basename "$0"` target_directory\n"
  exit
}

if [ "$#" -ne 1 ]; then
  usage
fi

# Versions
# Note: If these are not GA versions, you may run into issues verifying the MD5 sums.
HTTPD_VER="2.4.6"
PHP_VER="5.5.1"
MARIA_DB_VER="5.5.32"

TARGET_DIR="$1"
if [[ "$TARGET_DIR" != /* ]]; then
  echo -e "target_directory must be an absolute path.\n"
  usage
fi

TIMESTAMP=`date "+%Y-%m-%d_at_%H-%M-%S"`
TMP_DIR="/tmp/`basename $TARGET_DIR`/$TIMESTAMP"

echo "About to setup environment in $TARGET_DIR. Hit any key to continue or CTRL-C to abort..."
read

function log {
  if [ "$#" -eq 2 ]; then
    local ECHO_OPTS="$1e"
    shift
  else
    local ECHO_OPTS='-e'
  fi
  local MSG="$1"
  local LOGFILE="$TMP_DIR/install.log"
  echo "$ECHO_OPTS" "$MSG" >> "$LOGFILE"
  echo "$ECHO_OPTS" "$MSG"
}

function abort {
  local EXIT_CODE="$1"
  local ERROR_MESSAGE="$2"
  log "\n$ERROR_MESSAGE"
  log "Aborting environment setup."
  exit "$EXIT_CODE"
}

function download {
  local SRC="$1"
  local DEST="$2"
  if [ -z "$DEST" ]; then
    DEST=`basename $SRC`
  fi

  local STATUS=`curl -L -s -q -w "%{http_code}" -o "$DEST" "$SRC"`
  if [ "$?" -ne 0 ]; then
    abort 10 "Download of $DEST failed with curl exit code $?!"
  fi
  if [ "$STATUS" -ne 200 ]; then
    abort 20 "Download of $DEST failed with curl receiving HTTP status code $STATUS"
  fi
}

function verify_md5 {
  local FILENAME="$1"
  local EXPECTED="$2"

  if [ `which md5` ]; then
    local ACTUAL=`md5 -q $FILENAME`
  elif [ `which md5sum` ]; then
    local ACTUAL=`md5sum $FILENAME | cut -d ' ' -f 1`
  else
    abort 30 "MD5 Digest command not found. Unable to verify package integrity!"
  fi

  if [ "$EXPECTED" != "$ACTUAL" ]; then
    abort 40 "MD5 Digest for $FILENAME is invalid! Expected '$EXPECTED' but got '$ACTUAL'."
  fi
}

echo -n "Creating scratch directory $TMP_DIR... "
mkdir -p "$TMP_DIR"
echo "complete."
echo

cd "$TMP_DIR"

function install_apache {
  local APACHE_MIRRORS_FILE="apache-mirrors.txt"
  log -n "Determining Apache mirrors to use... "
  download 'http://www.apache.org/dyn/closer.cgi' "$APACHE_MIRRORS_FILE"
  local APACHE_MIRROR=`grep -A 2 'We suggest the following mirror' "$APACHE_MIRRORS_FILE" | tail -n 1 | awk '{ print $2 }' | cut -d \" -f 2`
  local APACHE_BACKUP_MIRROR=`grep -A 1 'verify your downloads or if no other mirrors are working.' "$APACHE_MIRRORS_FILE" | tail -n 1 | awk '{ print $3 }' | cut -d \" -f 2`
  log "complete."

  log
  log "Using mirror $APACHE_MIRROR for source code packages."
  log "Using mirror $APACHE_BACKUP_MIRROR for package verification."
  log

  log -n "Downloading Apache HTTP Server $HTTPD_VER package... "
  local HTTPD_BASE="httpd-$HTTPD_VER"
  local HTTPD_ARCHIVE="$HTTPD_BASE.tar.gz"
  download "$APACHE_MIRROR/httpd/$HTTPD_ARCHIVE"
  log "complete."

  log -n "Verifying integrity of Apache HTTP Server $HTTPD_VER package... "
  download "$APACHE_BACKUP_MIRROR/httpd/$HTTPD_ARCHIVE.md5"
  verify_md5 "$HTTPD_ARCHIVE" "`awk '{ print $1 }' $HTTPD_ARCHIVE.md5`"
  log "complete."

  log -n "Downloading Apache HTTP Server $HTTPD_VER APR and APR-Util package... "
  local HTTPD_APR_ARCHIVE="$HTTPD_BASE-deps.tar.gz"
  download "$APACHE_MIRROR/httpd/$HTTPD_APR_ARCHIVE"
  log "complete."

  log -n "Verifying integrity of Apache HTTP Server $HTTPD_VER APR and APR-Util package... "
  download "$APACHE_BACKUP_MIRROR/httpd/$HTTPD_APR_ARCHIVE.md5"
  verify_md5 "$HTTPD_APR_ARCHIVE" "`awk '{ print $1 }' $HTTPD_APR_ARCHIVE.md5`"
  log "complete."
  log
}

function install_php {
  log -n "Downloading PHP $PHP_VER package... "
  local PHP_BASE="php-$PHP_VER"
  local PHP_ARCHIVE="$PHP_BASE.tar.gz"
  local PHP_MIRRORS_FILE="php-mirrors.txt"
  download "http://php.net/get/$PHP_ARCHIVE/from/a/mirror" "$PHP_MIRRORS_FILE"
  local PHP_MIRROR_LINE=`grep -A 1 caret "$PHP_MIRRORS_FILE" | head -n 2 | tail -1`
  local PHP_HOSTNAME=`echo "$PHP_MIRROR_LINE" | awk -F '">|</a' '{ print $2 }'`
  local PHP_PATH=`echo "$PHP_MIRROR_LINE" | cut -d \" -f 2`
  download "http://$PHP_HOSTNAME$PHP_PATH" "$PHP_ARCHIVE"
  log "complete."

  log -n "Verifying integrity of PHP $PHP_VER package... "
  download "http://php.net/downloads.php"
  verify_md5 "$PHP_ARCHIVE" "`grep -A 1 \"$PHP_VER (tar.gz)\" downloads.php | tail -n 1 | awk '{ print $3 }' | cut -d '<' -f 1`"
  log "complete."
  log
}

function install_mariadb {
  log -n "Downloading MariaDB $MARIA_DB_VER package..."
  local MARIA_DB_RELEASE_NUM_FILE='maria_db_release.html'
  download "https://downloads.mariadb.org/mariadb/$MARIA_DB_VER/" "$MARIA_DB_RELEASE_NUM_FILE"
  local MARIA_DB_RELEASE=`grep data-release "$MARIA_DB_RELEASE_NUM_FILE" | cut -d \" -f 2`
  local MARIA_DB_RELEASE_DETAIL='maria_db_release_detail.html'
  download "https://downloads.mariadb.org/mariadb/+files/?release=$MARIA_DB_RELEASE&file_type=source" "$MARIA_DB_RELEASE_DETAIL"
  local MARIA_DB_DOWNLOAD_URL="https://downloads.mariadb.org/f/`grep '"filename"' $MARIA_DB_RELEASE_DETAIL | awk -F 'interstitial|">' '{ print $3 }'`"
  local MARIA_DB_ARCHIVE="mariadb-$MARIA_DB_VER.tar.gz"
  download $MARIA_DB_DOWNLOAD_URL "$MARIA_DB_ARCHIVE"
  log "complete."

  log -n "Verifying integrity of MariaDB $MARIA_DB_VER package..."
  verify_md5 "$MARIA_DB_ARCHIVE" `grep 'md5sum:' $MARIA_DB_RELEASE_DETAIL | awk '{ print $2 }'`
  log "complete."
  log
}

install_apache
install_php
install_mariadb
